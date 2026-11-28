import AppKit
import SwiftUI
import Combine

/// Everything a boomerang animation gets for one frame. Coordinates are points, origin top-left, y downward.
struct FlightFrame {
    let t: Double
    let duration: Double
    var seconds: Double { t * duration }
    let size: CGSize
    let from: CGRect
    let to: CGRect
    let notch: CGRect
    var distance: Double { FlightScene.distance(from, to) }
    let bg: RGBA
    let text: RGBA
    let accent: RGBA
    let dark: Bool
    let seed: UInt32
    let fromCells: CloseCells
    let toCells: CloseCells
    fileprivate let fromImage: GraphicsContext.ResolvedImage
    fileprivate let toImage: GraphicsContext.ResolvedImage

    var fromPath: Path { fromPath(in: from) }
    var toPath: Path { toPath(in: to) }
    func fromPath(in rect: CGRect) -> Path { closePadPath(in: rect, floating: true) }
    func toPath(in rect: CGRect) -> Path { closePadPath(in: rect, floating: false) }

    func drawFrom(_ ctx: GraphicsContext, in rect: CGRect? = nil, opacity: Double = 1) {
        draw(fromImage, in: rect ?? from, opacity: opacity, ctx)
    }

    func drawTo(_ ctx: GraphicsContext, in rect: CGRect? = nil, opacity: Double = 1) {
        draw(toImage, in: rect ?? to, opacity: opacity, ctx)
    }

    private func draw(_ image: GraphicsContext.ResolvedImage, in rect: CGRect, opacity: Double, _ ctx: GraphicsContext) {
        guard opacity > 0 else { return }
        var c = ctx
        c.opacity *= min(1, opacity)
        c.draw(image, in: rect)
    }
}

/// Draw only from the frame, with no external clock or random state.
/// At take-off the art must match `drawFrom`; at landing it must match `drawTo`.
protocol FlightEffectRenderer {
    var duration: Double { get }
    func draw(_ f: FlightFrame, _ ctx: GraphicsContext)
}

enum FlightEffect: String, CaseIterable, Identifiable {
    case boomerang, gate, beam, codestream, warp, swarm, bolt, comet
    var id: String { rawValue }

    var label: String {
        switch self {
        case .boomerang: return "Boomerang"
        case .gate: return "Stargate jump"
        case .beam: return "Transporter beam"
        case .codestream: return "Code stream"
        case .warp: return "Warp jump"
        case .swarm: return "Swarm"
        case .bolt: return "Lightning arc"
        case .comet: return "Comet"
        }
    }

    var detail: String {
        switch self {
        case .boomerang: return "The pad swings out and curves back into the notch."
        case .gate: return "A glowing gate takes the pad back to the notch."
        case .beam: return "The pad turns to light and takes shape again at the notch."
        case .codestream: return "The pad breaks into streams of code that race home."
        case .warp: return "The pad stretches into streaks of light and jumps home."
        case .swarm: return "Little pieces of the pad fly home and fit back together."
        case .bolt: return "A flash of lightning carries the pad back into place."
        case .comet: return "The pad streaks home with a glowing tail."
        }
    }

    var symbol: String {
        switch self {
        case .boomerang: return "arrow.uturn.backward"
        case .gate: return "circle.circle"
        case .beam: return "sparkles"
        case .codestream: return "character.textbox"
        case .warp: return "rays"
        case .swarm: return "circle.grid.3x3.fill"
        case .bolt: return "bolt.fill"
        case .comet: return "sparkle"
        }
    }

    var renderer: FlightEffectRenderer {
        switch self {
        case .boomerang: return BoomerangFlight()
        case .gate: return GateFlight()
        case .beam: return BeamFlight()
        case .codestream: return CodestreamFlight()
        case .warp: return WarpFlight()
        case .swarm: return SwarmFlight()
        case .bolt: return BoltFlight()
        case .comet: return CometFlight()
        }
    }

