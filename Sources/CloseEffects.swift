import SwiftUI
import AppKit
import Combine

// Closing animations. When the pad closes, a picture of it is taken and handed to one of the effects
// below, which draws it coming apart in a see-through window laid exactly over the pad. The pad itself
// has already closed underneath, so nothing about how NotchPad works depends on the animation.

// MARK: - Helpers every effect uses (the prototype harness has the same ones, with the same results)

func clamp01(_ x: Double) -> Double { x < 0 ? 0 : (x > 1 ? 1 : x) }
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
/// 0 before `a`, 1 after `b`, linear in between: gives each stage of an effect its own 0…1 clock.
func phase(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp01((t - a) / (b - a)) }
func easeIn(_ t: Double) -> Double { t * t * t }
func easeOut(_ t: Double) -> Double { let u: Double = 1 - t; return 1 - u * u * u }
func easeInOut(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t: Double = clamp01((x - a) / (b - a))
    return t * t * (3 - 2 * t)
}

/// Stateless random number in [0, 1) for a pair of integers.
func closeHash(_ i: Int, _ j: Int, _ seed: UInt32) -> Double {
    var h: UInt32 = UInt32(truncatingIfNeeded: i) &* 374761393
    h = h &+ UInt32(truncatingIfNeeded: j) &* 668265263
    h = h &+ seed &* 2246822519
    h = (h ^ (h >> 13)) &* 1274126177
    h ^= h >> 16
    return Double(h) / 4294967296.0
}

/// Seeded random sequence (mulberry32).
struct CloseRNG {
    private var s: UInt32
    init(_ seed: UInt32) { s = seed }
    mutating func next() -> Double {
        s = s &+ 0x6D2B79F5
        var t: UInt32 = s
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    /// 0 ..< n
    mutating func int(_ n: Int) -> Int { Int((next() * Double(n)).rounded(.down)) }
}

/// Smooth 2-D value noise in [0, 1).
func closeNoise(_ x: Double, _ y: Double, _ seed: UInt32) -> Double {
    let xf: Double = x.rounded(.down), yf: Double = y.rounded(.down)
    let xi = Int(xf), yi = Int(yf)
    let fx: Double = x - xf, fy: Double = y - yf
    let u: Double = fx * fx * (3 - 2 * fx), v: Double = fy * fy * (3 - 2 * fy)
    let a = closeHash(xi, yi, seed), b = closeHash(xi + 1, yi, seed)
    let c = closeHash(xi, yi + 1, seed), d = closeHash(xi + 1, yi + 1, seed)
    return lerp(lerp(a, b, u), lerp(c, d, u), v)
}

/// A colour as plain numbers (0…1), so effects can mix and fade colours.
struct RGBA {
    var r: Double, g: Double, b: Double, a: Double
    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }
    func mix(_ o: RGBA, _ t: Double) -> RGBA { RGBA(lerp(r, o.r, t), lerp(g, o.g, t), lerp(b, o.b, t), lerp(a, o.a, t)) }
    func alpha(_ a: Double) -> RGBA { RGBA(r, g, b, a) }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    static let white = RGBA(1, 1, 1, 1)
    static let black = RGBA(0, 0, 0, 1)
    static let clear = RGBA(0, 0, 0, 0)
}

/// The picture of the pad boiled down to a coarse grid of colours, for effects made of many small pieces.
struct CloseCells {
    let cols: Int
    let rows: Int
    /// Side of one cell, in points.
    let size: Double
    fileprivate let origin: CGPoint
    fileprivate let data: [UInt8]      // RGBA, premultiplied, row 0 at the top

