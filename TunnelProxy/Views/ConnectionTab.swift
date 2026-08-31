import SwiftUI
import Charts

/// The unified window's Connection tab, redesigned as Control-Center tiles: a
/// full-width hero (power ring + status + actions) above a 2×2 grid of Throughput,
/// Latency, Server quick-switch, and Options tiles. Everything binds to existing
/// `TunnelController` state/actions.
struct ConnectionTab: View {
    @EnvironmentObject var controller: TunnelController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: DS.gridGap) {
            warningBanner

            HeroTile()
                .frame(minHeight: 120)

            // 2×2 tile grid filling the remaining height.
            HStack(spacing: DS.gridGap) {
                ThroughputTile(monitor: controller.speedMonitor)
                LatencyTile()
            }
            HStack(spacing: DS.gridGap) {
                ServerTile()
                OptionsTile()
            }
        }
        .padding(DS.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var warningBanner: some View {
        if controller.config.servers.isEmpty {
            WarningBanner(text: Text("Add an SSH server in the Servers tab to connect."))
        } else if !controller.isConfigured {
            WarningBanner(text: Text(controller.config.connectError
                                     ?? String(localized: "Check server settings.")))
        } else if !controller.privoxyAvailable {
            WarningBanner(text: Text("Bundled proxy missing — reinstall the app."))
        }
    }
}

// MARK: - Hero tile

/// The full-width hero: power ring, status column (title + subtitle + chips), and
/// a trailing primary action (Disconnect / Connect) with a "via <host>" caption.
private struct HeroTile: View {
    @EnvironmentObject var controller: TunnelController

    var body: some View {
        Tile(padding: EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20),
             fill: AnyShapeStyle(controller.isConnected ? DS.heroGradient : DS.heroGradientNeutral)) {
            // Keep only the designed 20 pt gap between the ring and copy. A
            // spaced HStack also adds spacing on both sides of its Spacer,
            // which made this row wider than the app's 780 pt minimum window
            // and caused the entire window content to be clipped at both edges.
            HStack(spacing: 0) {
                PowerRing(size: 84, ringWidth: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.state.label)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(DS.primaryText)
                        .lineLimit(1)
                        .animation(.easeInOut(duration: 0.35), value: controller.state)
                    Text(controller.heroSubtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    chips.padding(.top, 8)
                }
                .padding(.leading, 20)
                .layoutPriority(1)

                Spacer(minLength: 8)

                // Trailing action column: keep its intrinsic width so the label
                // never wraps, even in a narrower window.
                VStack(spacing: 6) {
                    if controller.isConnected {
                        TintButton(title: "Disconnect", kind: .danger) {
                            controller.toggleConnection()
                        }
                        .disabled(!controller.canToggleConnection)
                    } else {
                        TintButton(title: "Connect", kind: .accent) {
                            controller.toggleConnection()
                        }
                        .disabled(!controller.canToggleConnection)
                    }
                    if let host = controller.selectedServer?.host, !host.isEmpty {
                        Text("via \(host)")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.secondaryText)
                            .lineLimit(1)
                    }
                }
                .fixedSize()
                .layoutPriority(2)
            }
        }
    }

    /// Status chips. Laid out on one line; each keeps its own intrinsic width but
    /// the row as a whole yields to the trailing action column when space is tight.
    @ViewBuilder
    private var chips: some View {
        HStack(spacing: 8) {
            if let ip = controller.exitIP {
                HeroChip(content: Text(ip), mono: true)
            }
            if let ms = controller.latencyMS {
                HeroChip(content: Text("● \(ms) ms"), color: controller.latencyColor)
            }
            HeroChip(content: Text(controller.watchdogEnabled ? "Watchdog on" : "Watchdog off"),
                     color: DS.secondaryText)
        }
    }
}

// MARK: - Throughput tile

/// Live down/up rates over a bottom-anchored sparkline of the last 60 samples.
/// Observes the controller's `SpeedMonitor` so the sparkline animates as samples
/// arrive (it's a separate `ObservableObject` from the controller).
private struct ThroughputTile: View {
    @ObservedObject var monitor: SpeedMonitor

