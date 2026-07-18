import SwiftUI

/// Thin `Settings` scene (⌘,). The full configuration surface now lives in the
/// unified main window's tabs (`SettingsTab`, `ToolsTab`).
/// Rather than host a second copy of those forms, ⌘, just opens/raises the main
/// window on the Settings tab, so there's a single source of truth.
struct SettingsView: View {
    @EnvironmentObject var controller: TunnelController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Effectively invisible: this scene exists only to intercept ⌘, and the
        // Settings menu item, redirect to the main window's Settings tab, then
        // close itself so the placeholder never lingers on screen.
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                controller.requestedTab = .settings
                openWindow(id: "main")
                TunnelUI.activateApp()
                closeSettingsWindow()
            }
    }

    /// Close the (already-open) Settings scene window on the next runloop tick so
    /// it doesn't stay up behind/next to the main window.
    private func closeSettingsWindow() {
        DispatchQueue.main.async {
            // The Settings scene window is the one titled for Settings; identify
            // it by title rather than key state (the main window becomes key).
            for window in NSApp.windows
            where window.title.localizedCaseInsensitiveContains("Settings")
                || window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true {
                window.close()
            }
        }
    }
}

// MARK: - Settings tab

/// The merged Settings tab (old **Tunnel** + **Advanced**), redesigned as a
/// 2-column grid of Control-Center tiles. **Settings apply in real time — there
/// is no Save button.** Toggles/pickers persist through the controller (their
/// own `didSet`, or `config`'s `onChange`); numeric fields commit on submit /
/// focus-loss with validation surfaced as an inline orange caption.
struct SettingsTab: View {
    @EnvironmentObject var controller: TunnelController

    @State private var deps: [Dependency] = []
    @State private var networkServiceOptions: [String] = []
    @State private var confirmClearStats = false