    /// Average colour of that cell (alpha 0 where the pad has no pixels).
    func color(_ col: Int, _ row: Int) -> RGBA {
        if col < 0 || row < 0 || col >= cols || row >= rows { return RGBA.clear }
        let i = (row * cols + col) * 4
        if i + 3 >= data.count { return RGBA.clear }
        let a: Double = Double(data[i + 3]) / 255
        if a <= 0 { return RGBA.clear }
        return RGBA(min(1, Double(data[i]) / 255 / a), min(1, Double(data[i + 1]) / 255 / a), min(1, Double(data[i + 2]) / 255 / a), a)
    }
    /// Where that cell sits on the canvas.
    func rect(_ col: Int, _ row: Int) -> CGRect {
        CGRect(x: Double(origin.x) + Double(col) * size, y: Double(origin.y) + Double(row) * size, width: size, height: size)
    }
}

/// Everything an effect gets for one frame. Coordinates are points, origin top-left, y downward.
struct CloseFrame {
    /// How far through the animation: 0 at the start, 1 at the end, linear in time.
    let t: Double
    /// Length of the whole animation in seconds (already includes the speed setting).
    let duration: Double
    var seconds: Double { t * duration }
    /// The canvas. The pad sits inside it with room around for sparks, bolts and rings.
    let size: CGSize
    /// Where the pad was.
    let pad: CGRect
    /// Where it ends up: the notch when docked, its own centre when floating.
    let sink: CGRect
    var target: CGPoint { CGPoint(x: sink.midX, y: sink.midY) }
    /// True when the pad was dragged away from the notch and is a plain rounded card.
    let floating: Bool
    let bg: RGBA
    let text: RGBA
    let accent: RGBA
    /// The theme's background is dark.
    let dark: Bool
    /// Different every time the pad closes; the same for every frame of one close.
    let seed: UInt32
    let cells: CloseCells
    fileprivate let image: GraphicsContext.ResolvedImage

    /// The pad's outline.
    var padPath: Path { padPath(in: pad) }
    func padPath(in rect: CGRect) -> Path { closePadPath(in: rect, floating: floating) }

    /// Draws the picture of the pad, by default exactly where the pad was.
    func drawPad(_ ctx: GraphicsContext, in rect: CGRect? = nil, opacity: Double = 1) {
        if opacity <= 0 { return }
        var c = ctx
        if opacity < 1 { c.opacity = c.opacity * opacity }
        c.draw(image, in: rect ?? pad)
    }
}

/// One closing animation. `draw` is called for every frame and must depend only on the frame:
/// no stored state, no clock, no random numbers except from `f.seed`.
protocol CloseEffectRenderer {
    /// Seconds at normal speed.
    var duration: Double { get }
    func draw(_ f: CloseFrame, _ ctx: GraphicsContext)
}

/// Docked: flat top that flares into the menu bar, round bottom corners. Floating: a rounded card.
func closePadPath(in r: CGRect, floating: Bool) -> Path {
    if floating {
        let radius: CGFloat = min(18, r.width / 2, r.height / 2)
        return Path(roundedRect: r, cornerRadius: max(0, radius), style: .continuous)
    }
    let t: CGFloat = max(0, min(12, r.width / 4, r.height / 2))
    let b: CGFloat = max(0, min(22, (r.width - 2 * t) / 2, r.height - t))
    var p = Path()
    p.move(to: CGPoint(x: r.minX, y: r.minY))
    p.addQuadCurve(to: CGPoint(x: r.minX + t, y: r.minY + t), control: CGPoint(x: r.minX + t, y: r.minY))
    p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
    p.addQuadCurve(to: CGPoint(x: r.minX + t + b, y: r.maxY), control: CGPoint(x: r.minX + t, y: r.maxY))
    p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
    p.addQuadCurve(to: CGPoint(x: r.maxX - t, y: r.maxY - b), control: CGPoint(x: r.maxX - t, y: r.maxY))
    p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
    p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - t, y: r.minY))
    p.closeSubpath()
    return p
}

// MARK: - The list of animations

enum CloseEffect: String, CaseIterable, Identifiable {
    case lightning, matrix, teleport, stargate, blackHole, tv, dust, burn
    var id: String { rawValue }

