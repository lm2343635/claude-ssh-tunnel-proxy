import SwiftUI

/// Shared visual language for the unified-window redesign ("2a"): a left sidebar
/// over a light-gray canvas, with Control-Center-style white tiles. Colors,
/// radii, and type come from the design handoff
/// (`plan/design_handoff_unified_redesign/README.md`). Surface colors are
/// adaptive (light + dark values from the design) so dark mode Just Works; the
/// brand/data accents that have no macOS system equivalent are the design hexes.

// MARK: - Adaptive color helper

extension Color {
    /// An appearance-adaptive color from explicit light/dark hex values, matching
    /// the design's own light/dark tokens. Falls back to the light value on any
    /// non-macOS/unknown appearance.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    /// A solid color from a 24-bit RGB hex (0xRRGGBB).
    init(hex: UInt32) {
        self = Color(nsColor: NSColor(hex: hex))
    }
}

extension NSColor {
    /// From a 24-bit RGB hex (0xRRGGBB), fully opaque.
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Design tokens

/// The redesign's color, type, and metric tokens. See the handoff's "Design
/// Tokens" section — values are final and used verbatim.
enum DS {

    // Surfaces (adaptive).
    /// Content-pane canvas behind the tiles.
    static let canvas = Color.adaptive(light: 0xF2F2F5, dark: 0x151517)
    /// Left navigation sidebar.
    static let sidebar = Color.adaptive(light: 0xE9E9EB, dark: 0x232327)
    /// 1 px separator on the sidebar's trailing edge.
    static let sidebarSeparator = Color.adaptive(light: 0xD9D9DC, dark: 0x2E2E32)
    /// A white tile face.
    static let tile = Color.adaptive(light: 0xFFFFFF, dark: 0x232327)
    /// Tile hairline border (white 6% in dark; a faint gray in light).
    static let tileBorder = Color.adaptive(light: 0xE9E9EC, dark: 0x2E2E33)
    /// Bordered field fill inside tiles.
    static let fieldFill = Color.adaptive(light: 0xF5F5F7, dark: 0x1B1B1E)
    static let fieldBorder = Color.adaptive(light: 0xE4E4E7, dark: 0x38383E)

    // Accents & data colors.
    /// Selection / links (matches macOS accent semantics closely).
    static let accent = Color.adaptive(light: 0x0A7CFF, dark: 0x0A84FF)
    /// Chart/data "down" blue.
    static let dataBlue = Color.adaptive(light: 0x0F7BF5, dark: 0x409CFF)
    /// Status/ring green.
    static let ringGreen = Color.adaptive(light: 0x28CD41, dark: 0x32D74B)
    /// Chart/data "up" green.
    static let dataGreen = Color.adaptive(light: 0x28BD4B, dark: 0x32D74B)
    /// Green used for latency / status text.
    static let textGreen = Color.adaptive(light: 0x1F9E38, dark: 0x32D74B)
    /// Destructive text (Disconnect / remove).
    static let dangerText = Color.adaptive(light: 0xE5372B, dark: 0xFF6B60)
    /// Warning orange (sluggish, validation errors).
    static let warning = Color.adaptive(light: 0xC77800, dark: 0xF0A83A)

    // Text.
    static let primaryText = Color.adaptive(light: 0x1D1D1F, dark: 0xF2F2F4)
    static let secondaryText = Color.adaptive(light: 0x85858B, dark: 0x9A9AA2)
    static let tertiaryText = Color.adaptive(light: 0xB0B0B5, dark: 0x6E6E76)
    /// Unfilled latency meter bar / inactive radio ring.
    static let meterOff = Color.adaptive(light: 0xD9D9DC, dark: 0x3A3A40)

    // Tints.
    /// Red-tint button fill (rgba(255,59,48,.10) light / .16 dark).
    static let dangerFill = Color.adaptive(light: 0xFCE7E6, dark: 0x3A2320)
    /// Blue-tint button fill for the "Connect" action.
    static let accentFill = Color.adaptive(light: 0xE6F1FF, dark: 0x1E2A3D)

    // Metrics.
    static let sidebarWidth: CGFloat = 188
    static let tileRadius: CGFloat = 16
    static let contentPadding: CGFloat = 16
    static let gridGap: CGFloat = 13

