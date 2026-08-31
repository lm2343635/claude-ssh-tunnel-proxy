import Foundation
import Darwin

/// Natively manages the tunnel pipeline that the shell scripts used to run:
///
///   ssh -N -D <socksPort> <host>   (SOCKS5 proxy)
///        │
///        ▼
///   privoxy (bundled)  forward-socks5 / 127.0.0.1:<socksPort>  (HTTP proxy on <httpPort>)
///
/// Both children are owned by this process (foreground, not forked), so quitting
/// the app or calling `stop()` tears them down cleanly. A background watchdog
/// probes the SOCKS port and relaunches ssh if it drops.
///
/// This type is an actor: connect/stop/watchdog all mutate child-process state,
/// and serializing them avoids races (e.g. a watchdog relaunch colliding with a
/// user-initiated stop).
actor TunnelEngine {

    enum Health: Equatable {
        case proxyOK        // HTTP proxy reachable end-to-end
        case tunnelOnly     // SOCKS up but HTTP proxy failed
        case down           // nothing reachable
    }

    private var sshProcess: Process?
    private var privoxyProcess: Process?
    private var watchdogTask: Task<Void, Never>?
    private var config = TunnelConfig()
    private var server = ServerProfile()
    /// Secret (password or key passphrase) for the active server, if any.
    private var secret: String?

    private let sshPath = "/usr/bin/ssh"
    private let curlPath = "/usr/bin/curl"

    // Watchdog state. Public HTTP probes are telemetry only; SSH process and
    // listener ownership are the authoritative liveness signals.
    private var consecutiveProbeFailures = 0
    private var reconnectAttempt = 0
    private var nextReconnectAt = Date.distantPast

    // MARK: - Lifecycle

    /// Start (or restart) the full pipeline for a given server. The secret, when
    /// present, is fed to ssh via a bundled SSH_ASKPASS helper.
    func connect(config: TunnelConfig, server: ServerProfile, secret: String?, watchdog: Bool) async -> Health {
        self.config = config
        self.server = server
        self.secret = secret
        log("Starting SSH tunnel to \(server.sshDestination)…")

        stopWatchdog()
        startSSH()
        // Give ssh a moment to establish the dynamic forward.
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        startPrivoxy()
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let health = await checkHealth()
        switch health {
        case .proxyOK: log("Tunnel + proxy started successfully")
        case .tunnelOnly:
            await describeForeignListener(on: config.httpProxyPort, expected: privoxyProcess)
            log("Tunnel OK but owned proxy failed")
        case .down:
            await describeForeignListener(on: config.socksPort, expected: sshProcess)
            await describeForeignListener(on: config.httpProxyPort, expected: privoxyProcess)
            log("Tunnel failed to start")
        }

        // Only arm the watchdog when something actually came up. Arming it on a
        // `.down` connect leaves a background task relaunching ssh into the same
        // (often occupied) port forever — the endless-loop bug. On `.down` we tear
        // down whatever partially started so we don't leak a half-open ssh/privoxy.
        if watchdog, health != .down {
            startWatchdog()
        } else if health == .down {
            terminate(&privoxyProcess, name: "privoxy")
            terminate(&sshProcess, name: "ssh")
        }
        return health
    }

    /// Tear down watchdog, privoxy, and ssh.
    func stop() {
        stopWatchdog()
        terminate(&privoxyProcess, name: "privoxy")
        terminate(&sshProcess, name: "ssh")
        log("Tunnel and proxy stopped")
    }

    // MARK: - SSH

    private func startSSH() {
        terminate(&sshProcess, name: "ssh")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: sshPath)

        var args = [
            "-N",                                   // no remote command
            "-o", "StrictHostKeyChecking=no",
            // Keepalive tuned for lossy carrier (China Telecom) links: probe often
            // enough to keep NAT/CGNAT mappings alive (they recycle idle flows ~60s),
            // but tolerate a wide burst-loss window before declaring the link dead.
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=6",          // ~90s of loss tolerated, not 30s
            "-o", "TCPKeepAlive=yes",               // OS-level keepalive as a backstop
            // Do NOT compress: on high-loss links -C amplifies latency sensitivity and
            // buys little for already-encrypted/compressed HTTPS traffic.
            "-o", "Compression=no",
            "-o", "IPQoS=throughput",               // avoid low-latency DSCP throttling
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ConnectTimeout=10",
            "-p", "\(server.port)",
            "-D", "\(config.socksPort)",
        ]

        var env = ProcessInfo.processInfo.environment
        env["HOME"] = NSHomeDirectory()

        switch server.authMethod {
        case .agent:
            // Non-interactive: rely on agent/default keys, never prompt.
            args += ["-o", "BatchMode=yes"]
        case .keyFile:
            if !server.keyPath.isEmpty {
                args += ["-i", (server.keyPath as NSString).expandingTildeInPath,
                         "-o", "IdentitiesOnly=yes"]
            }
            if let secret, !secret.isEmpty {
                // Encrypted key: feed the passphrase via the askpass helper.
                configureAskpass(&args, &env)
            } else {
                args += ["-o", "BatchMode=yes"]
            }
        case .password:
            // Force password auth and feed it via the askpass helper.
            args += [
                "-o", "PreferredAuthentications=password",
                "-o", "PubkeyAuthentication=no",
                "-o", "NumberOfPasswordPrompts=1",
            ]
            configureAskpass(&args, &env)
        }

        args.append(server.sshDestination)
        p.arguments = args
        p.environment = env
        redirectOutput(of: p, tag: "ssh")
        do {
            try p.run()
            sshProcess = p
        } catch {
            log("Failed to launch ssh: \(error.localizedDescription)")
        }
    }

    /// Wire ssh to read the secret from our bundled askpass helper. ssh calls the
    /// program in SSH_ASKPASS when it needs a password/passphrase; the helper
    /// echoes back what we place in TP_ASKPASS_SECRET.
    private func configureAskpass(_ args: inout [String], _ env: inout [String: String]) {
        guard let helper = AppPaths.askpassHelper,
              FileManager.default.isExecutableFile(atPath: helper.path),
              let secret else {
            log("askpass helper unavailable; ssh may fail to authenticate")
            return
        }
        env["SSH_ASKPASS"] = helper.path
        env["SSH_ASKPASS_REQUIRE"] = "force"   // use askpass even with a TTY
        env["TP_ASKPASS_SECRET"] = secret
        env["DISPLAY"] = env["DISPLAY"] ?? ":0" // older ssh requires DISPLAY set
        // Detach from any controlling terminal so ssh uses askpass, not the tty.
        args += ["-o", "BatchMode=no"]
    }

    // MARK: - Privoxy (bundled)

    private func startPrivoxy() {
        terminate(&privoxyProcess, name: "privoxy")
        guard let privoxy = AppPaths.bundledPrivoxy,
              FileManager.default.isExecutableFile(atPath: privoxy.path) else {
            log("Bundled privoxy not found")
            return
        }
        // Write a fresh config each connect.
        let conf = """
        listen-address 127.0.0.1:\(config.httpProxyPort)
        forward-socks5 / 127.0.0.1:\(config.socksPort) .
        # Keep privoxy quiet and self-contained.
        toggle 1
        enable-remote-toggle 0
        """
        AppPaths.ensureSupportDirectory()
        do {
            try conf.write(to: AppPaths.privoxyConfigURL, atomically: true, encoding: .utf8)
        } catch {
            log("Failed to write privoxy config: \(error.localizedDescription)")
            return
        }

        let p = Process()
        p.executableURL = privoxy
        // --no-daemon so we own the process; pass our generated config.
        p.arguments = ["--no-daemon", AppPaths.privoxyConfigURL.path]
        redirectOutput(of: p, tag: "privoxy")
        do {
            try p.run()
            privoxyProcess = p
        } catch {
            log("Failed to launch privoxy: \(error.localizedDescription)")
        }
    }

    // MARK: - Health checks

    /// Probe local pipeline ownership. Public endpoints are deliberately not
    /// part of this health decision: a DNS/API outage must not make us tear down
    /// an otherwise healthy SSH session.
    func checkHealth() async -> Health {
        guard await processOwnsListener(sshProcess, port: config.socksPort) else {
            return .down
        }
        return await processOwnsListener(privoxyProcess, port: config.httpProxyPort)
            ? .proxyOK : .tunnelOnly
    }

    /// A process merely being alive is not enough: a launchd-managed Homebrew
    /// Privoxy can race our bundled child for the same port. Require the listener
    /// PID to be the exact child this engine launched.
    private func processOwnsListener(_ process: Process?, port: Int) async -> Bool {
        guard let process, process.isRunning else { return false }
        let pid = process.processIdentifier
        let holder = await Task.detached { PortInspector.holder(ofPort: port) }.value
        return holder?.pid == pid
    }

    private func describeForeignListener(on port: Int, expected: Process?) async {
        let expectedPID = expected?.processIdentifier
        let holder = await Task.detached { PortInspector.holder(ofPort: port) }.value
        guard let holder, holder.pid != expectedPID else { return }
        log("Port \(port) is owned by \(holder.command) (PID \(holder.pid), \(holder.path)); refusing to treat it as our proxy")
    }

    /// Fetch the current exit IP through the HTTP proxy, or nil if unreachable.
    func exitIP() async -> String? {
        guard let out = await curl([
            "-s", "--max-time", "5",
            "-x", "http://127.0.0.1:\(config.httpProxyPort)",
            "https://api.ipify.org",
        ]) else { return nil }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
            ? trimmed : nil
    }

    /// Round-trip latency to the active SSH server, in milliseconds, or nil if it
    /// can't be reached. Measured as a TCP connect time to `host:port` — the same
    /// endpoint the tunnel rides on — which needs no live control socket and works
    /// for any auth method. Runs off the actor's executor via a detached task.
    func latencyMS() async -> Int? {
        let host = server.host
        let port = server.port
        guard !host.isEmpty else { return nil }
        return await Task.detached(priority: .utility) {
            Self.tcpConnectMS(host: host, port: port, timeout: 3)
        }.value
    }

    /// Blocking TCP-connect timing to `host:port`. Returns elapsed milliseconds on
    /// a successful connect, nil on failure/timeout. Uses a non-blocking socket +
    /// `poll` so a dead host times out instead of hanging.
    nonisolated private static func tcpConnectMS(host: String, port: Int, timeout: TimeInterval) -> Int? {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
                             ai_protocol: IPPROTO_TCP, ai_addrlen: 0,
                             ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let info = res else { return nil }
        defer { freeaddrinfo(res) }

        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        // Non-blocking connect so we can bound the wait with poll().
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let start = DispatchTime.now()
        let rc = Darwin.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
        if rc == 0 {
            return Int(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
        }
        guard errno == EINPROGRESS else { return nil }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&pfd, 1, Int32(timeout * 1000))
        guard ready > 0 else { return nil }   // 0 = timeout, <0 = error

        // Connected only if SO_ERROR is clear.
        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0, soError == 0 else { return nil }
        return Int(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }

    private func curl(_ args: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: curlPath)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            do {
                try p.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            continuation.resume(returning: String(data: data, encoding: .utf8))
        }
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        stopWatchdog()
        consecutiveProbeFailures = 0
        reconnectAttempt = 0
        nextReconnectAt = .distantPast
        let seconds = max(TunnelConfig.minimumWatchdogInterval, config.watchdogInterval)
        let interval = UInt64(seconds) * 1_000_000_000
        watchdogTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { break }
                await self.watchdogTick()
            }
        }
        log("Watchdog started (every \(seconds)s)")
    }

    private func watchdogTick() async {
        // OpenSSH's ServerAliveInterval/ServerAliveCountMax is responsible for
        // deciding whether the remote transport is dead. Restart immediately
        // only when that child has exited; a public DNS/API miss is not proof.
        guard sshProcess?.isRunning == true else {
            await reconnectSSH(reason: "SSH process exited")
            return
        }

        let port = config.socksPort
        let ourPID = sshProcess?.processIdentifier
        let holder = await Task.detached { PortInspector.holder(ofPort: port) }.value
        guard let holder, holder.pid == ourPID else {
            if let holder {
                log("SOCKS port \(port) is held by \(holder.command) (PID \(holder.pid)), not our SSH child — watchdog paused")
                stopWatchdog()
            } else {
                await reconnectSSH(reason: "SSH child is not listening on port \(port)")
            }
            return
        }

        if reconnectAttempt > 0 {
            reconnectAttempt = 0
            nextReconnectAt = .distantPast
            log("SSH tunnel recovered after delayed startup")
        }

        // End-to-end reachability remains useful diagnostics, but it never tears
        // down SSH. This avoids a single ipify/DNS outage creating a reconnect
        // storm on otherwise healthy carrier links.
        if await socksProbeOK() {
            if consecutiveProbeFailures > 0 {
                log("End-to-end probe recovered after \(consecutiveProbeFailures) miss(es)")
            }
            consecutiveProbeFailures = 0
        } else {
            consecutiveProbeFailures += 1
            if consecutiveProbeFailures == 1 || consecutiveProbeFailures % 4 == 0 {
                log("End-to-end probe unavailable (\(consecutiveProbeFailures) consecutive); SSH remains up")
            }
        }
    }

    private func reconnectSSH(reason: String) async {
        let now = Date()
        guard now >= nextReconnectAt else { return }

        reconnectAttempt += 1
        log("\(reason); reconnecting SSH (attempt \(reconnectAttempt))…")
        startSSH()
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        if await processOwnsListener(sshProcess, port: config.socksPort) {
            reconnectAttempt = 0
            nextReconnectAt = .distantPast
            consecutiveProbeFailures = 0
            log("SSH tunnel recovered")
            return
        }

        // Avoid DNS failures or an unavailable carrier link becoming a tight
        // process-spawn loop. The watchdog tick may be slower than this delay;
        // the date gate still guarantees the configured minimum backoff.
        let delays: [TimeInterval] = [5, 15, 30, 60]
        let delay = delays[min(reconnectAttempt - 1, delays.count - 1)]
        nextReconnectAt = Date().addingTimeInterval(delay)
        log("SSH reconnect failed; next attempt in at least \(Int(delay))s")
    }

    /// One SOCKS liveness probe through the tunnel. Short timeout so a stalled
    /// probe doesn't stretch the watchdog cycle on a slow link.
    private func socksProbeOK() async -> Bool {
        await curl([
            "-s", "--max-time", "4",
            "--socks5-hostname", "127.0.0.1:\(config.socksPort)",
            "https://api.ipify.org",
        ])?.range(of: #"\d+\.\d+"#, options: .regularExpression) != nil
    }

    private func stopWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    // MARK: - Process helpers

    private func terminate(_ process: inout Process?, name: String) {
        guard let p = process else { return }
        if p.isRunning {
            p.terminate()
            // Give it a beat; force-kill if still alive.
            let deadline = Date().addingTimeInterval(3)
            while p.isRunning && Date() < deadline {
                usleep(50_000)
            }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
        process = nil
    }

    /// Append a child's stdout/stderr into the shared log file.
    private func redirectOutput(of process: Process, tag: String) {
        let pipe = Pipe()
        let streamID = UUID()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                TunnelLog.flush(streamID: streamID, tag: tag)
            } else {
                TunnelLog.appendChildData(data, streamID: streamID, tag: tag)
            }
        }
    }

    // MARK: - Logging

    nonisolated func log(_ message: String) {
        TunnelLog.append(message)
    }
}