    var label: String {
        switch self {
        case .lightning: return "Lightning"
        case .matrix: return "Matrix"
        case .teleport: return "Teleport"
        case .stargate: return "Stargate"
        case .blackHole: return "Black hole"
        case .tv: return "Old TV"
        case .dust: return "Dust"
        case .burn: return "Burn"
        }
    }
    var detail: String {
        switch self {
        case .lightning: return "A bolt strikes and zaps it shut."
        case .matrix: return "It dissolves into falling ones and zeros."
        case .teleport: return "It turns to light and zips away."
        case .stargate: return "A rippling gate swallows it and winks out."
        case .blackHole: return "It's pulled apart and swirls into the notch."
        case .tv: return "It squashes to a bright line, then a dot, like an old TV switching off."
        case .dust: return "It crumbles and blows away."
        case .burn: return "It burns away from the bottom, leaving embers."
        }
    }
    var symbol: String {
        switch self {
        case .lightning: return "bolt.fill"
        case .matrix: return "character.textbox"
        case .teleport: return "sparkles"
        case .stargate: return "circle.circle"
        case .blackHole: return "hurricane"
        case .tv: return "tv"
        case .dust: return "wind"
        case .burn: return "flame.fill"
        }
    }
    var renderer: CloseEffectRenderer {
        switch self {
        case .lightning: return LightningClose()
        case .matrix: return MatrixClose()
        case .teleport: return TeleportClose()
        case .stargate: return StargateClose()
        case .blackHole: return BlackHoleClose()
        case .tv: return TVClose()
        case .dust: return DustClose()
        case .burn: return BurnClose()
        }
    }

    /// Turns the saved setting into the animation to play now. nil means the classic close.
    static func resolve(setting: String, theme: PadThemeSpec) -> CloseEffect? {
        switch setting {
        case "classic": return nil
        case "random": return CloseEffect.allCases.randomElement()
        case "theme": return theme.closeEffectID.flatMap { CloseEffect(rawValue: $0) }
        default: return CloseEffect(rawValue: setting)
        }
    }
}

// MARK: - A run: the fixed facts about one close

private func closeBitmap(width: CGFloat, height: CGFloat, scale: CGFloat, draw: (CGContext) -> Void) -> CGImage? {
    let pw = Int((width * scale).rounded(.up)), ph = Int((height * scale).rounded(.up))
    guard pw > 0, ph > 0, pw < 8000, ph < 8000,
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    // Top-left origin, in points.
    ctx.translateBy(x: 0, y: CGFloat(ph))
    ctx.scaleBy(x: scale, y: -scale)
    draw(ctx)
    return ctx.makeImage()
}

/// Draws an upright image into a context that has a top-left origin.
private func closeDraw(_ image: CGImage, in rect: CGRect, _ ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    ctx.restoreGState()
}

struct CloseScene {
    let effect: CloseEffect
    let renderer: CloseEffectRenderer
    let duration: Double
    let size: CGSize
    let pad: CGRect
    let sink: CGRect
    let floating: Bool
    let bg: RGBA
    let text: RGBA
    let accent: RGBA
    let dark: Bool
    let seed: UInt32
    let picture: CGImage
    let pictureScale: CGFloat
    let cells: CloseCells

    /// Room around the pad for the effect to draw in.
    static let bleed: CGFloat = 160

    init?(effect: CloseEffect, theme: PadThemeSpec, speed: Double, size: CGSize, pad: CGRect, sink: CGRect, floating: Bool,
          picture rawPicture: CGImage?, pictureScale: CGFloat, seed: UInt32) {
        let renderer = effect.renderer
        self.effect = effect
        self.renderer = renderer
        self.duration = max(0.15, renderer.duration * speed)
        self.size = size
        self.pad = pad
        self.sink = sink
        self.floating = floating
        self.bg = RGBA(theme.background)
        self.text = RGBA(theme.text)
        self.accent = RGBA(theme.accent)
        self.dark = theme.isDark
        self.seed = seed
        self.pictureScale = pictureScale
        // Trim the picture to the pad's outline; if there is no picture, use a plain pad in the theme's colour.
        let local = CGRect(x: 0, y: 0, width: pad.width, height: pad.height)
        let outline = closePadPath(in: local, floating: floating).cgPath
        let background = theme.background.usingColorSpace(.sRGB)?.cgColor ?? CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let trimmed = closeBitmap(width: pad.width, height: pad.height, scale: pictureScale, draw: { ctx in
            ctx.addPath(outline)
            ctx.clip()
            if let raw = rawPicture {
                closeDraw(raw, in: local, ctx)
            } else {
                ctx.setFillColor(background)
                ctx.fill(local)
            }
        }) else { return nil }
        self.picture = trimmed
        self.cells = CloseScene.makeCells(from: trimmed, pad: pad)
    }