    /// Hero-tile gradient when connected (green wash → tile), light + dark.
    static var heroGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .adaptive(light: 0xE4F8E9, dark: 0x2A3A2C), location: 0),
                .init(color: .adaptive(light: 0xFFFFFF, dark: 0x232327), location: 0.58),
            ]),
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Hero-tile gradient when disconnected (neutral gray wash → tile).
    static var heroGradientNeutral: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .adaptive(light: 0xF1F1F4, dark: 0x27272B), location: 0),
                .init(color: .adaptive(light: 0xFFFFFF, dark: 0x232327), location: 0.58),
            ]),
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Tile

/// A Control-Center-style white tile: rounded, faintly bordered, softly shadowed.
/// The reused container for every card in the redesign.
struct Tile<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)
    /// An optional custom fill (e.g. the hero gradient); defaults to the tile face.
    var fill: AnyShapeStyle = AnyShapeStyle(DS.tile)
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DS.tileRadius, style: .continuous)
                    .fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: DS.tileRadius, style: .continuous)
                    .strokeBorder(DS.tileBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

/// The uppercase caption sitting atop each tile's content.
struct TileCaption: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .kerning(0.6)
            .textCase(.uppercase)
            .foregroundStyle(DS.secondaryText)
    }
}

// MARK: - Shared small controls

/// A radio dot matching the design (accent when selected, gray ring otherwise).
struct RadioDot: View {
    var isSelected: Bool
    var size: CGFloat = 15

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? DS.accent : DS.meterOff, lineWidth: 1.5)
            if isSelected {
                Circle()
                    .fill(DS.accent)
                    .padding(size * 0.23)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A rounded, bordered "chip" (IP, latency, watchdog) used on the hero tile.
struct HeroChip: View {
    let content: Text
    var color: Color = DS.primaryText
    var mono: Bool = false

    var body: some View {
        content
            .font(.system(size: 11.5, weight: .semibold, design: mono ? .monospaced : .default))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DS.tile))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(DS.fieldBorder, lineWidth: 1))
            .fixedSize()
    }
}

/// A red-tint or accent-tint pill button used for Disconnect / Connect / Remove.
struct TintButton: View {
    enum Kind { case danger, accent }
    let title: LocalizedStringKey
    var kind: Kind = .danger
    var hPadding: CGFloat = 22
    var vPadding: CGFloat = 7
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(kind == .danger ? DS.dangerText : DS.accent)
                .lineLimit(1)
                .fixedSize()          // never wrap the label ("Dis / co / nn / ect")
                .padding(.horizontal, hPadding)
                .padding(.vertical, vPadding)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(kind == .danger ? DS.dangerFill : DS.accentFill))
        }
        .buttonStyle(.plain)
    }
}

/// A whole-card toggle used in the Connection Options tile and the popover: the
/// entire card is the tap target (no separate switch). ON = accent gradient with
/// white text; OFF = inset gray fill with primary/secondary text. Shows a title
/// and a state caption ("On" / "Off" / "Watchdog · On").
struct OptionCard: View {
    let title: LocalizedStringKey
    /// State caption; defaults to "On"/"Off" from `isOn` when nil.
    var caption: String? = nil
    @Binding var isOn: Bool
    /// Called with the new value on tap; use when the change has a side effect
    /// beyond flipping the binding (e.g. systemSocks). Defaults to just toggling.
    var onTap: ((Bool) -> Void)? = nil
    var titleSize: CGFloat = 12
    var captionSize: CGFloat = 9.5

    private var stateText: String {
        caption ?? (isOn ? String(localized: "On") : String(localized: "Off"))
    }