    private let columns = [GridItem(.flexible(), spacing: 11),
                           GridItem(.flexible(), spacing: 11)]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            TabHeader(title: "Settings") {
                Text("Changes apply immediately")
                    .font(.system(size: 11)).foregroundStyle(DS.secondaryText)
            }

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 11) {
                    portsTile
                    startupTile
                    macosTile
                    menuBarTile
                    runtimeTile
                    statisticsTile
                    filesTile.gridCellColumns(2)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(DS.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Real-time persistence: any config field change writes config.json and
        // re-checks status (ports / network service affect the live proxy).
        .onChange(of: controller.config) { _, _ in
            controller.saveConfig()
            controller.refreshStatus()
        }
        .onAppear {
            refreshDependencies()
            loadNetworkServices()
        }
        .confirmationDialog("Clear all recorded statistics?",
                            isPresented: $confirmClearStats, titleVisibility: .visible) {
            Button("Clear statistics", role: .destructive) { controller.clearStatistics() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all recorded traffic history.")
        }
    }

    // MARK: Tiles

    private var portsTile: some View {
        SettingsTile("Ports") {
            SettingsRow.field("SOCKS Port", $controller.config.socksPort)
            SettingsRow.field("HTTP Proxy Port", $controller.config.httpProxyPort)
            inlineError
        }
    }

    private var startupTile: some View {
        SettingsTile("Startup") {
            SettingsRow.toggle("Launch at login", $controller.launchAtLogin)
            SettingsRow.toggle("Auto-connect on launch", $controller.autoConnectOnLaunch)
        }
    }

    private var macosTile: some View {
        SettingsTile("macOS") {
            SettingsRow.picker("Network Service", selection: $controller.config.networkService) {
                ForEach(networkServiceOptions, id: \.self) { service in
                    Text(service).tag(service)
                }
                // Preserve a saved-but-unlisted value (e.g. an unplugged adapter).
                if !controller.config.networkService.isEmpty,
                   !networkServiceOptions.contains(controller.config.networkService) {
                    Text("\(controller.config.networkService) (unavailable)")
                        .tag(controller.config.networkService)
                }
            }
            SettingsRow.toggle("Auto-reconnect (watchdog)", $controller.watchdogEnabled)
            SettingsRow.field("Watchdog Interval (s)", $controller.config.watchdogInterval)
        }
    }

    private var menuBarTile: some View {
        SettingsTile("Menu Bar") {
            SettingsRow.toggle("Show menu bar icon", Binding(
                get: { controller.showMenuBarIcon },
                set: { controller.showMenuBarIcon = $0 }))
            SettingsRow.toggle("Show network speed", $controller.showSpeed)
            SettingsRow.toggle("Show status on Dock icon", $controller.showDockStateIcon)
        }
    }

    private var runtimeTile: some View {
        SettingsTile("Runtime") {
            ForEach(deps) { dep in
                HStack(spacing: 8) {
                    Image(systemName: dep.found ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(dep.found ? DS.dataGreen : DS.dangerText)
                    Text(dep.name).font(.system(size: 12.5)).foregroundStyle(DS.primaryText)
                    Spacer(minLength: 8)
                    Text(dep.detail)
                        .font(.system(size: 10.5, design: dep.detail.hasPrefix("/") ? .monospaced : .default))
                        .foregroundStyle(DS.secondaryText)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var statisticsTile: some View {
        SettingsTile("Statistics") {
            SettingsRow.toggle("Record traffic statistics", $controller.recordStats)
            Text("Records byte volume over time — not the sites you visit. Stored locally only.")
                .font(.system(size: 10.5)).foregroundStyle(DS.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Clear statistics…") { confirmClearStats = true }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(DS.dangerText)
        }
    }

    private var filesTile: some View {
        SettingsTile("Files") {
            SettingsRow.path("Config", AppPaths.configURL.path)
            SettingsRow.path("Logs", AppPaths.logURL.path)
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([AppPaths.configURL])
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(DS.accent)
        }
    }

    /// Inline validation caption under the Ports tile, shown only on an error.
    @ViewBuilder
    private var inlineError: some View {
        if let err = controller.config.connectError,
           err.localizedCaseInsensitiveContains("port") {
            Text(err).font(.system(size: 10.5)).foregroundStyle(DS.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Data

    private func loadNetworkServices() {
        Task.detached {
            let services = NetworkServices.list()
            let primary = NetworkServices.primary()
            await MainActor.run {
                self.networkServiceOptions = services
                let current = controller.config.networkService
                if current.isEmpty || (!services.contains(current) && current != primary) {
                    if let primary { controller.config.networkService = primary }
                }
            }
        }
    }

    private func refreshDependencies() {
        Task.detached {
            var checks: [Dependency] = []
            if let p = AppPaths.bundledPrivoxy, FileManager.default.isExecutableFile(atPath: p.path) {
                checks.append(Dependency(name: "privoxy (bundled)", found: true, detail: "included"))
            } else {
                checks.append(Dependency(name: "privoxy (bundled)", found: false, detail: "missing"))
            }
            for tool in ["ssh", "curl"] {
                let path = "/usr/bin/\(tool)"
                let found = FileManager.default.isExecutableFile(atPath: path)
                checks.append(Dependency(name: tool, found: found, detail: found ? path : "not found"))
            }
            let final = checks
            await MainActor.run { self.deps = final }
        }
    }
}

// MARK: - Settings tile + rows

/// A titled settings tile: an uppercase caption over a small stack of rows.
struct SettingsTile<Content: View>: View {
    let caption: LocalizedStringKey
    @ViewBuilder let content: Content
    init(_ caption: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        Tile(padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)) {
            VStack(alignment: .leading, spacing: 8) {
                TileCaption(caption)
                content
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Row builders shared by the settings tiles. Each is a label flush-left with a
/// trailing control — a switch, a bordered numeric field, a popup, or a path.
enum SettingsRow {
    static func toggle(_ label: LocalizedStringKey, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(DS.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    static func field(_ label: LocalizedStringKey, _ value: Binding<Int>) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5)).foregroundStyle(DS.primaryText)
            Spacer()
            TextField("", value: value, format: .number.grouping(.never))
                .textFieldStyle(.plain)   // drop the default white field chrome
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(DS.primaryText)
                .frame(minWidth: 48)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DS.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(DS.fieldBorder, lineWidth: 1))
        }
    }

    static func picker<Content: View>(_ label: LocalizedStringKey,
                                      selection: Binding<String>,
                                      @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(DS.primaryText)
                .fixedSize()
                .layoutPriority(1)
            Spacer(minLength: 8)
            // Cap the popup width so a long service name can't starve the label
            // (which otherwise collapses to a 1-char-wide vertical stack).
            Picker("", selection: selection, content: content)
                .labelsHidden()
                .font(.system(size: 12))
                .frame(maxWidth: 130, alignment: .trailing)
        }
    }

    static func path(_ label: LocalizedStringKey, _ path: String) -> some View {
        HStack(spacing: 16) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(DS.primaryText)
            Spacer()
            Text(path)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(DS.secondaryText)
                .lineLimit(1).truncationMode(.middle)
        }
    }
}

// MARK: - Tools tab

/// Claude Code proxy integration + "remove all proxies", as tiles.
struct ToolsTab: View {
    @EnvironmentObject var controller: TunnelController

    @State private var claudeProxyOn = false
    @State private var claudeProxyMessage: String?
    @State private var claudeProxyIsError = false
    @State private var removeProxiesAlert: RemoveProxiesResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabHeader(title: "Tools")

            claudeTile
            systemProxiesTile

            Spacer(minLength: 0)

            Text("Requires admin rights — macOS prompts when toggling system proxies.")
                .font(.system(size: 11)).foregroundStyle(DS.secondaryText)
                .padding(.horizontal, 4)
        }
        .padding(DS.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: refreshClaudeProxyState)
        .alert("Remove All Proxies",
               isPresented: Binding(
                get: { removeProxiesAlert != nil },
                set: { if !$0 { removeProxiesAlert = nil } }),
               presenting: removeProxiesAlert) { _ in
            Button("OK", role: .cancel) {}
        } message: { result in
            if result.succeeded {
                Text("All proxies were removed for “\(result.service)”.")
            } else {
                Text("Some proxies could not be removed for “\(result.service)”. Check the logs for details.")
            }
        }
    }

    private var claudeTile: some View {
        Tile(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Route Claude Code through this proxy")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(DS.primaryText)
                        Text("Adds the HTTP proxy env keys to ~/.claude/settings.json, pointing Claude Code at \(ClaudeCodeConfig.proxyURL(port: controller.config.httpProxyPort)). Other settings are left untouched.")
                            .font(.system(size: 11)).foregroundStyle(DS.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(get: { claudeProxyOn }, set: { setClaudeProxy($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                if let msg = claudeProxyMessage {
                    Text(msg).font(.system(size: 11))
                        .foregroundStyle(claudeProxyIsError ? DS.warning : DS.textGreen)
                        .padding(.top, 8)
                }
                Divider().overlay(DS.tileBorder).padding(.top, 10)
                HStack(spacing: 12) {
                    Text("Settings file").font(.system(size: 12.5)).foregroundStyle(DS.primaryText)
                    Spacer()
                    Text(ClaudeCodeConfig.settingsURL.path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(DS.secondaryText).lineLimit(1).truncationMode(.middle)
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([ClaudeCodeConfig.settingsURL])
                    }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(DS.accent)
                }
                .padding(.top, 10)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var systemProxiesTile: some View {
        Tile(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Remove All Proxies")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(DS.dangerText)
                    Text("Turns off HTTP, HTTPS, SOCKS, and auto (PAC) proxies for the \(controller.config.networkService.isEmpty ? "selected network service" : controller.config.networkService) network service.")
                        .font(.system(size: 11)).foregroundStyle(DS.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                TintButton(title: "Remove…", kind: .danger, hPadding: 16, vPadding: 6) {
                    Task {
                        let service = controller.config.networkService
                        let ok = await controller.removeAllProxies()
                        removeProxiesAlert = RemoveProxiesResult(service: service, succeeded: ok)
                    }
                }
                .disabled(controller.config.networkService.isEmpty || controller.isBusy)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func refreshClaudeProxyState() {
        let port = controller.config.httpProxyPort
        Task.detached {
            let enabled = ClaudeCodeConfig.isProxyEnabled(port: port)
            await MainActor.run { self.claudeProxyOn = enabled }
        }
    }

    /// Write (or clear) the proxy keys, reverting the toggle and surfacing the
    /// message on failure so a malformed settings.json never overwrites silently.
    private func setClaudeProxy(_ enabled: Bool) {
        let port = controller.config.httpProxyPort
        Task.detached {
            do {
                try ClaudeCodeConfig.setProxyEnabled(enabled, port: port)
                await MainActor.run {
                    self.claudeProxyOn = enabled
                    self.claudeProxyIsError = false
                    self.claudeProxyMessage = enabled ? "Claude Code will use this proxy." : "Proxy removed from Claude Code."
                }
            } catch {
                await MainActor.run {
                    self.claudeProxyOn = ClaudeCodeConfig.isProxyEnabled(port: port)
                    self.claudeProxyIsError = true
                    self.claudeProxyMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Shared helpers

struct Dependency: Identifiable {
    let id = UUID()
    let name: String
    let found: Bool
    let detail: String
}

/// Outcome of "Remove All Proxies", used to drive the result alert.
struct RemoveProxiesResult: Identifiable {
    let id = UUID()
    let service: String
    let succeeded: Bool
}
