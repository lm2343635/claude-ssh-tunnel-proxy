import AppKit

/// Composes the Dock icon for a given `ConnectionState`. Mirrors the structure of
/// `MenuBarRenderer`: pure drawing, no state of its own, results cached.
///
/// Unlike the menu bar icon (a monochrome template the bar tints), the Dock tile
/// shows full colour, so we draw the whole icon here — the same shield + routing
/// hub as `icon/icon.svg`, recoloured per state, with a small status badge in the
/// lower-right (Option A of `plan/dock-icon-states-plan.md`).
///
/// The five images never change, so `image(for:)` renders each once and caches it.
enum DockIconRenderer {

    /// Canvas edge in points. Drawn once at 1024² (the icon master size) so the
    /// vector geometry stays crisp when AppKit downscales to Dock tile sizes.
    private static let side: CGFloat = 1024

    /// Colours per state, matching the mockup
    /// (`plan/mockups/dock-icon-states-tint.svg`).
    private struct Palette {
        let bgTop: NSColor
        let bgMid: NSColor
        let bgBottom: NSColor
        let glyphStroke: NSColor
        let glyphDot: NSColor
    }

    /// One badge case per connection state. `.none` (no badge) isn't used today —
    /// every state carries a badge — but keeps the door open for a plain variant.
    private enum Badge {
        case check       // connected
        case ring        // disconnected (hollow)
        case dots        // connecting
        case arrow       // reconnecting
        case bang        // error
    }

    // MARK: - Public

    /// The composed, cached Dock icon for `state`. Distinct `.error` messages map
    /// to the same image (the badge is identical for any error string).
    static func image(for state: ConnectionState) -> NSImage {
        let key = cacheKey(for: state)
        if let cached = cache[key] { return cached }
        let img = render(palette: palette(for: state), badge: badge(for: state))
        cache[key] = img
        return img
    }

    // MARK: - Cache

    /// Keyed by a stable string so `.error(a)` and `.error(b)` share one entry.
    private static var cache: [String: NSImage] = [:]

    private static func cacheKey(for state: ConnectionState) -> String {
        switch state {
        case .connected:    return "connected"
        case .disconnected: return "disconnected"
        case .connecting:   return "connecting"
        case .reconnecting: return "reconnecting"
        case .error:        return "error"
        }
    }

    // MARK: - State → style

    private static func palette(for state: ConnectionState) -> Palette {
        switch state {
        case .connected:
            return Palette(bgTop: hex(0x3d6bff), bgMid: hex(0x2b53e0), bgBottom: hex(0x1b3aa8),
                           glyphStroke: hex(0x2b53e0), glyphDot: hex(0x1b3aa8))
        case .disconnected:
            return Palette(bgTop: hex(0x8b93a3), bgMid: hex(0x6b7385), bgBottom: hex(0x4c5364),
                           glyphStroke: hex(0x5b6274), glyphDot: hex(0x4c5364))
        case .connecting, .reconnecting:
            return Palette(bgTop: hex(0xffc24d), bgMid: hex(0xf0a622), bgBottom: hex(0xc47f0a),
                           glyphStroke: hex(0xb57a08), glyphDot: hex(0x8a5c04))
        case .error:
            return Palette(bgTop: hex(0xff6b6b), bgMid: hex(0xe23b3b), bgBottom: hex(0xa81b1b),
                           glyphStroke: hex(0xc22a2a), glyphDot: hex(0x8a1414))
        }
    }

    private static func badge(for state: ConnectionState) -> Badge {
        switch state {
        case .connected:    return .check
        case .disconnected: return .ring
        case .connecting:   return .dots
        case .reconnecting: return .arrow
        case .error:        return .bang
        }
    }

    // MARK: - Drawing

    private static func render(palette: Palette, badge: Badge) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

        // The icon.svg geometry uses a top-left origin (y down); AppKit is bottom-
        // left (y up). Flip so the SVG coordinates translate directly.
        ctx.translateBy(x: 0, y: side)
        ctx.scaleBy(x: 1, y: -1)