    var body: some View {
        Button {
            let newValue = !isOn
            if let onTap { onTap(newValue) } else { isOn = newValue }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : DS.primaryText)
                Text(stateText)
                    .font(.system(size: captionSize))
                    .foregroundStyle(isOn ? Color.white.opacity(0.85) : DS.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn
                          ? AnyShapeStyle(LinearGradient(
                                colors: [Color(hex: 0x4E96F7), Color(hex: 0x3873F1)],
                                startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(DS.fieldFill)))
            .shadow(color: isOn ? .black.opacity(0.15) : .clear, radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }
}

/// The circular power ring shared by the hero tile, popover, and mini window.
/// Reflects connection state: green full ring (connected), sweeping arc
/// (connecting), gray ring (disconnected), red ring (error). Tapping toggles.
struct PowerRing: View {
    @EnvironmentObject var controller: TunnelController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Outer diameter of the ring.
    var size: CGFloat = 84
    /// Ring stroke width.
    var ringWidth: CGFloat = 8
    /// Radial glow behind the ring (only meaningful when connected).
    var glow: Bool = true

    @State private var animating = false

    private var connecting: Bool {
        switch controller.state {
        case .connecting, .reconnecting: return true
        default: return false
        }
    }

    /// The ring's color for the current state.
    private var ringColor: Color {
        switch controller.state {
        case .connected: return DS.ringGreen
        case .connecting, .reconnecting: return DS.ringGreen
        case .error: return DS.dangerText
        case .disconnected: return DS.meterOff
        }
    }

    private var glyphSize: CGFloat { size * 0.30 }

    var body: some View {
        Button(action: controller.toggleConnection) {
            ZStack {
                if glow && controller.isConnected {
                    Circle()
                        .fill(RadialGradient(
                            gradient: Gradient(colors: [DS.ringGreen.opacity(0.28), .clear]),
                            center: .center, startRadius: 0, endRadius: size * 0.7))
                        .frame(width: size * 1.28, height: size * 1.28)
                }

                // Base track.
                Circle()
                    .strokeBorder(controller.isConnected || connecting
                                  ? DS.meterOff.opacity(0.35) : DS.meterOff,
                                  lineWidth: ringWidth)
                    .frame(width: size, height: size)

                // State ring: full circle when connected/error; sweeping arc while
                // connecting.
                stateRing
                    .frame(width: size, height: size)

                // White face + power glyph.
                Circle()
                    .fill(DS.tile)
                    .frame(width: size - ringWidth * 2, height: size - ringWidth * 2)
                    .overlay(
                        Image(systemName: "power")
                            .font(.system(size: glyphSize, weight: .medium))
                            .foregroundStyle(glyphColor))
                    .shadow(color: .black.opacity(0.10), radius: 3, y: 2)
            }
            // The glow is intentionally allowed to draw beyond the control,
            // but it must not participate in layout. Treating the 128% glow
            // diameter as the button's intrinsic size made the hero row wider
            // than the minimum window even though the visible ring is 84 pt.
            .frame(width: size, height: size)
            .contentShape(Circle())
            .scaleEffect(breathing)
        }
        .buttonStyle(.plain)
        .disabled(!controller.canToggleConnection)
        .opacity(controller.canToggleConnection ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.35), value: controller.state)
        .onAppear { syncAnimation() }
        .onChange(of: controller.state) { _, _ in syncAnimation() }
    }

    @ViewBuilder
    private var stateRing: some View {
        if connecting && !reduceMotion {
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(ringColor, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(animating ? 360 : 0))
                .animation(animating
                           ? .linear(duration: 1).repeatForever(autoreverses: false)
                           : .default, value: animating)
        } else if connecting {
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(ringColor, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
        } else if controller.isConnected {
            Circle().stroke(ringColor, lineWidth: ringWidth)
        } else if case .error = controller.state {
            Circle().stroke(ringColor, lineWidth: ringWidth)
        }
    }

    private var glyphColor: Color {
        switch controller.state {
        case .connected: return DS.ringGreen
        case .error: return DS.dangerText
        case .connecting, .reconnecting, .disconnected: return DS.secondaryText
        }
    }

    private var breathing: CGFloat {
        guard animating, !reduceMotion else { return 1 }
        return (controller.isConnected || connecting) ? 1.03 : 1
    }

    private func syncAnimation() {
        guard !reduceMotion else { animating = false; return }
        let shouldAnimate = connecting || controller.isConnected
        withAnimation(shouldAnimate
                      ? .easeInOut(duration: 2).repeatForever(autoreverses: true)
                      : .default) {
            animating = shouldAnimate
        }
    }
}