    @EnvironmentObject private var controller: TunnelController

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 0) {
                TileCaption("Throughput")
                HStack(spacing: 16) {
                    Text("↓ \(ByteRate.string(monitor.downRate))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DS.dataBlue)
                    Text("↑ \(ByteRate.string(monitor.upRate))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DS.dataGreen)
                }
                .padding(.top, 7)

                Spacer(minLength: 8)

                chart
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// iStat-style mirrored bar chart: up = green bars above a dotted zero
    /// baseline, down = blue bars below. Empty (dotted baseline only) while
    /// disconnected. Bars plotted against a positional index so the series always
    /// spans the tile.
    @ViewBuilder
    private var chart: some View {
        let samples = monitor.history
        let peak = max(1, samples.map { max($0.down, $0.up) }.max() ?? 0)
        Chart {
            RuleMark(y: .value("zero", 0))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [1.6, 1.6]))
                .foregroundStyle(controller.isConnected ? DS.meterOff : DS.meterOff.opacity(0.8))
            ForEach(Array(samples.enumerated()), id: \.element.id) { i, s in
                BarMark(x: .value("t", i), y: .value("up", s.up), width: 2.2)
                    .foregroundStyle(DS.dataGreen)
                BarMark(x: .value("t", i), y: .value("down", -s.down), width: 2.2)
                    .foregroundStyle(DS.dataBlue)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: 0...max(1, monitor.historyCapacityValue - 1))
        .chartYScale(domain: -peak...peak)
        .animation(.linear(duration: 1), value: samples)
    }
}

// MARK: - Latency tile

/// A big latency number over a bottom-anchored history bar chart (one green bar
/// per probe), with a "avg over 60 s" footer. Empty (dotted baseline) + "—" +
/// "not connected" while disconnected.
private struct LatencyTile: View {
    @EnvironmentObject var controller: TunnelController

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 0) {
                TileCaption("Latency")
                HStack(alignment: .bottom, spacing: 12) {
                    if let ms = controller.latencyMS {
                        (Text("\(ms)").font(.system(size: 24, weight: .heavy))
                            .foregroundColor(controller.latencyColor)
                         + Text(" ms").font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DS.secondaryText))
                    } else {
                        Text("—").font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(DS.secondaryText)
                    }
                }
                .padding(.top, 5)

                Spacer(minLength: 8)

                chart
                    .frame(height: 36)
                    .frame(maxWidth: .infinity)

                Text(footerText)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.secondaryText)
                    .lineLimit(1)
                    .padding(.top, 6)
            }
        }
    }

    /// Bottom-anchored green bars, one per probe, rising from a dotted baseline.
    @ViewBuilder
    private var chart: some View {
        let samples = controller.latencyHistory
        let peak = max(1, samples.max() ?? 1)
        Chart {
            RuleMark(y: .value("zero", 0))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [1.6, 1.6]))
                .foregroundStyle(controller.isConnected ? DS.meterOff : DS.meterOff.opacity(0.8))
            ForEach(Array(samples.enumerated()), id: \.offset) { i, ms in
                BarMark(x: .value("t", i), y: .value("ms", ms), width: 2.2)
                    .foregroundStyle(DS.dataGreen)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: 0...49)   // pin to the ~50-sample window
        .chartYScale(domain: 0...Double(peak))
        .animation(.linear(duration: 1), value: samples)
    }

    private var footerText: String {
        let status = controller.isConnected
            ? String(localized: "avg over 60 s")
            : String(localized: "not connected")
        if let host = controller.selectedServer?.host, !host.isEmpty {
            return "\(host) · \(status)"
        }
        return status
    }
}

// MARK: - Server tile (quick-switch)

/// A compact radio list of profiles for in-place switching, plus "+ Add server".
/// Disabled while connected/busy, matching the existing picker rule.
private struct ServerTile: View {
    @EnvironmentObject var controller: TunnelController

    private var disabled: Bool { controller.isBusy || controller.isConnected }

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 8) {
                TileCaption("Server")

                if controller.config.servers.isEmpty {
                    Text("No servers yet")
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS.secondaryText)
                } else {
                    ForEach(controller.config.servers) { server in
                        row(for: server)
                    }
                }

                Spacer(minLength: 4)

                Button {
                    controller.requestedTab = .servers
                } label: {
                    Text("+ Add server")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(for server: ServerProfile) -> some View {
        let isSelected = server.id == (controller.config.selectedServerID
                                       ?? controller.config.servers.first?.id)
        return Button {
            if !disabled { controller.selectServer(server.id) }
        } label: {
            HStack(spacing: 8) {
                RadioDot(isSelected: isSelected)
                Text(server.displayName)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DS.primaryText : DS.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isSelected, let ms = controller.latencyMS {
                    Text("\(ms) ms")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(controller.latencyColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled && !isSelected ? 0.6 : 1)
    }
}

// MARK: - Options tile

/// OPTIONS caption over three whole-card toggles (button-cards): route Mac
/// traffic, auto-reconnect (watchdog), launch at login.
private struct OptionsTile: View {
    @EnvironmentObject var controller: TunnelController

    var body: some View {
        Tile(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
            VStack(alignment: .leading, spacing: 7) {
                TileCaption("Options").padding(.leading, 2)

                // Intent binding: run the toggle action only on a real change so a
                // programmatic state sync never re-issues networksetup.
                OptionCard(title: "Route Mac traffic",
                           isOn: .constant(controller.systemSocksOn),
                           onTap: { newValue in
                               guard newValue != controller.systemSocksOn else { return }
                               controller.systemSocksOn = newValue
                               Task { await controller.toggleSystemSocks(on: newValue) }
                           })
                OptionCard(title: "Auto-reconnect",
                           caption: controller.watchdogEnabled
                               ? String(localized: "Watchdog · On")
                               : String(localized: "Watchdog · Off"),
                           isOn: $controller.watchdogEnabled)
                OptionCard(title: "Launch at login", isOn: $controller.launchAtLogin)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Byte-rate formatting

/// Formats a bytes-per-second value like the design: "340 KB/s", "1.2 MB/s".
/// (Distinct from `SpeedMonitor.format`, which is space-free for the menu bar.)
enum ByteRate {
    static func string(_ bytesPerSec: Double) -> String {
        let kb = bytesPerSec / 1024
        if kb < 1 { return "0 KB/s" }
        if kb < 1024 { return "\(Int(kb.rounded())) KB/s" }
        let mb = kb / 1024
        return String(format: "%.1f MB/s", mb)
    }
}
