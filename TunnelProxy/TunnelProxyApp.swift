import SwiftUI

@main
struct TunnelProxyApp: App {
    @StateObject private var controller = TunnelController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu bar status item with a popover. `isInserted` is driven by the
        // user preference so the main window can show/hide the icon live.
        MenuBarExtra(isInserted: $controller.showMenuBarIcon) {
            MenuBarView()
                .environmentObject(controller)
        } label: {
            MenuBarLabel()
                .environmentObject(controller)
        }
        .menuBarExtraStyle(.window)
        // App menus (Connection / View / Help). Attached to the primary scene so
        // they install app-wide; they're only visible while the app is `.regular`
        // (main window open). Commands run outside the view tree, so the
        // controller is injected directly rather than via the environment.
        .commands { TunnelCommands(controller: controller) }

        // The single unified window — Connection · Servers · Logs · Statistics ·
        // Settings · Tools in one tabbed surface. Opened on launch and on reopen
        // (see AppDelegate).
        Window("Tunnel Proxy", id: "main") {
            UnifiedWindowView()
                .environmentObject(controller)
        }
        .defaultSize(width: 840, height: 580)
        .windowResizability(.contentMinSize)
        // Calendar-app style: no title strip; the tab picker lives in the
        // titlebar toolbar, so there's a single unified surface up top.
        .windowStyle(.hiddenTitleBar)

        // Settings scene (⌘,) — thin: it just opens/raises the main window on the
        // Servers tab rather than hosting a second copy of the config forms.
        Settings {
            SettingsView()
                .environmentObject(controller)
        }

        // Standalone User Guide window, opened from the popover. Shows the
        // bundled HTML manual in-app instead of the default browser.
        Window("User Guide", id: "user-guide") {
            ManualView()
        }
        .defaultSize(width: 860, height: 640)

        // Compact always-on-top mini window. Opened from the popover; promoted to
        // a floating panel in `MiniWindowView.onAppear`.
        Window("Tunnel Proxy Mini", id: "mini") {
            MiniWindowView()
                .environmentObject(controller)
        }
        .defaultSize(width: 300, height: 120)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

/// App delegate that flushes the traffic recorder on quit and drives the main
/// window's open/reopen lifecycle. SwiftUI tears the scene down before `deinit`
/// runs reliably, so we hook `applicationWillTerminate`. The controller registers
/// its flush closure here; `UnifiedWindowView` registers `openMainWindow`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `TunnelController` on init; invoked synchronously on quit.
    static var onTerminate: (() -> Void)?
    /// Set by `UnifiedWindowView` (which owns the SwiftUI `openWindow` action) so
    /// we can (re)open the main window from AppKit lifecycle callbacks.
    static var openMainWindow: (() -> Void)?
    /// Weak handle to the controller so the launch fallback can force the menu
    /// bar icon back on if it was hidden (see `openMainWindowWhenReady`).
    static weak var controller: TunnelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show the normal window on launch. `AppActivation.becomeRegular()` in
        // UnifiedWindowView.onAppear promotes the app to a Dock-visible app.
        // `openMainWindow` is registered by a SwiftUI view on its first render,
        // which may land a runloop tick or two after this callback — retry
        // briefly until it's available.
        openMainWindowWhenReady()
    }

    /// Retry opening the main window until the SwiftUI `openWindow` action has
    /// been registered, backing off over a short bounded window.
    ///
    /// `openMainWindow` is published by the menu bar label (which only renders
    /// while the icon is inserted). If the user launched with the icon hidden,
    /// nothing renders and the action never arrives — so, as a last resort,
    /// re-show the icon. That both makes the app reachable and triggers the
    /// registration, after which the next tick opens the window.
    private func openMainWindowWhenReady(attempt: Int = 0) {
        if let open = AppDelegate.openMainWindow {
            open()
            return
        }
        guard attempt < 40 else { return }   // ~2s ceiling at 50ms steps
        if attempt == 20, let controller = AppDelegate.controller {
            // Runs on the main runloop (asyncAfter on .main); the controller is
            // main-actor isolated, so assume isolation to touch it.
            MainActor.assumeIsolated {
                if !controller.showMenuBarIcon {
                    controller.showMenuBarIcon = true   // never leave the app unreachable
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.openMainWindowWhenReady(attempt: attempt + 1)
        }
    }

    /// Closing the last window must NOT quit — the app lives on in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Relaunching the app (Finder / `open -a`) resurfaces the main window even
    /// when the menu bar icon is hidden, so the user is never stranded.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppDelegate.openMainWindow?()
        AppActivation.becomeRegular()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.onTerminate?()
    }
}