        drawCanvas(ctx, palette: palette)
        drawShield(ctx)
        drawGlyph(ctx, palette: palette)
        drawBadge(ctx, badge: badge)

        return image
    }

    /// Rounded-rect (squircle) canvas with the state's vertical gradient. Path
    /// matches icon.svg's canvas path.
    private static func drawCanvas(_ ctx: CGContext, palette: Palette) {
        let path = CGMutablePath()
        // M300 100 h424 c110 0 200 90 200 200 v424 c0 110 -90 200 -200 200
        // h-424 c-110 0 -200 -90 -200 -200 v-424 c0 -110 90 -200 200 -200 z
        path.move(to: CGPoint(x: 300, y: 100))
        path.addLine(to: CGPoint(x: 724, y: 100))
        path.addCurve(to: CGPoint(x: 924, y: 300), control1: CGPoint(x: 834, y: 100), control2: CGPoint(x: 924, y: 190))
        path.addLine(to: CGPoint(x: 924, y: 724))
        path.addCurve(to: CGPoint(x: 724, y: 924), control1: CGPoint(x: 924, y: 834), control2: CGPoint(x: 834, y: 924))
        path.addLine(to: CGPoint(x: 300, y: 924))
        path.addCurve(to: CGPoint(x: 100, y: 724), control1: CGPoint(x: 190, y: 924), control2: CGPoint(x: 100, y: 834))
        path.addLine(to: CGPoint(x: 100, y: 300))
        path.addCurve(to: CGPoint(x: 300, y: 100), control1: CGPoint(x: 100, y: 190), control2: CGPoint(x: 190, y: 100))
        path.closeSubpath()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        drawVerticalGradient(ctx,
                             stops: [(0, palette.bgTop), (0.55, palette.bgMid), (1, palette.bgBottom)],
                             from: CGPoint(x: 0, y: 100), to: CGPoint(x: 0, y: 924))
        ctx.restoreGState()
    }

    /// White shield face. Path matches icon.svg's shield path.
    private static func drawShield(_ ctx: CGContext) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 512, y: 236))
        path.addCurve(to: CGPoint(x: 730, y: 316), control1: CGPoint(x: 560, y: 268), control2: CGPoint(x: 648, y: 316))
        path.addCurve(to: CGPoint(x: 698, y: 634), control1: CGPoint(x: 730, y: 316), control2: CGPoint(x: 744, y: 520))
        path.addCurve(to: CGPoint(x: 512, y: 802), control1: CGPoint(x: 660, y: 728), control2: CGPoint(x: 566, y: 782))
        path.addCurve(to: CGPoint(x: 326, y: 634), control1: CGPoint(x: 458, y: 782), control2: CGPoint(x: 364, y: 728))
        path.addCurve(to: CGPoint(x: 294, y: 316), control1: CGPoint(x: 280, y: 520), control2: CGPoint(x: 294, y: 316))
        path.addCurve(to: CGPoint(x: 512, y: 236), control1: CGPoint(x: 376, y: 316), control2: CGPoint(x: 464, y: 268))
        path.closeSubpath()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        drawVerticalGradient(ctx,
                             stops: [(0, hex(0xffffff)), (1, hex(0xeef1f8))],
                             from: CGPoint(x: 0, y: 236), to: CGPoint(x: 0, y: 802))
        ctx.restoreGState()
    }

    /// Routing glyph: entry + two exits through a central hub. Matches icon.svg.
    private static func drawGlyph(_ ctx: CGContext, palette: Palette) {
        ctx.saveGState()

        // Three spokes.
        ctx.setStrokeColor(palette.glyphStroke.cgColor)
        ctx.setLineWidth(36)
        ctx.setLineCap(.round)
        let spokes: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 374, y: 424), CGPoint(x: 512, y: 512)),
            (CGPoint(x: 512, y: 512), CGPoint(x: 650, y: 424)),
            (CGPoint(x: 512, y: 512), CGPoint(x: 512, y: 664)),
        ]
        for (a, b) in spokes {
            ctx.move(to: a)
            ctx.addLine(to: b)
        }
        ctx.strokePath()

        // Three outer nodes.
        ctx.setFillColor(palette.glyphDot.cgColor)
        for c in [CGPoint(x: 374, y: 424), CGPoint(x: 650, y: 424), CGPoint(x: 512, y: 664)] {
            ctx.fillEllipse(in: CGRect(x: c.x - 40, y: c.y - 40, width: 80, height: 80))
        }

        // Central hub: filled disc + white ring.
        ctx.setFillColor(palette.glyphStroke.cgColor)
        ctx.fillEllipse(in: CGRect(x: 512 - 56, y: 512 - 56, width: 112, height: 112))
        ctx.setStrokeColor(hex(0xffffff).cgColor)
        ctx.setLineWidth(16)
        ctx.strokeEllipse(in: CGRect(x: 512 - 56, y: 512 - 56, width: 112, height: 112))

        ctx.restoreGState()
    }

    /// Status badge in the lower-right, at the mockup's placement (centre ≈ 158/200
    /// of the 200-unit tile → 809/1024 here) with a white ring behind it.
    private static func drawBadge(_ ctx: CGContext, badge: Badge) {
        // Mockup: badge centre (158,158) of 200 → scale ×5.12; outer r 30, inner r 24.
        let cx: CGFloat = 158 * 5.12   // 809.0
        let cy: CGFloat = 158 * 5.12   // 809.0
        let outerR: CGFloat = 30 * 5.12  // 153.6 — white halo
        let innerR: CGFloat = 24 * 5.12  // 122.9 — coloured disc / ring

        ctx.saveGState()

        // White halo so the badge separates from the canvas tint.
        ctx.setFillColor(hex(0xffffff).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - outerR, y: cy - outerR, width: outerR * 2, height: outerR * 2))

        switch badge {
        case .check:
            fillDisc(ctx, cx: cx, cy: cy, r: innerR, color: hex(0x34c759))
            // ✓ — mockup path "M147 158 l7 7 l14 -15" (in 200-space), scaled.
            strokePolyline(ctx,
                           points: [CGPoint(x: 147, y: 158), CGPoint(x: 154, y: 165), CGPoint(x: 168, y: 150)],
                           color: hex(0xffffff), width: 6)
        case .ring:
            // Hollow ring: no fill, coloured stroke.
            ctx.setStrokeColor(hex(0x8b93a3).cgColor)
            ctx.setLineWidth(6 * 5.12)
            ctx.strokeEllipse(in: CGRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2))
        case .dots:
            fillDisc(ctx, cx: cx, cy: cy, r: innerR, color: hex(0xf0a622))
            // Three white dots (in 200-space at y=158, x=149/158/167, r=3.5).
            ctx.setFillColor(hex(0xffffff).cgColor)
            for dx in [CGFloat(149), 158, 167] {
                let p = scale(CGPoint(x: dx, y: 158))
                let r: CGFloat = 3.5 * 5.12
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
        case .arrow:
            fillDisc(ctx, cx: cx, cy: cy, r: innerR, color: hex(0xf0a622))
            drawRefreshArrow(ctx, cx: cx, cy: cy)
        case .bang:
            fillDisc(ctx, cx: cx, cy: cy, r: innerR, color: hex(0xe23b3b))
            // "!" — a stem plus a dot, mockup "M158 148 l0 12" + dot near 158,167.
            strokePolyline(ctx,
                           points: [CGPoint(x: 158, y: 148), CGPoint(x: 158, y: 160)],
                           color: hex(0xffffff), width: 6)
            let dot = scale(CGPoint(x: 158, y: 168))
            let dr: CGFloat = 3 * 5.12
            ctx.setFillColor(hex(0xffffff).cgColor)
            ctx.fillEllipse(in: CGRect(x: dot.x - dr, y: dot.y - dr, width: dr * 2, height: dr * 2))
        }

        ctx.restoreGState()
    }

    /// A clockwise circular refresh arrow inside the reconnecting badge: a ~270°
    /// white arc with a solid triangular arrowhead at its leading end, centred in
    /// the badge and sized so it stays legible at Dock tile sizes.
    private static func drawRefreshArrow(_ ctx: CGContext, cx: CGFloat, cy: CGFloat) {
        let r: CGFloat = 58          // arc radius (badge inner disc is ~123 px)
        let lineW: CGFloat = 22
        let white = hex(0xffffff)

        ctx.saveGState()
        ctx.setStrokeColor(white.cgColor)
        ctx.setLineWidth(lineW)
        ctx.setLineCap(.round)

        // Sweep from the top, clockwise-on-screen, leaving a gap at the top-right
        // for the arrowhead. In the flipped (y-down) context, increasing angle is
        // clockwise on screen, so `clockwise: false` here reads as clockwise.
        let start = -CGFloat.pi / 2 + 0.55   // just past 12 o'clock
        let end = start + CGFloat.pi * 1.6    // ~290° of sweep
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                   startAngle: start, endAngle: end, clockwise: false)
        ctx.strokePath()

        // Solid arrowhead tangent to the arc at its start (the open end), pointing
        // in the direction of travel so the arc reads as a rotating arrow.
        let tip = CGPoint(x: cx + r * cos(start), y: cy + r * sin(start))
        // Tangent direction at `start` for a counter-clockwise-parametrised arc is
        // (-sin, cos); negate to point "backwards" into the sweep's leading edge.
        let tangent = CGPoint(x: sin(start), y: -cos(start))
        let normal = CGPoint(x: cos(start), y: sin(start))   // radial (outward)
        let headLen: CGFloat = 42
        let headHalf: CGFloat = 30
        let base = CGPoint(x: tip.x + tangent.x * headLen, y: tip.y + tangent.y * headLen)
        let p1 = CGPoint(x: base.x + normal.x * headHalf, y: base.y + normal.y * headHalf)
        let p2 = CGPoint(x: base.x - normal.x * headHalf, y: base.y - normal.y * headHalf)
        ctx.setFillColor(white.cgColor)
        ctx.beginPath()
        ctx.move(to: tip)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()

        ctx.restoreGState()
    }

    // MARK: - Small drawing helpers

    private static func fillDisc(_ ctx: CGContext, cx: CGFloat, cy: CGFloat, r: CGFloat, color: NSColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    /// Stroke a polyline whose points are given in the 200-unit mockup space.
    private static func strokePolyline(_ ctx: CGContext, points: [CGPoint], color: NSColor, width: CGFloat) {
        strokePolyline(ctx, pointsAbsolute: points.map(scale), color: color, width: width * 5.12)
    }

    /// Stroke a polyline whose points are already in the 1024 canvas space.
    private static func strokePolyline(_ ctx: CGContext, pointsAbsolute pts: [CGPoint], color: NSColor, width: CGFloat) {
        guard let first = pts.first else { return }
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: first)
        for p in pts.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Map a point from the 200-unit mockup space to the 1024 canvas.
    private static func scale(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * 5.12, y: p.y * 5.12) }

    private static func drawVerticalGradient(_ ctx: CGContext,
                                             stops: [(CGFloat, NSColor)],
                                             from: CGPoint, to: CGPoint) {
        let colors = stops.map { $0.1.cgColor } as CFArray
        let locations = stops.map { $0.0 }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: locations) else { return }
        ctx.drawLinearGradient(gradient, start: from, end: to, options: [])
    }

    private static func hex(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xff) / 255,
                green: CGFloat((rgb >> 8) & 0xff) / 255,
                blue: CGFloat(rgb & 0xff) / 255,
                alpha: 1)
    }
}