    private static func makeCells(from picture: CGImage, pad: CGRect) -> CloseCells {
        let size: Double = max(6, (Double(pad.width) * Double(pad.height) / 5000).squareRoot())
        let cols = max(1, Int((Double(pad.width) / size).rounded(.up)))
        let rows = max(1, Int((Double(pad.height) / size).rounded(.up)))
        var data = [UInt8](repeating: 0, count: cols * rows * 4)
        if let space = CGColorSpace(name: CGColorSpace.sRGB) {
            data.withUnsafeMutableBytes { raw in
                guard let ctx = CGContext(data: raw.baseAddress, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: cols * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                ctx.interpolationQuality = .medium
                // One cell = one pixel. The picture's top-left goes to the top-left (row 0 of the data).
                let w = CGFloat(Double(pad.width) / size), h = CGFloat(Double(pad.height) / size)
                ctx.draw(picture, in: CGRect(x: 0, y: CGFloat(rows) - h, width: w, height: h))
            }
        }
        return CloseCells(cols: cols, rows: rows, size: size, origin: pad.origin, data: data)
    }

    func frame(t: Double, image: GraphicsContext.ResolvedImage) -> CloseFrame {
        CloseFrame(t: clamp01(t), duration: duration, size: size, pad: pad, sink: sink, floating: floating,
                   bg: bg, text: text, accent: accent, dark: dark, seed: seed, cells: cells, image: image)
    }

    /// A stand-in pad for the Settings previews and the build checks (the real thing uses a picture of your pad).
    static func mock(effect: CloseEffect, theme: PadThemeSpec, padSize: CGSize = CGSize(width: 360, height: 200),
                     floating: Bool = false, seed: UInt32 = 20261128) -> CloseScene? {
        let bleed = CloseScene.bleed
        let size = CGSize(width: padSize.width + 2 * bleed, height: padSize.height + bleed + (floating ? bleed : 0))
        let pad = CGRect(x: bleed, y: floating ? bleed : 0, width: padSize.width, height: padSize.height)
        let sink = floating
            ? CGRect(x: pad.midX - 20, y: pad.midY - 3, width: 40, height: 6)
            : CGRect(x: pad.midX - 90, y: 0, width: 180, height: 32)
        let scale: CGFloat = 2
        let picture = closeBitmap(width: padSize.width, height: padSize.height, scale: scale) { ctx in
            let local = CGRect(x: 0, y: 0, width: padSize.width, height: padSize.height)
            ctx.addPath(closePadPath(in: local, floating: floating).cgPath)
            ctx.clip()
            ctx.setFillColor(theme.background.usingColorSpace(.sRGB)?.cgColor ?? CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(local)
            let top: CGFloat = floating ? 8 : 34, left: CGFloat = floating ? 16 : 24, right: CGFloat = padSize.width - (floating ? 16 : 24)
            let dim = theme.text.withAlphaComponent(0.55).usingColorSpace(.sRGB)?.cgColor ?? CGColor(gray: 0.6, alpha: 1)
            let accent = theme.accent.usingColorSpace(.sRGB)?.cgColor ?? CGColor(gray: 0.8, alpha: 1)
            for i in 0..<4 {
                ctx.setFillColor(dim)
                ctx.fill(CGRect(x: left + CGFloat(i) * 24, y: top + 3, width: 13, height: 13))
                ctx.setFillColor(i == 3 ? accent : dim)
                ctx.fill(CGRect(x: right - 13 - CGFloat(i) * 24, y: top + 3, width: 13, height: 13))
            }
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let lines = ["Things to remember", "", "Call the plumber about the tap", "milk, eggs, coffee, bread",
                         "Wi-Fi at the bach: kowhai-5G", "Ideas for the deck: wider steps,", "a seat along the fence, lights",
                         "Book the ferry for Friday", "Ring Mum on Sunday"]
            let attributes = theme.textAttributes(.theme, size: 13)
            var y: CGFloat = top + 28
            for line in lines {
                if y > padSize.height - 30 { break }
                if !line.isEmpty { NSAttributedString(string: line, attributes: attributes).draw(at: CGPoint(x: left + 4, y: y)) }
                y += 19
            }
            NSGraphicsContext.current = previous
        }
        return CloseScene(effect: effect, theme: theme, speed: 1, size: size, pad: pad, sink: sink, floating: floating,
                          picture: picture, pictureScale: scale, seed: seed)
    }
}

/// Draws one frame of a run. `visible` picks the part of the canvas to show, scaled to fit the view
/// (used by the small previews); nil shows it all at its real size.
struct CloseEffectCanvas: View {
    let scene: CloseScene
    let t: Double
    var visible: CGRect? = nil

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, viewSize in
            let image = context.resolve(Image(decorative: scene.picture, scale: scene.pictureScale))
            let frame = scene.frame(t: t, image: image)
            if frame.t >= 1 { return }
            if let v = visible, v.width > 0, v.height > 0 {
                var c = context
                let k: CGFloat = min(viewSize.width / v.width, viewSize.height / v.height)
                c.translateBy(x: (viewSize.width - v.width * k) / 2, y: (viewSize.height - v.height * k) / 2)
                c.scaleBy(x: k, y: k)
                c.translateBy(x: -v.minX, y: -v.minY)
                scene.renderer.draw(frame, c)
            } else {
                scene.renderer.draw(frame, context)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Playing it over the real pad

struct CloseRun {
    let id: Int
    let scene: CloseScene
    let start: Date
    /// Build checks: hold the animation at this point.
    let frozen: Double?
    func progress(at date: Date) -> Double {
        if let f = frozen { return f }
        return clamp01(date.timeIntervalSince(start) / scene.duration)
    }
}

final class CloseEffectModel: ObservableObject {
    @Published var run: CloseRun?
}

private struct CloseEffectStage: View {
    @ObservedObject var model: CloseEffectModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let run = model.run {
                if run.frozen != nil {
                    CloseEffectCanvas(scene: run.scene, t: run.progress(at: run.start))
                } else {
                    TimelineView(.animation) { timeline in
                        CloseEffectCanvas(scene: run.scene, t: run.progress(at: timeline.date))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(model.run?.id ?? 0)
    }
}

private final class CloseEffectWindow: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        animationBehavior = .none
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Like the pad, it has to be able to sit over the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class CloseEffectPlayer {
    static let shared = CloseEffectPlayer()

    private let model = CloseEffectModel()
    private var window: CloseEffectWindow?
    private var counter = 0
    private(set) var isPlaying = false

    private static let environment = ProcessInfo.processInfo.environment
    private static var forced: CloseEffect? {
        guard notchPadDebug, let id = environment["NOTCHPAD_DEBUG_CLOSE"] else { return nil }
        return CloseEffect(rawValue: id)
    }
    private static var frozen: Double? {
        guard notchPadDebug, let raw = environment["NOTCHPAD_DEBUG_CLOSE_FREEZE"], let v = Double(raw) else { return nil }
        return clamp01(v)
    }

    /// The animation to use for the next close, or nil for the classic one.
    func effectForNextClose(override: CloseEffect? = nil) -> CloseEffect? {
        if testNoEffects || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return nil }
        if let o = override { return o }
        if let f = CloseEffectPlayer.forced { return f }
        return CloseEffect.resolve(setting: Settings.shared.closeEffect, theme: ThemeStore.shared.current)
    }

    /// Takes a picture of the pad as it is right now. Call it before the pad changes.
    /// `padRect` is the pad in screen coordinates.
    static func snapshot(of panel: NSWindow, padRect: NSRect) -> (image: CGImage, scale: CGFloat)? {
        guard let view = panel.contentView else { return nil }
        let inWindow = panel.convertFromScreen(padRect)
        let inView = view.convert(inWindow, from: nil).integral
        guard inView.width > 1, inView.height > 1, let rep = view.bitmapImageRepForCachingDisplay(in: inView) else { return nil }
        view.cacheDisplay(in: inView, to: rep)
        guard let image = rep.cgImage, inView.width > 0 else { return nil }
        return (image, CGFloat(image.width) / inView.width)
    }

    /// Starts the animation over the spot where the pad was. Everything is in screen coordinates.
    /// Returns false (and shows nothing) if it can't run.
    @discardableResult
    func play(_ effect: CloseEffect, picture: (image: CGImage, scale: CGFloat)?, padRect: NSRect, sinkRect: NSRect,
              floating: Bool, screen: NSRect, level: NSWindow.Level, sharing: NSWindow.SharingType) -> Bool {
        let bleed = CloseScene.bleed
        // The canvas: the pad plus room around it, but never above the top of the screen.
        let top: CGFloat = floating ? min(padRect.maxY + bleed, max(screen.maxY, padRect.maxY)) : padRect.maxY
        let frame = NSRect(x: padRect.minX - bleed, y: padRect.minY - bleed,
                           width: padRect.width + 2 * bleed, height: top - (padRect.minY - bleed))
        func local(_ r: NSRect) -> CGRect {
            CGRect(x: r.minX - frame.minX, y: frame.maxY - r.maxY, width: r.width, height: r.height)
        }
        let theme = ThemeStore.shared.current
        let seed = UInt32.random(in: 1...UInt32.max)
        guard let scene = CloseScene(effect: effect, theme: theme, speed: Settings.shared.closeSpeed.factor,
                                     size: frame.size, pad: local(padRect), sink: local(sinkRect), floating: floating,
                                     picture: picture?.image, pictureScale: picture?.scale ?? 2, seed: seed) else { return false }
        let win: CloseEffectWindow
        if let w = window {
            win = w
        } else {
            win = CloseEffectWindow()
            let host = NSHostingView(rootView: CloseEffectStage(model: model))
            host.autoresizingMask = [.width, .height]
            win.contentView = host
            window = win
        }
        counter += 1
        let id = counter
        let frozen = CloseEffectPlayer.frozen
        win.level = NSWindow.Level(rawValue: level.rawValue + 1)
        win.sharingType = sharing
        win.setFrame(frame, display: false)
        model.run = CloseRun(id: id, scene: scene, start: Date(), frozen: frozen)
        isPlaying = true
        win.orderFrontRegardless()
        win.displayIfNeeded()
        let snap = picture.map { "\($0.image.width)x\($0.image.height)" } ?? "none"
        if notchPadDebug, CloseEffectPlayer.environment["NOTCHPAD_DEBUG_CLOSE_SNAPSHOT"] != nil {
            // Build checks: save the picture the animation was given, to compare with the real pad.
            let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("close-snapshot.png")
            if let data = NSBitmapImageRep(cgImage: scene.picture).representation(using: .png, properties: [:]),
               (try? data.write(to: file)) != nil {
                debugLog("NOTCHPAD_CLOSE_SNAPSHOT file=\(file.path)")
            }
        }
        debugLog("NOTCHPAD_CLOSE effect=\(effect.rawValue) snapshot=\(snap) floating=\(floating)")
        if frozen == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + scene.duration + 0.03) { [weak self] in
                guard let self = self, self.counter == id, self.isPlaying else { return }
                self.finish()
                debugLog("NOTCHPAD_CLOSE_DONE effect=\(effect.rawValue)")
            }
        }
        return true
    }

    /// Stops and hides the animation at once (the pad is opening again, or the app is going away).
    func cancel() {
        guard isPlaying else { return }
        counter += 1
        finish()
    }

    private func finish() {
        isPlaying = false
        model.run = nil
        window?.orderOut(nil)
    }

    // MARK: Build checks

    /// NOTCHPAD_DEBUG_CLOSE_FRAMES=<n>: writes n still frames of every effect as PNG files.
    func writeDebugFramesIfAsked() {
        guard notchPadDebug, let raw = CloseEffectPlayer.environment["NOTCHPAD_DEBUG_CLOSE_FRAMES"],
              let n = Int(raw), n >= 2, n <= 120 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("close-frames", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let theme = ThemeStore.shared.current
            let floating = CloseEffectPlayer.environment["NOTCHPAD_DEBUG_CLOSE_FLOATING"] != nil
            var count = 0
            for effect in CloseEffect.allCases {
                guard let scene = CloseScene.mock(effect: effect, theme: theme, padSize: CGSize(width: 500, height: 290),
                                                  floating: floating) else { continue }
                for i in 0..<n {
                    let t: Double = Double(i) / Double(n - 1)
                    if let data = CloseEffectPlayer.png(of: scene, t: t) {
                        let name = String(format: "%@-%03d.png", effect.rawValue, i)
                        if (try? data.write(to: dir.appendingPathComponent(name))) != nil { count += 1 }
                    }
                }
            }
            debugLog("NOTCHPAD_CLOSE_FRAMES dir=\(dir.path) count=\(count)")
        }
    }

    /// One frame over a plain desktop-like backdrop, as PNG data.
    private static func png(of scene: CloseScene, t: Double) -> Data? {
        let backdrop = LinearGradient(colors: [Color(.sRGB, red: 0.11, green: 0.13, blue: 0.2, opacity: 1),
                                               Color(.sRGB, red: 0.23, green: 0.17, blue: 0.25, opacity: 1)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        let view = ZStack(alignment: .topLeading) {
            Rectangle().fill(backdrop)
            CloseEffectCanvas(scene: scene, t: t)
        }
        .frame(width: scene.size.width, height: scene.size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}

// MARK: - Small preview for Settings

/// The effect on a small stand-in pad, in the given theme. Loops while `playing`; otherwise a still frame.
struct CloseEffectPreview: View {
    let effect: CloseEffect
    let theme: PadThemeSpec
    let playing: Bool

    @State private var scene: CloseScene?
    @State private var started = Date()

    private static let padSize = CGSize(width: 300, height: 168)
    /// The part of the canvas shown: the pad with some room for the effect.
    private var visible: CGRect {
        let bleed = CloseScene.bleed
        return CGRect(x: bleed - 44, y: 0, width: CloseEffectPreview.padSize.width + 88, height: CloseEffectPreview.padSize.height + 52)
    }
    private var key: String { "\(effect.rawValue)|\(theme.id)|\(theme.name)|\(theme.isCustom)" }

    var body: some View {
        ZStack {
            if let scene = scene {
                if playing {
                    TimelineView(.animation) { timeline in
                        CloseEffectCanvas(scene: scene, t: loopProgress(at: timeline.date, scene: scene), visible: visible)
                    }
                } else {
                    CloseEffectCanvas(scene: scene, t: 0.42, visible: visible)
                }
            }
        }
        .onAppear { build() }
        .onChange(of: key) { _ in build() }
        .onChange(of: playing) { on in if on { started = Date() } }
    }

    private func build() {
        scene = CloseScene.mock(effect: effect, theme: theme, padSize: CloseEffectPreview.padSize)
    }

    /// Plays, rests on the empty frame for a moment, then starts again.
    private func loopProgress(at date: Date, scene: CloseScene) -> Double {
        let lead: Double = 0.35, rest: Double = 0.5
        let cycle: Double = lead + scene.duration + rest
        let elapsed: Double = max(0, date.timeIntervalSince(started))
        let inCycle: Double = elapsed.truncatingRemainder(dividingBy: cycle)
        return clamp01((inCycle - lead) / scene.duration)
    }
}