/// The status-item label. `MenuBarExtra` clips a multi-line SwiftUI label to the
/// menu bar height, so when the speed is shown we draw the whole label (icon +
/// two-line up/down text) into a single fixed-height NSImage, which the status
/// item renders at its natural size without clipping.
struct MenuBarLabel: View {
    @EnvironmentObject var controller: TunnelController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Reading `iconDimmed` here re-renders the label each blink tick. The
        // dim is baked into the NSImage (a template image ignores SwiftUI
        // `.opacity`, so fading has to happen at the pixel level).
        let dimmed = controller.iconDimmed
        return Group {
        if controller.showSpeed {
            // Nested view observes the SpeedMonitor so the image refreshes as
            // rates change (it's a separate ObservableObject from controller).
            SpeedLabel(monitor: controller.speedMonitor,
                       symbol: controller.menuBarSymbol,
                       dimmed: dimmed)
        } else {
            Image(nsImage: MenuBarRenderer.iconImage(
                symbol: controller.menuBarSymbol, dimmed: dimmed))
                .accessibilityLabel("Tunnel Proxy")
        }
        }
        // The status item label reliably renders at launch (whenever the icon is
        // inserted), so capture the SwiftUI `openWindow` action here for the
        // AppKit launch/reopen callbacks in AppDelegate.
        .onAppear { AppDelegate.openMainWindow = { openWindow(id: "main") } }
    }
}

/// Renders the icon + two-line up/down speed into one NSImage.
private struct SpeedLabel: View {
    @ObservedObject var monitor: SpeedMonitor
    let symbol: String
    let dimmed: Bool

    var body: some View {
        Image(nsImage: MenuBarRenderer.labelImage(
            symbol: symbol, up: monitor.upText, down: monitor.downText, dimmed: dimmed))
            .accessibilityLabel("Tunnel Proxy")
    }
}

extension TunnelController {
    /// SF Symbol reflecting the current connection state.
    var menuBarSymbol: String {
        switch state {
        case .connected: return "shield.lefthalf.filled"
        // A loading/progress glyph while the tunnel comes up, instead of a
        // blinking shield — reads as "working" without the flicker.
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.shield"
        case .disconnected: return "shield"
        }
    }
}

/// The app's main menus, shown on the left of the system menu bar while the app
/// is `.regular` (main window open). Mirrors the window/popover actions with
/// keyboard shortcuts. Commands run outside the view tree, so the controller is
/// observed here directly rather than pulled from the environment.
struct TunnelCommands: Commands {
    @ObservedObject var controller: TunnelController
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Help ▸ User Guide (replaces the default empty Help menu).
        CommandGroup(replacing: .help) {
            if AppPaths.userGuide != nil {
                Button("User Guide") {
                    openWindow(id: "user-guide")
                    TunnelUI.activateApp()
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        // Connection menu.
        CommandMenu("Connection") {
            Button(controller.isConnected ? "Disconnect" : "Connect") {
                controller.toggleConnection()
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(!controller.canToggleConnection)

            Button("Reconnect") {
                Task { await controller.disconnect(); await controller.connect() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!controller.canToggleConnection || !controller.isConnected)

            Divider()

            Menu("Server") {
                if controller.config.servers.isEmpty {
                    Text("No servers")
                } else {
                    ForEach(controller.config.servers) { server in
                        Button {
                            controller.selectServer(server.id)
                        } label: {
                            Label(server.displayName,
                                  systemImage: server.id == controller.config.selectedServerID
                                  ? "checkmark" : "")
                        }
                    }
                }
            }
            .disabled(controller.isBusy || controller.isConnected)

            Divider()

            Toggle("macOS SOCKS proxy", isOn: Binding(
                get: { controller.systemSocksOn },
                set: { newValue in
                    guard newValue != controller.systemSocksOn else { return }
                    controller.systemSocksOn = newValue
                    Task { await controller.toggleSystemSocks(on: newValue) }
                }
            ))
            Toggle("Auto-reconnect (watchdog)", isOn: $controller.watchdogEnabled)
            Toggle("Show network speed", isOn: $controller.showSpeed)
        }

        // Augment the standard View menu (rather than adding a second one) with
        // the app's tabs + the menu-bar-icon toggle. Logs/Statistics are now tabs
        // of the main window, so these select the tab and raise the window.
        CommandGroup(after: .sidebar) {
            Button("Logs") {
                controller.requestedTab = .logs
                openWindow(id: "main")
                TunnelUI.activateApp()
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Statistics") {
                controller.requestedTab = .stats
                openWindow(id: "main")
                TunnelUI.activateApp()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Tunnel Proxy Window") {
                controller.requestedTab = .connection
                openWindow(id: "main")
                TunnelUI.activateApp()
            }

            Button("Mini Window") {
                openWindow(id: "mini")
                TunnelUI.activateApp()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()

            Toggle("Show Menu Bar Icon", isOn: Binding(
                get: { controller.showMenuBarIcon },
                set: { controller.showMenuBarIcon = $0 }
            ))
        }
    }
}
