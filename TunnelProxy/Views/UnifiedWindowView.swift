import SwiftUI

/// The single, unified app window. The redesign ("2a") replaces the old top
/// icon-tab strip with a **left sidebar** (Mail / System-Settings style) over a
/// light-gray canvas, with Control-Center-style white tiles for content.
///
/// The app ships as an `LSUIElement` menu bar agent (no Dock icon). While this
/// window is on screen we promote the app to `.regular` so it gets a Dock icon +
/// app menus; when it closes we drop back to `.accessory`. Closing never quits —
/// the `MenuBarExtra` scene keeps the process alive.
struct UnifiedWindowView: View {
    @EnvironmentObject var controller: TunnelController
    @Environment(\.openWindow) private var openWindow
    @SceneStorage("mainTab") private var tab: WindowTab = .connection

    var body: some View {
        // `.hiddenTitleBar` lets content extend to the very top; the sidebar paints
        // its own surface behind the floating traffic-light buttons (top ~36 pt is
        // reserved for them). Sidebar (fixed 188 pt) + content pane (canvas).
        HStack(spacing: 0) {
            Sidebar(selection: $tab)
                .frame(width: DS.sidebarWidth)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.canvas)
        }
        .frame(minWidth: 780, idealWidth: 840, minHeight: 560, idealHeight: 580)
        .ignoresSafeArea(.container, edges: .top)
        // Route "open on tab X" requests from the popover / app menus.
        .onChange(of: controller.requestedTab) { _, new in
            if let new {
                tab = new
                controller.requestedTab = nil
            }
        }
        .onAppear {
            controller.onAppear()
            if let requested = controller.requestedTab {
                tab = requested
                controller.requestedTab = nil
            }
            AppDelegate.openMainWindow = { openWindow(id: "main") }
            AppActivation.becomeRegular()
            // The Dock tile only exists once we're `.regular`; paint it to the
            // current state now so a window opened mid-connection isn't stale.
            controller.updateDockIcon()
        }
        .onDisappear {
            AppActivation.becomeAccessory()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .connection: ConnectionTab()
        case .servers:    ServersView()
        case .logs:       LogsView()
        case .stats:      StatisticsView()
        case .settings:   SettingsTab()
        case .tools:      ToolsTab()
        }
    }
}

// MARK: - Sidebar

/// The left navigation sidebar: app header, a nav list of the six tabs, and a
/// pinned connection-status card at the bottom.
private struct Sidebar: View {
    @Binding var selection: WindowTab
    @EnvironmentObject var controller: TunnelController

    private struct Item: Identifiable {
        let tab: WindowTab
        let title: LocalizedStringKey
        let symbol: String
        var id: WindowTab { tab }
    }

    private let items: [Item] = [
        .init(tab: .connection, title: "Connection", symbol: "bolt.horizontal.circle"),
        .init(tab: .servers,    title: "Servers",    symbol: "server.rack"),
        .init(tab: .logs,       title: "Logs",       symbol: "doc.plaintext"),
        .init(tab: .stats,      title: "Statistics", symbol: "chart.bar"),
        .init(tab: .settings,   title: "Settings",   symbol: "gearshape"),
        .init(tab: .tools,      title: "Tools",      symbol: "wrench.and.screwdriver"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clear the traffic-light controls (top ~36 pt).
            Spacer().frame(height: 34)

            // App header row.
            HStack(spacing: 8) {
                Image("SidebarIcon")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("Tunnel Proxy")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.primaryText)
            }
            .padding(.leading, 4)

            // Nav list.
            VStack(spacing: 2) {
                ForEach(items) { item in
                    NavRow(item: item, isSelected: selection == item.tab) {
                        selection = item.tab
                    }
                }
            }
            .padding(.top, 16)

            Spacer(minLength: 12)

            StatusCard()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(DS.sidebarSeparator).frame(width: 1)
        }
    }

    private struct NavRow: View {
        let item: Item
        let isSelected: Bool
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 15))
                        .frame(width: 18)
                        .foregroundStyle(isSelected ? .white : DS.secondaryText)
                    Text(item.title)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? .white : DS.primaryText)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? DS.accent
                              : (hovering ? DS.primaryText.opacity(0.06) : .clear)))
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

/// The pinned status card at the bottom of the sidebar: a status dot + label,
/// right-aligned latency, and the exit IP.
private struct StatusCard: View {
    @EnvironmentObject var controller: TunnelController

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(controller.statusColor).frame(width: 8, height: 8)
                Text(controller.state.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let ms = controller.latencyMS {
                    Text("\(ms) ms")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(controller.latencyColor)
                }
            }
            Text(controller.exitIP ?? "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DS.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.tile.opacity(0.65)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DS.tileBorder, lineWidth: 1))
    }
}

// MARK: - Reusable content helpers (redesign)

/// A tab's standard header: a bold title flush-left with optional trailing
/// controls. Used across the tiled tabs.
struct TabHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DS.primaryText)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension TabHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.title = title
        self.trailing = EmptyView()
    }
    init(title: LocalizedStringKey) {
        self.title = title
        self.trailing = EmptyView()
    }
}

// MARK: - Legacy reusable style pieces (still referenced by unported surfaces)

/// A titled group card. Retained for any view not yet migrated to `Tile`.
struct SectionCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(nsColor: .separatorColor)))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// Label flush-left, switch flush-right — a settings-style row.
struct SwitchRow: View {
    let label: LocalizedStringKey
    @Binding var isOn: Bool

    init(_ label: LocalizedStringKey, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label).frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .font(.system(size: 13))
        .padding(.vertical, 8)
    }
}

/// An inline warning line (amber, with a triangle glyph).
struct WarningBanner: View {
    let text: Text

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            text
        }
        .font(.system(size: 11.5))
        .foregroundStyle(DS.warning)
        .multilineTextAlignment(.leading)
    }
}

/// Small helper for flipping the activation policy between agent (`.accessory`)
/// and normal-app (`.regular`) modes, and bringing the app forward.
enum AppActivation {
    static func becomeRegular() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func becomeAccessory() {
        NSApp.setActivationPolicy(.accessory)
    }
}