    private static let themeEffects: [String: FlightEffect] = [
        "matrix": .codestream, "stargate": .gate, "storm": .bolt, "transporter": .beam,
        "singularity": .comet, "blueprint": .beam, "neon-district": .warp,
        "chalkboard": .swarm, "field-notes": .swarm,
        "synthwave": .warp, "aurora": .comet, "deep-sea": .swarm
    ]

    static func resolve(setting: String, theme: PadThemeSpec) -> FlightEffect? {
        switch setting {
        case "classic": return nil
        case "random": return allCases.randomElement()
        case "theme":
            if let named = theme.extras["notchpad-boomerang"], let effect = FlightEffect(rawValue: named) {
                return effect
            }
            return themeEffects[theme.id] ?? .boomerang
        default: return FlightEffect(rawValue: setting)
        }
    }
}

enum FlightMockLayout: String, CaseIterable {
    case near, far, left, right, below

    var origin: CGPoint {
        switch self {
        case .near: return CGPoint(x: 455, y: 172)
        case .far: return CGPoint(x: 625, y: 440)
        case .left: return CGPoint(x: 55, y: 268)
        case .right: return CGPoint(x: 625, y: 268)
        case .below: return CGPoint(x: 340, y: 440)
        }
    }
}

/// The data that stays the same from take-off to landing.
struct FlightScene {
    typealias Picture = (image: CGImage, scale: CGFloat)

    let effect: FlightEffect
    let renderer: FlightEffectRenderer
    let duration: Double
    let size: CGSize
    let from: CGRect
    let to: CGRect
    let notch: CGRect
    let bg: RGBA
    let text: RGBA
    let accent: RGBA
    let dark: Bool
    let seed: UInt32
    let fromPicture: Picture
    let toPicture: Picture
    let fromCells: CloseCells
    let toCells: CloseCells
    let virtualNotch: Bool

    static func distance(_ from: CGRect, _ to: CGRect) -> Double {
        hypot(Double(to.midX - from.midX), Double(to.midY - from.midY))
    }

    init(effect: FlightEffect, theme: PadThemeSpec, speed: Double, size: CGSize,
         from: CGRect, to: CGRect, notch: CGRect, fromPicture: Picture, toPicture: Picture, seed: UInt32,
         virtualNotch: Bool = false) {
        let renderer = effect.renderer
        self.effect = effect
        self.renderer = renderer
        let distanceFactor = lerp(0.65, 1.2, smoothstep(24, 1100, Self.distance(from, to)))
        self.duration = max(0.15, renderer.duration * speed * distanceFactor)
        self.size = size
        self.from = from
        self.to = to
        self.notch = notch
        self.bg = RGBA(theme.background)
        self.text = RGBA(theme.text)
        self.accent = RGBA(theme.accent)
        self.dark = theme.isDark
        self.seed = seed
        self.fromPicture = fromPicture
        self.toPicture = toPicture
        self.fromCells = CloseScene.makeCells(from: fromPicture.image, pad: from)
        self.toCells = CloseScene.makeCells(from: toPicture.image, pad: to)
        self.virtualNotch = virtualNotch
    }

    func frame(t: Double, fromImage: GraphicsContext.ResolvedImage, toImage: GraphicsContext.ResolvedImage) -> FlightFrame {
        FlightFrame(t: clamp01(t), duration: duration, size: size, from: from, to: to, notch: notch, bg: bg,
                    text: text, accent: accent, dark: dark, seed: seed, fromCells: fromCells, toCells: toCells,
                    fromImage: fromImage, toImage: toImage)
    }