/// Serial, append-only writer shared by engine events and child-process output.
/// The previous implementation kept several independently seeked file handles;
/// concurrent SSH/Privoxy/app writes could overwrite or splice each other.
private enum TunnelLog {
    private static let queue = DispatchQueue(label: "TunnelProxy.tunnel-log")
    private static var childBuffers: [UUID: Data] = [:]

    static func append(_ message: String) {
        queue.async { writeLine(message) }
    }

    static func appendChildData(_ data: Data, streamID: UUID, tag: String) {
        queue.async {
            var buffer = childBuffers[streamID, default: Data()]
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[..<newline]
                buffer.removeSubrange(...newline)
                let line = String(decoding: lineData, as: UTF8.self)
                    .trimmingCharacters(in: .newlines)
                if !line.isEmpty { writeLine("[\(tag)] \(line)") }
            }
            childBuffers[streamID] = buffer
        }
    }

    static func flush(streamID: UUID, tag: String) {
        queue.async {
            if let remainder = childBuffers.removeValue(forKey: streamID), !remainder.isEmpty {
                let line = String(decoding: remainder, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { writeLine("[\(tag)] \(line)") }
            }
        }
    }

    private static func writeLine(_ message: String) {
        AppPaths.ensureSupportDirectory()
        let line = "\(timestamp())  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fd = Darwin.open(AppPaths.logURL.path, O_WRONLY | O_CREAT | O_APPEND,
                             mode_t(S_IRUSR | S_IWUSR))
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(fd, base.advanced(by: offset), rawBuffer.count - offset)
                if count <= 0 { break }
                offset += count
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}
