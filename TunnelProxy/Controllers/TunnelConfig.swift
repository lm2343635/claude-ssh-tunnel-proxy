import Foundation

/// App configuration, persisted as JSON in Application Support. Holds the list of
/// SSH server profiles plus app-global tunnel settings. Secrets are NOT stored
/// here — they live in the Keychain (see `KeychainStore`).
struct TunnelConfig: Codable, Equatable {
    static let minimumWatchdogInterval = 15
    static let defaultWatchdogInterval = 30

    var servers: [ServerProfile] = []
    /// The currently selected server's id.
    var selectedServerID: UUID?

    // App-global tunnel settings (independent of which server is active).
    var socksPort: Int = 1080
    var httpProxyPort: Int = 8118
    /// Empty by default; the UI fills this with the primary (default-route)
    /// network service on first open.
    var networkService: String = ""
    var watchdogInterval: Int = Self.defaultWatchdogInterval

    // MARK: - Server helpers

    var selectedServer: ServerProfile? {
        guard let id = selectedServerID else { return servers.first }
        return servers.first { $0.id == id } ?? servers.first
    }

    mutating func upsert(_ server: ServerProfile) {
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
        } else {
            servers.append(server)
        }
        if selectedServerID == nil { selectedServerID = server.id }
    }

    mutating func remove(_ serverID: UUID) {
        servers.removeAll { $0.id == serverID }
        KeychainStore.deleteSecret(for: serverID)
        if selectedServerID == serverID {
            selectedServerID = servers.first?.id
        }
    }

    // MARK: - Persistence

    static func load() -> TunnelConfig {
        guard let data = try? Data(contentsOf: AppPaths.configURL),
              var config = try? JSONDecoder().decode(TunnelConfig.self, from: data) else {
            return TunnelConfig()
        }
        // Older builds allowed very short watchdog intervals. Those intervals
        // amplified a brief DNS outage into a tight probe/reconnect loop, so
        // migrate existing values to the supported floor once on load.
        if config.watchdogInterval < minimumWatchdogInterval {
            config.watchdogInterval = minimumWatchdogInterval
            try? config.save()
        }
        return config
    }

    func save() throws {
        AppPaths.ensureSupportDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: AppPaths.configURL, options: .atomic)
    }

    // MARK: - Validation

    /// Reason the config can't be used to connect, or nil when it's ready.
    var connectError: String? {
        guard let server = selectedServer else { return String(localized: "No server selected") }
        if let err = server.validationError { return err }
        guard (1...65535).contains(socksPort) else { return String(localized: "SOCKS port must be 1–65535") }
        guard (1...65535).contains(httpProxyPort) else { return String(localized: "HTTP proxy port must be 1–65535") }
        if socksPort == httpProxyPort { return String(localized: "Ports must differ") }
        if watchdogInterval < Self.minimumWatchdogInterval {
            return String(localized: "Watchdog interval must be at least 15 seconds")
        }
        return nil
    }

    var canConnect: Bool { connectError == nil }
}