    static func mock(effect: FlightEffect, theme: PadThemeSpec, layout: FlightMockLayout = .far,
                     seed: UInt32 = 20261128) -> FlightScene? {
        let size = CGSize(width: 1180, height: 760)
        let padSize = CGSize(width: 500, height: 290)
        let from = CGRect(origin: layout.origin, size: padSize)
        let to = CGRect(x: 340, y: 0, width: padSize.width, height: padSize.height)
        let notch = CGRect(x: 500, y: 0, width: 180, height: 32)
        guard let first = CloseScene.mock(effect: .matrix, theme: theme, padSize: padSize, floating: true),
              let last = CloseScene.mock(effect: .matrix, theme: theme, padSize: padSize) else { return nil }
        return FlightScene(effect: effect, theme: theme, speed: 1, size: size, from: from, to: to, notch: notch,
                           fromPicture: (first.picture, first.pictureScale), toPicture: (last.picture, last.pictureScale),
                           seed: seed, virtualNotch: true)
    }
}

var flightDebugDraws = 0

struct FlightEffectCanvas: View {
    let scene: FlightScene
    let t: Double
    var fit = false
    var classicPreview = false
    var visible: CGRect? = nil
    var countLiveFrames = false

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, viewSize in
            if notchPadDebug && countLiveFrames { flightDebugDraws += 1 }
            var c = context
            let area = visible ?? CGRect(origin: .zero, size: scene.size)
            if fit, area.width > 0, area.height > 0 {
                let k: CGFloat = min(viewSize.width / area.width, viewSize.height / area.height)
                c.translateBy(x: (viewSize.width - area.width * k) / 2, y: (viewSize.height - area.height * k) / 2)
                c.scaleBy(x: k, y: k)
                c.translateBy(x: -area.minX, y: -area.minY)
            }
            let first = context.resolve(Image(decorative: scene.fromPicture.image, scale: scene.fromPicture.scale))
            let last = context.resolve(Image(decorative: scene.toPicture.image, scale: scene.toPicture.scale))
            let frame = scene.frame(t: t, fromImage: first, toImage: last)
            if scene.virtualNotch && frame.t > 0 && frame.t < 1 {
                // The landing spot on Macs without a camera housing. Ease it in and out so
                // both endpoint pictures still match their real windows, even with a translucent pad.
                let alpha = smoothstep(0, 0.12, frame.t) * (1 - smoothstep(0.88, 1, frame.t))
                let pill = scene.notch.insetBy(dx: -6, dy: 0)
                let path = NotchShape(topRadius: 6, bottomRadius: 9).path(in: pill)
                c.fill(path, with: .color(.black.opacity(alpha)))
            }
            if frame.t <= 0 {
                frame.drawFrom(c)
            } else if frame.t >= 1 {
                frame.drawTo(c)
            } else if classicPreview {
                drawSampleFlight(frame, c, bowScale: 0)
            } else {
                scene.renderer.draw(frame, c)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A simple glide for the Classic preview and for placeholder renderers.
func drawSampleFlight(_ f: FlightFrame, _ ctx: GraphicsContext, bowScale: Double = 1) {
    let t = smoothstep(0, 1, f.t)
    let bow = sin(.pi * t) * min(100, f.distance * 0.25) * bowScale
    let x = lerp(Double(f.from.minX), Double(f.to.minX), t) + bow
    let y = lerp(Double(f.from.minY), Double(f.to.minY), t)
    let w = lerp(Double(f.from.width), Double(f.to.width), t)
    let h = lerp(Double(f.from.height), Double(f.to.height), t)
    let rect = CGRect(x: x, y: y, width: w, height: h)
    f.drawFrom(ctx, in: rect, opacity: 1 - t)
    f.drawTo(ctx, in: rect, opacity: t)
}

// MARK: - Player

private struct FlightRun {
    let scene: FlightScene
    let start: Date
    let frozen: Double?

    func progress(at date: Date) -> Double {
        frozen ?? clamp01(date.timeIntervalSince(start) / scene.duration)
    }
}

private final class FlightOverlayModel: ObservableObject {
    enum Contents {
        case hold(FlightScene.Picture, CGRect)
        case fly(FlightRun)
    }

    @Published var contents: Contents?
}

private struct FlightOverlayStage: View {
    @ObservedObject var model: FlightOverlayModel

    var body: some View {
        Group {
            switch model.contents {
            case .hold(let picture, let rect):
                Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
                    let image = context.resolve(Image(decorative: picture.image, scale: picture.scale))
                    context.draw(image, in: rect)
                }
            case .fly(let run):
                if let t = run.frozen {
                    FlightEffectCanvas(scene: run.scene, t: t, countLiveFrames: true)
                } else {
                    TimelineView(.animation) { timeline in
                        FlightEffectCanvas(scene: run.scene, t: run.progress(at: timeline.date), countLiveFrames: true)
                    }
                }
            case nil:
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

final class FlightEffectPlayer {
    static let shared = FlightEffectPlayer()

    struct Route {
        let bounds: CGRect
        let from: CGRect
        let to: CGRect
        let notch: CGRect

        init?(from: NSRect, to: NSRect, notch: NSRect, screen: NSRect) {
            // A close-by return is better as a short, ordinary pull. Clip the canvas, not the pads,
            // to the display that owns the notch. Coordinates below here are top-left, y downward.
            guard screen.width > 0, screen.height > 0, from.width > 1, to.width > 1,
                  from.height > 1, to.height > 1, FlightScene.distance(from, to) >= 54 else { return nil }
            let union = from.union(to)
            let padded = union.insetBy(dx: -CloseScene.bleed, dy: -CloseScene.bleed)
            let frame = padded.intersection(screen)
            guard !frame.isEmpty, screen.insetBy(dx: -1, dy: -1).contains(union) else { return nil }
            func local(_ r: NSRect) -> CGRect {
                CGRect(x: r.minX - frame.minX, y: frame.maxY - r.maxY, width: r.width, height: r.height)
            }
            self.bounds = frame
            self.from = local(from)
            self.to = local(to)
            self.notch = local(notch)
        }
    }

    private let model = FlightOverlayModel()
    private var window: CloseEffectWindow?
    private var serial = 0
    private var restorePad: ((Bool) -> Void)?
    var isPlaying: Bool { restorePad != nil }

    private static let environment = ProcessInfo.processInfo.environment

    func effectForNextFlight() -> FlightEffect? {
        guard !testNoEffects, !reduceMotionOn else { return nil }
        if notchPadDebug, let id = Self.environment["NOTCHPAD_DEBUG_FLIGHT"], let forced = FlightEffect(rawValue: id) {
            return forced
        }
        return FlightEffect.resolve(setting: Settings.shared.flightEffect, theme: ThemeStore.shared.current)
    }

    private static var frozen: Double? {
        guard notchPadDebug, let raw = environment["NOTCHPAD_DEBUG_FLIGHT_FREEZE"],
              let value = Double(raw), value.isFinite else { return nil }
        return clamp01(value)
    }

    /// Covers the floating pad before the controller repositions the real window.
    func cover(_ route: Route, picture: FlightScene.Picture, panel: NSPanel, restore: @escaping (Bool) -> Void) -> Int {
        cancel()
        let win: CloseEffectWindow
        if let existing = window {
            win = existing
        } else {
            win = CloseEffectWindow()
            let host = NSHostingView(rootView: FlightOverlayStage(model: model))
            host.autoresizingMask = [.width, .height]
            win.contentView = host
            window = win
        }
        serial += 1
        restorePad = restore
        win.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        win.sharingType = panel.sharingType
        win.setFrame(route.bounds, display: false)
        model.contents = .hold(picture, route.from)
        win.contentView?.layoutSubtreeIfNeeded()
        win.orderFrontRegardless()
        win.displayIfNeeded()
        return serial
    }

    func isCurrent(_ token: Int) -> Bool { serial == token && isPlaying }

    func play(_ scene: FlightScene, token: Int) {
        guard isCurrent(token) else { return }
        let frozen = Self.frozen
        let drawsBefore = flightDebugDraws
        model.contents = .fly(FlightRun(scene: scene, start: Date(), frozen: frozen))
        debugLog("NOTCHPAD_FLIGHT effect=\(scene.effect.rawValue) distance=\(Int(FlightScene.distance(scene.from, scene.to)))")
        if frozen == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + scene.duration + 0.035) { [weak self] in
                guard let self = self, self.isCurrent(token) else { return }
                self.finish()
                debugLog("NOTCHPAD_FLIGHT_DONE effect=\(scene.effect.rawValue) frames=\(flightDebugDraws - drawsBefore) seconds=\(scene.duration)")
            }
        }
    }

    func cancel() {
        guard isPlaying else { return }
        serial += 1
        finish()
    }

    private func finish() {
        let restore = restorePad
        restorePad = nil
        let didFly: Bool
        if case .fly = model.contents { didFly = true } else { didFly = false }
        // Reveal the pad underneath the final frame, then lift off the overlay in this same turn.
        restore?(didFly)
        window?.orderOut(nil)
        model.contents = nil
    }

    /// The note is never photographed while it should be blurred. A plain silhouette is safer than
    /// relying on SwiftUI's blur filter while AppKit is caching the view into a bitmap.
    static func picture(of panel: NSPanel, pad: CGRect, floating: Bool, obscured: Bool,
                        theme: PadThemeSpec, opacity: Double) -> FlightScene.Picture? {
        if !obscured {
            panel.contentView?.layoutSubtreeIfNeeded()
            return CloseEffectPlayer.snapshot(of: panel, padRect: pad)
        }
        let scale = panel.backingScaleFactor
        let local = CGRect(origin: .zero, size: pad.size)
        guard let image = closeBitmap(width: pad.width, height: pad.height, scale: scale, draw: { ctx in
            let fill = theme.background.withAlphaComponent(CGFloat(clamp01(opacity))).usingColorSpace(.sRGB)?.cgColor
                ?? CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            ctx.setFillColor(fill)
            ctx.addPath(closePadPath(in: local, floating: floating).cgPath)
            ctx.fillPath()
        }) else { return nil }
        return (image, scale)
    }
}

// MARK: - Build checks

enum FlightDebugFrames {
    private static let environment = ProcessInfo.processInfo.environment

    static func writeIfAsked() {
        guard notchPadDebug, let raw = environment["NOTCHPAD_DEBUG_FLIGHT_FRAMES"],
              let n = Int(raw), n >= 1, n <= 120 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Task { @MainActor in write(n) }
        }
    }

    @MainActor
    private static func write(_ n: Int) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("flight-frames", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let theme = ThemeStore.shared.current
        let layout = environment["NOTCHPAD_DEBUG_FLIGHT_LAYOUT"].flatMap(FlightMockLayout.init(rawValue:)) ?? .far
        let only = environment["NOTCHPAD_DEBUG_FLIGHT_ONLY"]?.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        var count = 0
        for effect in FlightEffect.allCases {
            if let only = only, !only.contains(effect.rawValue) { continue }
            guard let scene = FlightScene.mock(effect: effect, theme: theme, layout: layout) else { continue }
            for i in 0..<n {
                let t = n == 1 ? 0.5 : Double(i) / Double(n - 1)
                let name = String(format: "flight-%@-%03d.png", effect.rawValue, i)
                if let data = png(of: scene, t: t), (try? data.write(to: dir.appendingPathComponent(name))) != nil {
                    count += 1
                }
            }
        }
        debugLog("NOTCHPAD_FLIGHT_FRAMES dir=\(dir.path) count=\(count)")
    }

    @MainActor
    private static func png(of scene: FlightScene, t: Double) -> Data? {
        let backdrop = LinearGradient(colors: [Color(.sRGB, red: 0.11, green: 0.13, blue: 0.2, opacity: 1),
                                               Color(.sRGB, red: 0.23, green: 0.17, blue: 0.25, opacity: 1)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        let view = ZStack(alignment: .topLeading) {
            Rectangle().fill(backdrop)
            FlightEffectCanvas(scene: scene, t: t)
        }
        .frame(width: scene.size.width, height: scene.size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}
