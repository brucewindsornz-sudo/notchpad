import SwiftUI
import AppKit

/// A layered backdrop for a theme: base gradient, optional Canvas pattern, vignette and edge finish.
/// Built-in themes are looked up by id here; custom Ghostty-format theme files can opt in with
/// `notchpad-backdrop`, `notchpad-backdrop-color`, `notchpad-backdrop-tint`, `notchpad-edge-glow`
/// and `notchpad-vignette`.
struct ThemeBackdrop: Equatable {
    struct GradientStop: Equatable {
        var location: CGFloat
        var color: NSColor
    }

    enum Base: Equatable {
        case linear(stops: [GradientStop], start: UnitPoint, end: UnitPoint)
        case radial(stops: [GradientStop], center: UnitPoint, startFraction: CGFloat, endFraction: CGFloat)
    }

    enum Pattern: String, Equatable {
        case none
        case matrix
        case stargate
        case storm
        case transporter
        case singularity
        case phosphor
        case chalkboard
        case parchment
        case ruled
        case blueprint
        case neonDistrict
        case newsprint
        case synthwave
        case aurora
        case deepSea
        case liquidGlass

        /// Whether this pattern has gentle live motion when Moving backgrounds is on.
        var hasMotion: Bool {
            switch self {
            case .matrix, .stargate, .storm, .transporter, .singularity,
                 .phosphor, .neonDistrict, .synthwave, .aurora, .deepSea:
                return true
            case .none, .chalkboard, .parchment, .ruled, .blueprint, .newsprint, .liquidGlass:
                return false
            }
        }

        /// Parses the value of `notchpad-backdrop = ...` in a custom theme file.
        init?(custom raw: String) {
            let key = raw.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
            switch key {
            case "none", "flat", "subtle": self = .none
            case "matrix", "code", "rain": self = .matrix
            case "stargate", "starfield", "stars": self = .stargate
            case "storm", "clouds", "lightning": self = .storm
            case "transporter", "particles", "sparkles": self = .transporter
            case "singularity", "blackhole", "swirl": self = .singularity
            case "phosphor", "scanlines", "crt": self = .phosphor
            case "chalkboard", "chalk": self = .chalkboard
            case "parchment", "paper", "ember": self = .parchment
            case "ruled", "notebook", "lines": self = .ruled
            case "blueprint", "grid": self = .blueprint
            case "neondistrict", "neon", "horizon": self = .neonDistrict
            case "newsprint", "editorial": self = .newsprint
            case "synthwave", "sunset": self = .synthwave
            case "aurora", "northernlights": self = .aurora
            case "deepsea", "ocean", "caustics": self = .deepSea
            case "liquidglass", "glass", "frost": self = .liquidGlass
            default: return nil
            }
        }
    }

    struct Vignette: Equatable {
        var color: NSColor
        var strength: Double
    }

    struct Edge: Equatable {
        var hairlineColor: NSColor
        var hairlineOpacity: Double
        var hairlineWidth: CGFloat = 1
        var glowColor: NSColor? = nil
        var glowOpacity: Double = 0
        var glowWidth: CGFloat = 5
        var topSpecular: Double = 0
    }

    var base: Base
    var pattern: Pattern
    var patternTint: NSColor
    var patternSecondary: NSColor
    var vignette: Vignette
    var edge: Edge

    var hasMotion: Bool { pattern.hasMotion }
}

extension PadThemeSpec {
    /// The designed backdrop for this theme. Looked up by id for built-ins, or built from
    /// `extras` for custom Ghostty-format theme files.
    var backdrop: ThemeBackdrop {
        if isCustom { return ThemeBackdrop.custom(for: self) }
        if let built = ThemeBackdrop.builtIn[id] { return built }
        return ThemeBackdrop.standard(for: self)
    }
}

// MARK: - Built-in backdrop table

extension ThemeBackdrop {
    private static func hex(_ value: String) -> NSColor {
        NSColor(hex: value) ?? .black
    }

    private static func stop(_ loc: CGFloat, _ value: String) -> GradientStop {
        GradientStop(location: loc, color: hex(value))
    }

    /// Quiet, finished treatment for standard themes: gentle tonal depth, soft vignette, crisp hairline.
    static func standard(for theme: PadThemeSpec, topHex: String? = nil, bottomHex: String? = nil,
                         edgeHex: String? = nil, vignetteStrength: Double? = nil) -> ThemeBackdrop {
        let dark = theme.isDark
        let baseBG = theme.background
        let topColor: NSColor = topHex.map(hex) ?? (baseBG.blended(withFraction: dark ? 0.08 : 0.04, of: dark ? .white : .white) ?? baseBG)
        let bottomColor: NSColor = bottomHex.map(hex) ?? (baseBG.blended(withFraction: dark ? 0.14 : 0.05, of: .black) ?? baseBG)
        let edgeColor: NSColor = edgeHex.map(hex) ?? (dark ? (theme.accent.blended(withFraction: 0.65, of: .white) ?? .white) : (theme.text))
        let vigColor: NSColor = dark ? .black : (baseBG.blended(withFraction: 0.30, of: theme.text) ?? .black)
        let vigAmt: Double = vignetteStrength ?? (dark ? 0.22 : 0.12)
        return ThemeBackdrop(
            base: .linear(stops: [
                GradientStop(location: 0.0, color: topColor),
                GradientStop(location: 0.55, color: baseBG),
                GradientStop(location: 1.0, color: bottomColor)
            ], start: .topLeading, end: .bottomTrailing),
            pattern: .none,
            patternTint: theme.accent,
            patternSecondary: theme.text,
            vignette: Vignette(color: vigColor, strength: vigAmt),
            edge: Edge(
                hairlineColor: edgeColor,
                hairlineOpacity: dark ? 0.16 : 0.16,
                hairlineWidth: 1,
                glowColor: dark ? theme.accent : nil,
                glowOpacity: dark ? 0.05 : 0,
                glowWidth: 4,
                topSpecular: dark ? 0.07 : 0.25
            )
        )
    }

    /// Custom Ghostty-format theme files can specify:
    ///   notchpad-backdrop = grid | scanlines | ruled | chalk | matrix | starfield | storm | particles |
    ///                       singularity | newsprint | parchment | neon | synthwave | aurora | deepsea | glass | none
    ///   notchpad-backdrop-color = #hex   (secondary gradient stop)
    ///   notchpad-backdrop-tint = #hex    (pattern colour; defaults to cursor/accent)
    ///   notchpad-edge-glow = #hex        (inner hairline and subtle edge glow)
    ///   notchpad-vignette = 0.0...1.0    (optional vignette strength)
    static func custom(for theme: PadThemeSpec) -> ThemeBackdrop {
        let dark = theme.isDark
        let pattern = theme.extras["notchpad-backdrop"].flatMap(Pattern.init(custom:)) ?? .none
        let secondaryBG = theme.extras["notchpad-backdrop-color"].flatMap(NSColor.init(hex:))
        let tint = theme.extras["notchpad-backdrop-tint"].flatMap(NSColor.init(hex:)) ?? theme.accent
        let edgeGlow = theme.extras["notchpad-edge-glow"].flatMap(NSColor.init(hex:))
        let vigOverride = theme.extras["notchpad-vignette"].flatMap(Double.init).map { min(max($0, 0), 1) }

        let topColor: NSColor
        let bottomColor: NSColor
        if let sec = secondaryBG {
            topColor = sec
            bottomColor = theme.background.blended(withFraction: 0.22, of: .black) ?? theme.background
        } else {
            topColor = theme.background.blended(withFraction: dark ? 0.09 : 0.04, of: .white) ?? theme.background
            bottomColor = theme.background.blended(withFraction: dark ? 0.16 : 0.06, of: .black) ?? theme.background
        }

        let defaultVig: Double = pattern == .none ? (dark ? 0.22 : 0.12) : (dark ? 0.36 : 0.18)
        let edgeColor = edgeGlow ?? (dark ? tint : theme.text)
        return ThemeBackdrop(
            base: .linear(stops: [
                GradientStop(location: 0.0, color: topColor),
                GradientStop(location: 0.55, color: theme.background),
                GradientStop(location: 1.0, color: bottomColor)
            ], start: .topLeading, end: .bottomTrailing),
            pattern: pattern,
            patternTint: tint,
            patternSecondary: theme.text,
            vignette: Vignette(color: dark ? .black : theme.text, strength: vigOverride ?? defaultVig),
            edge: Edge(
                hairlineColor: edgeColor,
                hairlineOpacity: edgeGlow != nil ? 0.34 : (dark ? 0.20 : 0.16),
                hairlineWidth: 1,
                glowColor: edgeGlow ?? (pattern != .none && dark ? tint : nil),
                glowOpacity: edgeGlow != nil ? 0.18 : (pattern != .none && dark ? 0.10 : 0),
                glowWidth: 5,
                topSpecular: dark ? 0.08 : 0.25
            )
        )
    }

    static let builtIn: [String: ThemeBackdrop] = [
        // MARK: Standard themes (quiet, crafted depth)
        "notch": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#0b0c10"), stop(0.45, "#030305"), stop(1, "#000000")],
                          start: .top, end: .bottom),
            pattern: .none, patternTint: hex("#0a84ff"), patternSecondary: hex("#f2f2f2"),
            vignette: Vignette(color: .black, strength: 0.10),
            edge: Edge(hairlineColor: hex("#ffffff"), hairlineOpacity: 0.14, hairlineWidth: 1, topSpecular: 0.08)
        ),
        "graphite": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#333338"), stop(0.55, "#28282b"), stop(1, "#1e1e21")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#0a84ff"), patternSecondary: hex("#ebebeb"),
            vignette: Vignette(color: .black, strength: 0.22),
            edge: Edge(hairlineColor: hex("#ffffff"), hairlineOpacity: 0.14, hairlineWidth: 1, topSpecular: 0.10)
        ),
        "midnight": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#162447"), stop(0.55, "#0f1730"), stop(1, "#090e1f")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#6ea8ff"), patternSecondary: hex("#e0ebff"),
            vignette: Vignette(color: hex("#040712"), strength: 0.28),
            edge: Edge(hairlineColor: hex("#6ea8ff"), hairlineOpacity: 0.22, hairlineWidth: 1,
                       glowColor: hex("#3b78e7"), glowOpacity: 0.08, glowWidth: 4, topSpecular: 0.09)
        ),
        "paper": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#fdf9ee"), stop(0.6, "#faf4e3"), stop(1, "#f2e8cf")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#e8782a"), patternSecondary: hex("#26241f"),
            vignette: Vignette(color: hex("#b8a682"), strength: 0.16),
            edge: Edge(hairlineColor: hex("#6e6045"), hairlineOpacity: 0.28, hairlineWidth: 1, topSpecular: 0.35)
        ),
        "catppuccin-mocha": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#26263a"), stop(0.55, "#1e1e2e"), stop(1, "#161624")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#cba6f7"), patternSecondary: hex("#cdd6f4"),
            vignette: Vignette(color: hex("#0d0d16"), strength: 0.24),
            edge: Edge(hairlineColor: hex("#cba6f7"), hairlineOpacity: 0.20, hairlineWidth: 1,
                       glowColor: hex("#cba6f7"), glowOpacity: 0.06, glowWidth: 4, topSpecular: 0.08)
        ),
        "catppuccin-latte": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#f5f7fb"), stop(0.55, "#eff1f5"), stop(1, "#e4e7f0")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#8839ef"), patternSecondary: hex("#4c4f69"),
            vignette: Vignette(color: hex("#8c8fa1"), strength: 0.14),
            edge: Edge(hairlineColor: hex("#5c5f77"), hairlineOpacity: 0.28, hairlineWidth: 1, topSpecular: 0.35)
        ),
        "dracula": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#313344"), stop(0.55, "#282a36"), stop(1, "#1e1f29")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#bd93f9"), patternSecondary: hex("#f8f8f2"),
            vignette: Vignette(color: hex("#13141c"), strength: 0.26),
            edge: Edge(hairlineColor: hex("#bd93f9"), hairlineOpacity: 0.22, hairlineWidth: 1,
                       glowColor: hex("#bd93f9"), glowOpacity: 0.07, glowWidth: 4, topSpecular: 0.08)
        ),
        "nord": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#373f4e"), stop(0.55, "#2e3440"), stop(1, "#242933")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#88c0d0"), patternSecondary: hex("#d8dee9"),
            vignette: Vignette(color: hex("#191d24"), strength: 0.24),
            edge: Edge(hairlineColor: hex("#88c0d0"), hairlineOpacity: 0.22, hairlineWidth: 1,
                       glowColor: hex("#88c0d0"), glowOpacity: 0.06, glowWidth: 4, topSpecular: 0.09)
        ),
        "tokyo-night": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#232538"), stop(0.55, "#1a1b26"), stop(1, "#12131c")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#7aa2f7"), patternSecondary: hex("#c0caf5"),
            vignette: Vignette(color: hex("#0b0c12"), strength: 0.28),
            edge: Edge(hairlineColor: hex("#7aa2f7"), hairlineOpacity: 0.22, hairlineWidth: 1,
                       glowColor: hex("#7aa2f7"), glowOpacity: 0.07, glowWidth: 4, topSpecular: 0.08)
        ),
        "gruvbox-dark": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#33302d"), stop(0.55, "#282828"), stop(1, "#1d1c1b")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#fabd2f"), patternSecondary: hex("#ebdbb2"),
            vignette: Vignette(color: hex("#121110"), strength: 0.26),
            edge: Edge(hairlineColor: hex("#fabd2f"), hairlineOpacity: 0.18, hairlineWidth: 1, topSpecular: 0.08)
        ),
        "gruvbox-light": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#fdf5d3"), stop(0.55, "#fbf1c7"), stop(1, "#f0e1ae")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#d65d0e"), patternSecondary: hex("#3c3836"),
            vignette: Vignette(color: hex("#b5a375"), strength: 0.16),
            edge: Edge(hairlineColor: hex("#665c54"), hairlineOpacity: 0.28, hairlineWidth: 1, topSpecular: 0.30)
        ),
        "solarized-dark": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#053745"), stop(0.55, "#002b36"), stop(1, "#001f27")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#268bd2"), patternSecondary: hex("#93a1a1"),
            vignette: Vignette(color: hex("#00141a"), strength: 0.26),
            edge: Edge(hairlineColor: hex("#2aa198"), hairlineOpacity: 0.22, hairlineWidth: 1, topSpecular: 0.08)
        ),
        "solarized-light": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#fff9ea"), stop(0.55, "#fdf6e3"), stop(1, "#f3e9ce")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#268bd2"), patternSecondary: hex("#586e75"),
            vignette: Vignette(color: hex("#c2b89d"), strength: 0.16),
            edge: Edge(hairlineColor: hex("#657b83"), hairlineOpacity: 0.28, hairlineWidth: 1, topSpecular: 0.30)
        ),
        "rose-pine": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#242033"), stop(0.55, "#191724"), stop(1, "#12101b")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#ebbcba"), patternSecondary: hex("#e0def4"),
            vignette: Vignette(color: hex("#0b0912"), strength: 0.26),
            edge: Edge(hairlineColor: hex("#ebbcba"), hairlineOpacity: 0.22, hairlineWidth: 1,
                       glowColor: hex("#ebbcba"), glowOpacity: 0.06, glowWidth: 4, topSpecular: 0.08)
        ),
        "rose-pine-dawn": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#fdf8f3"), stop(0.55, "#faf4ed"), stop(1, "#efe5db")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#d7827e"), patternSecondary: hex("#575279"),
            vignette: Vignette(color: hex("#c4b2a8"), strength: 0.15),
            edge: Edge(hairlineColor: hex("#797593"), hairlineOpacity: 0.28, hairlineWidth: 1, topSpecular: 0.35)
        ),
        "one-dark": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#313640"), stop(0.55, "#282c34"), stop(1, "#1e2128")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#61afef"), patternSecondary: hex("#abb2bf"),
            vignette: Vignette(color: hex("#14171c"), strength: 0.24),
            edge: Edge(hairlineColor: hex("#61afef"), hairlineOpacity: 0.18, hairlineWidth: 1, topSpecular: 0.08)
        ),
        "monokai": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#31322b"), stop(0.55, "#272822"), stop(1, "#1d1e19")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#a6e22e"), patternSecondary: hex("#f8f8f2"),
            vignette: Vignette(color: hex("#121310"), strength: 0.24),
            edge: Edge(hairlineColor: hex("#a6e22e"), hairlineOpacity: 0.18, hairlineWidth: 1, topSpecular: 0.08)
        ),
        "kanagawa": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#292936"), stop(0.55, "#1f1f28"), stop(1, "#16161e")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#7e9cd8"), patternSecondary: hex("#dcd7ba"),
            vignette: Vignette(color: hex("#0e0e14"), strength: 0.26),
            edge: Edge(hairlineColor: hex("#7e9cd8"), hairlineOpacity: 0.20, hairlineWidth: 1, topSpecular: 0.08)
        ),
        "everforest-dark": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#364047"), stop(0.55, "#2d353b"), stop(1, "#22292e")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#a7c080"), patternSecondary: hex("#d3c6aa"),
            vignette: Vignette(color: hex("#171c20"), strength: 0.24),
            edge: Edge(hairlineColor: hex("#a7c080"), hairlineOpacity: 0.20, hairlineWidth: 1, topSpecular: 0.08)
        ),
        "github-dark": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#141b24"), stop(0.55, "#0d1117"), stop(1, "#080b10")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#2f81f7"), patternSecondary: hex("#e6edf3"),
            vignette: Vignette(color: hex("#040608"), strength: 0.22),
            edge: Edge(hairlineColor: hex("#58a6ff"), hairlineOpacity: 0.18, hairlineWidth: 1, topSpecular: 0.08)
        ),
        "github-light": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#ffffff"), stop(0.65, "#fafbfd"), stop(1, "#f1f4f9")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .none, patternTint: hex("#0969da"), patternSecondary: hex("#1f2328"),
            vignette: Vignette(color: hex("#b6c2cf"), strength: 0.12),
            edge: Edge(hairlineColor: hex("#57606a"), hairlineOpacity: 0.28, hairlineWidth: 1, topSpecular: 0.40)
        ),

        // MARK: Signature themes (distinct, atmospheric, legibility-first)
        "matrix": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#040c06"), stop(0.5, "#08170d"), stop(1, "#030a05")],
                          start: .top, end: .bottom),
            pattern: .matrix, patternTint: hex("#3bfa73"), patternSecondary: hex("#c4ffd6"),
            vignette: Vignette(color: hex("#010502"), strength: 0.48),
            edge: Edge(hairlineColor: hex("#48ed75"), hairlineOpacity: 0.36, hairlineWidth: 1,
                       glowColor: hex("#28d15c"), glowOpacity: 0.22, glowWidth: 6, topSpecular: 0.06)
        ),
        "stargate": ThemeBackdrop(
            base: .radial(stops: [stop(0, "#0f2c3f"), stop(0.55, "#091821"), stop(1, "#040b11")],
                          center: UnitPoint(x: 0.76, y: 0.72), startFraction: 0.02, endFraction: 0.95),
            pattern: .stargate, patternTint: hex("#69d4ff"), patternSecondary: hex("#ffb875"),
            vignette: Vignette(color: hex("#02060a"), strength: 0.46),
            edge: Edge(hairlineColor: hex("#69d4ff"), hairlineOpacity: 0.34, hairlineWidth: 1,
                       glowColor: hex("#38b6ff"), glowOpacity: 0.20, glowWidth: 6, topSpecular: 0.08)
        ),
        "storm": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#101524"), stop(0.45, "#1a2136"), stop(1, "#111626")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .storm, patternTint: hex("#b2b9ff"), patternSecondary: hex("#e4ecff"),
            vignette: Vignette(color: hex("#070912"), strength: 0.44),
            edge: Edge(hairlineColor: hex("#b2b9ff"), hairlineOpacity: 0.30, hairlineWidth: 1,
                       glowColor: hex("#7d8cff"), glowOpacity: 0.18, glowWidth: 5, topSpecular: 0.07)
        ),
        "transporter": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#130d21"), stop(0.5, "#1d1532"), stop(1, "#110b1f")],
                          start: .top, end: .bottom),
            pattern: .transporter, patternTint: hex("#f7aafd"), patternSecondary: hex("#ffe299"),
            vignette: Vignette(color: hex("#080412"), strength: 0.44),
            edge: Edge(hairlineColor: hex("#f7aafd"), hairlineOpacity: 0.34, hairlineWidth: 1,
                       glowColor: hex("#dc79ff"), glowOpacity: 0.22, glowWidth: 6, topSpecular: 0.08)
        ),
        "singularity": ThemeBackdrop(
            base: .radial(stops: [stop(0, "#241328"), stop(0.48, "#100b16"), stop(1, "#06030a")],
                          center: UnitPoint(x: 0.74, y: 0.68), startFraction: 0.05, endFraction: 0.92),
            pattern: .singularity, patternTint: hex("#ff946e"), patternSecondary: hex("#f472b6"),
            vignette: Vignette(color: hex("#030106"), strength: 0.50),
            edge: Edge(hairlineColor: hex("#ff946e"), hairlineOpacity: 0.30, hairlineWidth: 1,
                       glowColor: hex("#d95b80"), glowOpacity: 0.18, glowWidth: 5, topSpecular: 0.06)
        ),
        "phosphor": ThemeBackdrop(
            base: .radial(stops: [stop(0, "#291a0a"), stop(0.58, "#1b1106"), stop(1, "#0e0802")],
                          center: UnitPoint(x: 0.5, y: 0.48), startFraction: 0.05, endFraction: 0.95),
            pattern: .phosphor, patternTint: hex("#ffb454"), patternSecondary: hex("#ffe3b3"),
            vignette: Vignette(color: hex("#060300"), strength: 0.54),
            edge: Edge(hairlineColor: hex("#ffb454"), hairlineOpacity: 0.36, hairlineWidth: 1,
                       glowColor: hex("#ff9d2e"), glowOpacity: 0.22, glowWidth: 6, topSpecular: 0.06)
        ),
        "chalkboard": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#1f342d"), stop(0.55, "#192a25"), stop(1, "#12201c")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .chalkboard, patternTint: hex("#eef2de"), patternSecondary: hex("#d4c59e"),
            vignette: Vignette(color: hex("#09120f"), strength: 0.44),
            edge: Edge(hairlineColor: hex("#9ab09e"), hairlineOpacity: 0.26, hairlineWidth: 1,
                       glowColor: hex("#0a1410"), glowOpacity: 0.25, glowWidth: 4, topSpecular: 0.04)
        ),
        "ember-typewriter": ThemeBackdrop(
            base: .radial(stops: [stop(0, "#fff8e8"), stop(0.58, "#f7e5c4"), stop(1, "#dfbc87")],
                          center: UnitPoint(x: 0.42, y: 0.40), startFraction: 0.08, endFraction: 0.96),
            pattern: .parchment, patternTint: hex("#6e3c19"), patternSecondary: hex("#c94a1c"),
            vignette: Vignette(color: hex("#4a1e0a"), strength: 0.48),
            edge: Edge(hairlineColor: hex("#632b10"), hairlineOpacity: 0.42, hairlineWidth: 1,
                       glowColor: hex("#b83d14"), glowOpacity: 0.20, glowWidth: 6, topSpecular: 0.18)
        ),
        "field-notes": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#fdf6e4"), stop(0.6, "#faf0d7"), stop(1, "#f2e3bf")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .ruled, patternTint: hex("#5a87a6"), patternSecondary: hex("#c95a4e"),
            vignette: Vignette(color: hex("#bfa87a"), strength: 0.18),
            edge: Edge(hairlineColor: hex("#735c38"), hairlineOpacity: 0.32, hairlineWidth: 1, topSpecular: 0.28)
        ),
        "blueprint": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#123456"), stop(0.55, "#0e2640"), stop(1, "#08192c")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .blueprint, patternTint: hex("#79d8ff"), patternSecondary: hex("#c8f0ff"),
            vignette: Vignette(color: hex("#040f1c"), strength: 0.36),
            edge: Edge(hairlineColor: hex("#79d8ff"), hairlineOpacity: 0.38, hairlineWidth: 1,
                       glowColor: hex("#38b6ff"), glowOpacity: 0.16, glowWidth: 5, topSpecular: 0.08)
        ),
        "neon-district": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#160b21"), stop(0.52, "#23102d"), stop(1, "#12091b")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .neonDistrict, patternTint: hex("#ff73b8"), patternSecondary: hex("#70e8e1"),
            vignette: Vignette(color: hex("#08030e"), strength: 0.44),
            edge: Edge(hairlineColor: hex("#ff73b8"), hairlineOpacity: 0.38, hairlineWidth: 1,
                       glowColor: hex("#ff4da6"), glowOpacity: 0.22, glowWidth: 6, topSpecular: 0.08)
        ),
        "morning-edition": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#fbfaf4"), stop(0.6, "#f7f5ec"), stop(1, "#edeae0")],
                          start: .top, end: .bottom),
            pattern: .newsprint, patternTint: hex("#3b3a34"), patternSecondary: hex("#71402e"),
            vignette: Vignette(color: hex("#b5b0a0"), strength: 0.20),
            edge: Edge(hairlineColor: hex("#32302a"), hairlineOpacity: 0.30, hairlineWidth: 1, topSpecular: 0.25)
        ),
        "synthwave": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#110722"), stop(0.42, "#220f3c"), stop(0.68, "#3e1649"), stop(1, "#140826")],
                          start: .top, end: .bottom),
            pattern: .synthwave, patternTint: hex("#ff5e9c"), patternSecondary: hex("#4deeea"),
            vignette: Vignette(color: hex("#070212"), strength: 0.42),
            edge: Edge(hairlineColor: hex("#ff5e9c"), hairlineOpacity: 0.38, hairlineWidth: 1,
                       glowColor: hex("#ff3d8a"), glowOpacity: 0.22, glowWidth: 6, topSpecular: 0.08)
        ),
        "aurora": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#040d14"), stop(0.5, "#071822"), stop(1, "#051118")],
                          start: .top, end: .bottom),
            pattern: .aurora, patternTint: hex("#4ef2b8"), patternSecondary: hex("#9b72ff"),
            vignette: Vignette(color: hex("#02070c"), strength: 0.44),
            edge: Edge(hairlineColor: hex("#4ef2b8"), hairlineOpacity: 0.34, hairlineWidth: 1,
                       glowColor: hex("#28d49c"), glowOpacity: 0.20, glowWidth: 6, topSpecular: 0.08)
        ),
        "deep-sea": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#0c2840"), stop(0.48, "#061728"), stop(1, "#030c17")],
                          start: .top, end: .bottom),
            pattern: .deepSea, patternTint: hex("#38e2ff"), patternSecondary: hex("#7ef9d6"),
            vignette: Vignette(color: hex("#01060d"), strength: 0.46),
            edge: Edge(hairlineColor: hex("#38e2ff"), hairlineOpacity: 0.34, hairlineWidth: 1,
                       glowColor: hex("#1cb5e0"), glowOpacity: 0.18, glowWidth: 5, topSpecular: 0.09)
        ),
        "liquid-glass": ThemeBackdrop(
            base: .linear(stops: [stop(0, "#f8fbff"), stop(0.48, "#ecf3fb"), stop(1, "#e2ebf8")],
                          start: .topLeading, end: .bottomTrailing),
            pattern: .liquidGlass, patternTint: hex("#7cc4ff"), patternSecondary: hex("#b8a6ff"),
            vignette: Vignette(color: hex("#8aa4c2"), strength: 0.16),
            edge: Edge(hairlineColor: hex("#385370"), hairlineOpacity: 0.28, hairlineWidth: 1,
                       glowColor: hex("#ffffff"), glowOpacity: 0.70, glowWidth: 3, topSpecular: 0.62)
        ),
    ]
}

// MARK: - Renderer

/// Build check hook: fixes the backdrop animation clock to a chosen second so motion can be
/// compared across two deterministic screenshots.
private let debugBackdropTime: Double? = {
    guard notchPadDebug, let raw = ProcessInfo.processInfo.environment["NOTCHPAD_DEBUG_BACKDROP_TIME"] else { return nil }
    return Double(raw)
}()

struct ThemeBackdropView<S: Shape>: View {
    let theme: PadThemeSpec
    let shape: S
    let isOpen: Bool
    let allowMotion: Bool
    let topInset: CGFloat
    let isMini: Bool

    init(theme: PadThemeSpec, shape: S, isOpen: Bool, allowMotion: Bool,
         topInset: CGFloat = 0, isMini: Bool = false) {
        self.theme = theme
        self.shape = shape
        self.isOpen = isOpen
        self.allowMotion = allowMotion
        self.topInset = topInset
        self.isMini = isMini
    }

    private var spec: ThemeBackdrop { theme.backdrop }

    private var shouldAnimate: Bool {
        isOpen && allowMotion && !reduceMotionOn && !testNoEffects && !isMini && spec.hasMotion
    }

    var body: some View {
        ZStack {
            baseLayer
            if spec.pattern != .none {
                patternLayer
            }
            if spec.vignette.strength > 0.001 {
                vignetteLayer
            }
            edgeLayer
        }
        .clipShape(shape)
    }

    @ViewBuilder
    private var baseLayer: some View {
        switch spec.base {
        case .linear(let stops, let start, let end):
            LinearGradient(
                gradient: Gradient(stops: stops.map { Gradient.Stop(color: Color(nsColor: $0.color), location: $0.location) }),
                startPoint: start,
                endPoint: end
            )
        case .radial(let stops, let center, let startF, let endF):
            GeometryReader { geo in
                let dim = max(geo.size.width, geo.size.height)
                RadialGradient(
                    gradient: Gradient(stops: stops.map { Gradient.Stop(color: Color(nsColor: $0.color), location: $0.location) }),
                    center: center,
                    startRadius: dim * startF,
                    endRadius: dim * endF
                )
            }
        }
    }

    @ViewBuilder
    private var patternLayer: some View {
        if let fixed = debugBackdropTime {
            Canvas { ctx, size in
                ThemeBackdropCanvas.draw(spec: spec, in: &ctx, size: size, time: fixed, topInset: topInset, isMini: isMini)
            }
            .allowsHitTesting(false)
        } else if shouldAnimate {
            TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !isOpen)) { timeline in
                let t: Double = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    ThemeBackdropCanvas.draw(spec: spec, in: &ctx, size: size, time: t, topInset: topInset, isMini: isMini)
                }
            }
            .allowsHitTesting(false)
        } else {
            Canvas { ctx, size in
                ThemeBackdropCanvas.draw(spec: spec, in: &ctx, size: size, time: 0, topInset: topInset, isMini: isMini)
            }
            .allowsHitTesting(false)
        }
    }

    private var vignetteLayer: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            let radius: CGFloat = max(w, h) * 0.78
            let c = Color(nsColor: spec.vignette.color)
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: c.opacity(0), location: 0.42),
                    .init(color: c.opacity(spec.vignette.strength * 0.45), location: 0.76),
                    .init(color: c.opacity(spec.vignette.strength), location: 1.0)
                ]),
                center: .center,
                startRadius: 0,
                endRadius: radius
            )
        }
        .allowsHitTesting(false)
    }

    private var edgeLayer: some View {
        ZStack {
            if let glow = spec.edge.glowColor, spec.edge.glowOpacity > 0.001 {
                // Double width clipped to shape yields a clean inner-only rim glow.
                let gw: CGFloat = isMini ? max(2, spec.edge.glowWidth * 0.65) : spec.edge.glowWidth
                shape
                    .stroke(Color(nsColor: glow).opacity(spec.edge.glowOpacity), lineWidth: gw * 2)
                    .blur(radius: isMini ? 1.5 : 3.5)
            }
            if spec.edge.topSpecular > 0.001 {
                LinearGradient(
                    colors: [Color.white.opacity(spec.edge.topSpecular), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: isMini ? 0.25 : 0.14)
                )
            }
            shape
                .stroke(Color(nsColor: spec.edge.hairlineColor).opacity(spec.edge.hairlineOpacity),
                        lineWidth: spec.edge.hairlineWidth * 2)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Canvas pattern painters

private enum ThemeBackdropCanvas {
    /// Deterministic pseudo-random in [0, 1).
    private static func hash01(_ n: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n &* 374761393 &+ 668265263))
        x = (x ^ (x >> 13)) &* 1274126177
        x = x ^ (x >> 16)
        return Double(x & 0xFFFF) / 65536.0
    }

    static func draw(spec: ThemeBackdrop, in ctx: inout GraphicsContext, size: CGSize,
                     time: Double, topInset: CGFloat, isMini: Bool) {
        guard size.width > 4, size.height > 4 else { return }
        switch spec.pattern {
        case .none: break
        case .matrix: drawMatrix(spec: spec, in: &ctx, size: size, time: time, isMini: isMini)
        case .stargate: drawStargate(spec: spec, in: &ctx, size: size, time: time, isMini: isMini)
        case .storm: drawStorm(spec: spec, in: &ctx, size: size, time: time, isMini: isMini)
        case .transporter: drawTransporter(spec: spec, in: &ctx, size: size, time: time, isMini: isMini)
        case .singularity: drawSingularity(spec: spec, in: &ctx, size: size, time: time, isMini: isMini)
        case .phosphor: drawPhosphor(spec: spec, in: &ctx, size: size, time: time, isMini: isMini)
        case .chalkboard: drawChalkboard(spec: spec, in: &ctx, size: size, isMini: isMini)
        case .parchment: drawParchment(spec: spec, in: &ctx, size: size, isMini: isMini)
        case .ruled: drawRuled(spec: spec, in: &ctx, size: size, topInset: topInset, isMini: isMini)
        case .blueprint: drawBlueprint(spec: spec, in: &ctx, size: size, topInset: topInset, isMini: isMini)
        case .neonDistrict: drawNeonDistrict(spec: spec, in: &ctx, size: size, time: time, isMini: isMini)
        case .newsprint: drawNewsprint(spec: spec, in: &ctx, size: size, topInset: topInset, isMini: isMini)
        case .synthwave: drawSynthwave(spec: spec, in: &ctx, size: size, time: time, isMini: isMini)
        case .aurora: drawAurora(spec: spec, in: &ctx, size: size, time: time, isMini: isMini)
        case .deepSea: drawDeepSea(spec: spec, in: &ctx, size: size, time: time, isMini: isMini)
        case .liquidGlass: drawLiquidGlass(spec: spec, in: &ctx, size: size, isMini: isMini)
        }
    }

    private static let matrixGlyphs: [String] = [
        "0", "1", "ｱ", "ｶ", "ｻ", "ﾀ", "ﾅ", "ﾊ", "ﾏ", "ﾔ", "ﾗ", "ﾜ", "7", "9", "Z", "ｷ"
    ]

    // 1. Matrix: dim falling vertical code columns, softer behind the centre text area.
    private static func drawMatrix(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                   size: CGSize, time: Double, isMini: Bool) {
        let tint = Color(nsColor: spec.patternTint)
        let head = Color(nsColor: spec.patternSecondary)
        let cols: Int = isMini ? 14 : 30
        let colW: Double = Double(size.width) / Double(cols)
        let cellH: Double = isMini ? 5.0 : 10.5
        let rows: Int = Int(Double(size.height) / cellH) + 2
        let fontSize: CGFloat = isMini ? 5.0 : 9.0

        for c in 0..<cols {
            let xFrac: Double = (Double(c) + 0.5) / Double(cols)
            // Slightly brighter near edges, quieter behind the central reading zone.
            let edgeBoost: Double = 0.50 + 0.50 * abs(xFrac - 0.5) * 2.0
            let speed: Double = 1.8 + hash01(c * 17 + 3) * 2.6
            let trailLen: Int = isMini ? 4 : (8 + Int(hash01(c * 13 + 5) * 8.0))
            let cycle: Double = Double(rows + trailLen + 3)
            let phase: Double = hash01(c * 31 + 7) * cycle
            let headRow: Double = (phase + time * speed).truncatingRemainder(dividingBy: cycle)
            let x: Double = (Double(c) + 0.5) * colW

            for step in 0..<trailLen {
                let row: Int = Int(headRow) - step
                if row < -1 || row > rows { continue }
                let y: Double = (Double(row) + 0.5) * cellH
                let fade: Double = 1.0 - Double(step) / Double(trailLen)
                let alpha: Double = (step == 0 ? 0.34 : (0.04 + 0.16 * fade * fade)) * edgeBoost
                let glyphSeed: Int = c * 97 + row * 13 + Int(time * 1.5) / 2
                let idx: Int = Int(hash01(glyphSeed) * Double(matrixGlyphs.count)) % matrixGlyphs.count
                let col = (step == 0 ? head : tint).opacity(alpha)
                if isMini {
                    let rect = CGRect(x: x - 1.4, y: y - 1.6, width: 2.8, height: 3.2)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 0.7), with: .color(col))
                } else {
                    let label = Text(matrixGlyphs[idx])
                        .font(.system(size: fontSize, weight: step == 0 ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(col)
                    ctx.draw(label, at: CGPoint(x: x, y: y))
                }
            }
        }
    }

    // 2. Stargate: twinkling starfield + glowing blue event-horizon ripple & amber chevron arc.
    private static func drawStargate(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                     size: CGSize, time: Double, isMini: Bool) {
        let cyan = Color(nsColor: spec.patternTint)
        let amber = Color(nsColor: spec.patternSecondary)
        let w = Double(size.width)
        let h = Double(size.height)

        // Pinprick starfield
        let starCount: Int = isMini ? 16 : 44
        for i in 0..<starCount {
            let sx: Double = hash01(i * 23 + 11) * w
            let sy: Double = hash01(i * 41 + 19) * h
            let r: Double = (isMini ? 0.5 : 0.7) + hash01(i * 7 + 3) * (isMini ? 0.6 : 1.1)
            let tw: Double = 0.55 + 0.45 * sin(time * (1.2 + hash01(i * 5) * 1.6) + Double(i) * 1.7)
            let alpha: Double = (0.14 + 0.24 * hash01(i * 13)) * tw
            let dot = Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2))
            ctx.fill(dot, with: .color(Color.white.opacity(alpha)))
        }

        // Event horizon off to the lower-right so text stays crisp
        let cx: Double = w * 0.78
        let cy: Double = h * 0.74
        let gateR: Double = min(w, h) * (isMini ? 0.44 : 0.48)
        let pulse: Double = 1.0 + 0.04 * sin(time * 1.3)

        // Soft glowing blue puddle
        let poolRect = CGRect(x: cx - gateR * pulse, y: cy - gateR * pulse, width: gateR * 2 * pulse, height: gateR * 2 * pulse)
        let poolGrad = Gradient(stops: [
            .init(color: cyan.opacity(0.24), location: 0.0),
            .init(color: cyan.opacity(0.11), location: 0.55),
            .init(color: cyan.opacity(0.0), location: 1.0)
        ])
        ctx.fill(Path(ellipseIn: poolRect),
                 with: .radialGradient(poolGrad, center: CGPoint(x: cx, y: cy), startRadius: 2, endRadius: gateR * pulse))

        // Concentric kawoosh / water ripples
        for rIdx in 1...3 {
            let phase: Double = (time * 0.16 + Double(rIdx) / 3.0).truncatingRemainder(dividingBy: 1.0)
            let rr: Double = gateR * (0.22 + 0.72 * phase)
            let alpha: Double = (1.0 - phase) * 0.18
            let ring = Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2))
            ctx.stroke(ring, with: .color(cyan.opacity(alpha)), lineWidth: isMini ? 0.8 : 1.2)
        }

        // Outer metallic ring & glowing amber chevrons
        let outerR: Double = gateR * 0.96
        let outerRing = Path(ellipseIn: CGRect(x: cx - outerR, y: cy - outerR, width: outerR * 2, height: outerR * 2))
        ctx.stroke(outerRing, with: .color(cyan.opacity(0.24)), lineWidth: isMini ? 1.5 : 3.0)

        for k in 0..<7 {
            let angle: Double = Double(k) * (Double.pi * 2.0 / 7.0) - Double.pi * 0.5
            let px: Double = cx + cos(angle) * outerR
            let py: Double = cy + sin(angle) * outerR
            let haloR: Double = isMini ? 3.5 : 7.0
            let hg = Gradient(stops: [.init(color: amber.opacity(0.32), location: 0), .init(color: amber.opacity(0), location: 1)])
            ctx.fill(Path(ellipseIn: CGRect(x: px - haloR, y: py - haloR, width: haloR * 2, height: haloR * 2)),
                     with: .radialGradient(hg, center: CGPoint(x: px, y: py), startRadius: 0.5, endRadius: haloR))
            let chevSize: Double = isMini ? 2.4 : 4.2
            let chev = Path(ellipseIn: CGRect(x: px - chevSize * 0.5, y: py - chevSize * 0.5, width: chevSize, height: chevSize))
            ctx.fill(chev, with: .color(amber.opacity(0.72)))
        }
    }

    // 3. Storm: dramatic layered thunderhead clouds, slanted rain, subtle distant lightning.
    private static func drawStorm(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                  size: CGSize, time: Double, isMini: Bool) {
        let tint = Color(nsColor: spec.patternTint)
        let flashColor = Color(nsColor: spec.patternSecondary)
        let darkCloud = Color(nsColor: NSColor(hex: "#060913")!)
        let w = Double(size.width)
        let h = Double(size.height)

        // Moody thunderhead bank: dark brooding undersides + silver-lit upper billow rims
        let puffs: Int = isMini ? 6 : 11
        for i in 0..<puffs {
            let drift: Double = (time * (2.6 + hash01(i * 11) * 3.5)).truncatingRemainder(dividingBy: w + 200)
            let baseX: Double = (hash01(i * 19 + 3) * (w + 200) + drift).truncatingRemainder(dividingBy: w + 200) - 100
            let isTop: Bool = (i % 3 != 2)
            let baseY: Double = isTop ? (h * (0.04 + hash01(i * 7) * 0.24)) : (h * (0.76 + hash01(i * 9) * 0.20))
            let r: Double = min(w, h) * (0.28 + hash01(i * 29) * 0.24)
            let isDarkUnder: Bool = (i % 2 == 1)
            let cloudGrad = Gradient(stops: [
                .init(color: (isDarkUnder ? darkCloud : tint).opacity(isDarkUnder ? 0.36 : 0.16), location: 0.0),
                .init(color: (isDarkUnder ? darkCloud : tint).opacity(isDarkUnder ? 0.15 : 0.06), location: 0.55),
                .init(color: (isDarkUnder ? darkCloud : tint).opacity(0.0), location: 1.0)
            ])
            var g = ctx
            g.translateBy(x: baseX, y: baseY)
            g.scaleBy(x: 1.85, y: 0.68)
            g.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                   with: .radialGradient(cloudGrad, center: .zero, startRadius: 1, endRadius: r))
        }

        // Slanted rain streaks
        let drops: Int = isMini ? 10 : 28
        for i in 0..<drops {
            let rx: Double = hash01(i * 37 + 5) * w
            let speed: Double = 36.0 + hash01(i * 13) * 28.0
            let ry: Double = (hash01(i * 23 + 2) * h + time * speed).truncatingRemainder(dividingBy: h + 24) - 12
            let len: Double = (isMini ? 7.0 : 14.0) + hash01(i * 7) * (isMini ? 4.0 : 10.0)
            var p = Path()
            p.move(to: CGPoint(x: rx, y: ry))
            p.addLine(to: CGPoint(x: rx - len * 0.28, y: ry + len))
            ctx.stroke(p, with: .color(tint.opacity(0.11 + hash01(i * 17) * 0.05)), lineWidth: 0.85)
        }

        // Distant right-side cloud illumination + delicate forked filament (subtle ambient + brighter flicker)
        let cycle: Double = time.truncatingRemainder(dividingBy: 6.5)
        let flickerBoost: Double
        if cycle > 0.2 && cycle < 0.42 {
            flickerBoost = sin((cycle - 0.2) / 0.22 * Double.pi) * 0.26
        } else if cycle > 0.50 && cycle < 0.64 {
            flickerBoost = sin((cycle - 0.50) / 0.14 * Double.pi) * 0.16
        } else {
            flickerBoost = 0
        }
        let fx: Double = w * 0.84
        let fy: Double = h * 0.24
        let fr: Double = min(w, h) * 0.52
        let glowAlpha: Double = 0.12 + flickerBoost
        let fg = Gradient(stops: [
            .init(color: flashColor.opacity(glowAlpha), location: 0.0),
            .init(color: tint.opacity(glowAlpha * 0.45), location: 0.5),
            .init(color: tint.opacity(0.0), location: 1.0)
        ])
        ctx.fill(Path(ellipseIn: CGRect(x: fx - fr, y: fy - fr, width: fr * 2, height: fr * 2)),
                 with: .radialGradient(fg, center: CGPoint(x: fx, y: fy), startRadius: 2, endRadius: fr))

        // Delicate distant jagged bolt in the upper-right margin (keeps well clear of left-aligned text)
        var bolt = Path()
        bolt.move(to: CGPoint(x: w * 0.87, y: h * 0.06))
        bolt.addLine(to: CGPoint(x: w * 0.84, y: h * 0.17))
        bolt.addLine(to: CGPoint(x: w * 0.88, y: h * 0.23))
        bolt.addLine(to: CGPoint(x: w * 0.83, y: h * 0.36))
        bolt.addLine(to: CGPoint(x: w * 0.85, y: h * 0.44))
        var branch = Path()
        branch.move(to: CGPoint(x: w * 0.88, y: h * 0.23))
        branch.addLine(to: CGPoint(x: w * 0.92, y: h * 0.31))
        let boltAlpha: Double = 0.16 + flickerBoost * 1.15
        ctx.stroke(bolt, with: .color(flashColor.opacity(boltAlpha)), lineWidth: isMini ? 0.9 : 1.2)
        ctx.stroke(branch, with: .color(tint.opacity(boltAlpha * 0.7)), lineWidth: isMini ? 0.6 : 0.85)
    }

    // 4. Transporter: vertical shimmering energy columns + rising sparkling matter motes.
    private static func drawTransporter(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                        size: CGSize, time: Double, isMini: Bool) {
        let lilac = Color(nsColor: spec.patternTint)
        let gold = Color(nsColor: spec.patternSecondary)
        let w = Double(size.width)
        let h = Double(size.height)

        // Subtle vertical beam columns (stronger at edges)
        let beamXs: [Double] = [0.10, 0.24, 0.76, 0.90]
        for (idx, frac) in beamXs.enumerated() {
            let bx: Double = w * frac
            let bw: Double = w * (isMini ? 0.08 : 0.06)
            let shimmer: Double = 0.05 + 0.035 * sin(time * 1.7 + Double(idx) * 1.4)
            let grad = Gradient(stops: [
                .init(color: lilac.opacity(0), location: 0),
                .init(color: lilac.opacity(shimmer), location: 0.5),
                .init(color: lilac.opacity(0), location: 1)
            ])
            let rect = CGRect(x: bx - bw, y: 0, width: bw * 2, height: h)
            ctx.fill(Path(rect), with: .linearGradient(grad, startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
        }

        // Rising matter-stream sparkles
        let count: Int = isMini ? 16 : 38
        for i in 0..<count {
            let xFrac: Double = hash01(i * 29 + 7)
            let edgeFactor: Double = 0.45 + 0.55 * abs(xFrac - 0.5) * 2.0
            let sx: Double = xFrac * w
            let speed: Double = 8.0 + hash01(i * 17 + 3) * 14.0
            let sy: Double = h - ((hash01(i * 43 + 11) * h + time * speed).truncatingRemainder(dividingBy: h + 16)) + 8
            let tw: Double = 0.45 + 0.55 * sin(time * (2.2 + hash01(i * 5) * 2.0) + Double(i))
            let alpha: Double = (0.16 + 0.28 * hash01(i * 19)) * tw * edgeFactor
            let isGold: Bool = (i % 4 == 0)
            let col = (isGold ? gold : lilac).opacity(alpha)
            let s: Double = (isMini ? 1.2 : 2.0) + hash01(i * 11) * (isMini ? 1.0 : 1.8)
            var diamond = Path()
            diamond.move(to: CGPoint(x: sx, y: sy - s * 1.4))
            diamond.addLine(to: CGPoint(x: sx + s * 0.7, y: sy))
            diamond.addLine(to: CGPoint(x: sx, y: sy + s * 1.4))
            diamond.addLine(to: CGPoint(x: sx - s * 0.7, y: sy))
            diamond.closeSubpath()
            ctx.fill(diamond, with: .color(col))
        }
    }

    // 5. Singularity: dark gravitational swirl of dust arcs around a warm amber-rose accretion core.
    private static func drawSingularity(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                        size: CGSize, time: Double, isMini: Bool) {
        let amber = Color(nsColor: spec.patternTint)
        let rose = Color(nsColor: spec.patternSecondary)
        let w = Double(size.width)
        let h = Double(size.height)
        let cx: Double = w * 0.75
        let cy: Double = h * 0.68
        let coreR: Double = min(w, h) * (isMini ? 0.14 : 0.13)

        // Warm accretion glow halo
        let haloR: Double = coreR * 4.2
        let halo = Gradient(stops: [
            .init(color: amber.opacity(0.24), location: 0.18),
            .init(color: rose.opacity(0.11), location: 0.50),
            .init(color: rose.opacity(0.0), location: 1.0)
        ])
        ctx.fill(Path(ellipseIn: CGRect(x: cx - haloR, y: cy - haloR, width: haloR * 2, height: haloR * 2)),
                 with: .radialGradient(halo, center: CGPoint(x: cx, y: cy), startRadius: coreR * 0.6, endRadius: haloR))

        // Tilted orbiting dust arcs
        var g = ctx
        g.translateBy(x: cx, y: cy)
        g.rotate(by: .degrees(-18))
        let rings: Int = isMini ? 6 : 12
        for i in 0..<rings {
            let f: Double = Double(i + 1) / Double(rings)
            let rx: Double = coreR * (1.25 + f * 3.1)
            let ry: Double = rx * 0.36
            let startDeg: Double = hash01(i * 19 + 5) * 360.0 + time * (16.0 - f * 9.0)
            let spanDeg: Double = 70.0 + hash01(i * 31) * 110.0
            let steps: Int = 14
            var arc = Path()
            for s in 0...steps {
                let deg: Double = startDeg + spanDeg * Double(s) / Double(steps)
                let rad: Double = deg * Double.pi / 180.0
                let pt = CGPoint(x: cos(rad) * rx, y: sin(rad) * ry)
                if s == 0 { arc.move(to: pt) } else { arc.addLine(to: pt) }
            }
            let alpha: Double = (0.28 - f * 0.18)
            let col = (i % 2 == 0 ? amber : rose).opacity(max(0.05, alpha))
            g.stroke(arc, with: .color(col), lineWidth: isMini ? 0.9 : 1.3)
        }

        // Dark event horizon shadow core + bright photon ring
        let coreRect = CGRect(x: cx - coreR, y: cy - coreR, width: coreR * 2, height: coreR * 2)
        ctx.fill(Path(ellipseIn: coreRect), with: .color(Color(nsColor: NSColor(hex: "#06030a")!).opacity(0.88)))
        ctx.stroke(Path(ellipseIn: coreRect), with: .color(amber.opacity(0.42)), lineWidth: isMini ? 1.0 : 1.6)
    }

    // 6. Phosphor: authentic amber CRT scan lines + slow refresh band + curved-glass reflection.
    private static func drawPhosphor(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                     size: CGSize, time: Double, isMini: Bool) {
        let amber = Color(nsColor: spec.patternTint)
        let cream = Color(nsColor: spec.patternSecondary)
        let w = Double(size.width)
        let h = Double(size.height)

        // Crisp horizontal CRT scan lines
        let step: Double = isMini ? 2.5 : 3.0
        var lines = Path()
        var y: Double = 0
        while y < h {
            lines.addRect(CGRect(x: 0, y: y, width: w, height: 1.0))
            y += step
        }
        ctx.fill(lines, with: .color(Color.black.opacity(isMini ? 0.22 : 0.24)))

        // Slow drifting phosphor refresh band
        let bandY: Double = (time * 18.0).truncatingRemainder(dividingBy: h + 60) - 30
        let bandH: Double = isMini ? 14 : 36
        let bandRect = CGRect(x: 0, y: bandY, width: w, height: bandH)
        let bandGrad = Gradient(stops: [
            .init(color: amber.opacity(0), location: 0),
            .init(color: amber.opacity(0.055), location: 0.5),
            .init(color: amber.opacity(0), location: 1)
        ])
        ctx.fill(Path(bandRect), with: .linearGradient(bandGrad, startPoint: CGPoint(x: 0, y: bandRect.minY), endPoint: CGPoint(x: 0, y: bandRect.maxY)))

        // Subtle curved CRT glass reflection along the upper-left (scaled circle for seamless falloff)
        var glassCtx = ctx
        glassCtx.translateBy(x: w * 0.35, y: -h * 0.12)
        glassCtx.scaleBy(x: 1.65, y: 0.75)
        let gr: Double = min(w, h) * 0.72
        let glassGrad = Gradient(stops: [
            .init(color: cream.opacity(0.065), location: 0.0),
            .init(color: cream.opacity(0.02), location: 0.55),
            .init(color: cream.opacity(0.0), location: 1.0)
        ])
        glassCtx.fill(Path(ellipseIn: CGRect(x: -gr, y: -gr, width: gr * 2, height: gr * 2)),
                      with: .radialGradient(glassGrad, center: .zero, startRadius: 2, endRadius: gr))
    }

    // 7. Chalkboard: seamless erased chalk smudges, fine chalk dust speckles, faint tray line.
    private static func drawChalkboard(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                       size: CGSize, isMini: Bool) {
        let chalk = Color(nsColor: spec.patternTint)
        let tray = Color(nsColor: spec.patternSecondary)
        let w = Double(size.width)
        let h = Double(size.height)

        // Seamless soft erased chalk clouds (circle scaled in context so alpha reaches 0 before edge)
        let smudges: Int = isMini ? 4 : 9
        for i in 0..<smudges {
            let sx: Double = (0.14 + hash01(i * 23 + 7) * 0.72) * w
            let sy: Double = (0.18 + hash01(i * 37 + 11) * 0.64) * h
            let r: Double = min(w, h) * (0.20 + hash01(i * 13) * 0.20)
            let alpha: Double = 0.032 + hash01(i * 5) * 0.030
            let g = Gradient(stops: [
                .init(color: chalk.opacity(alpha), location: 0.0),
                .init(color: chalk.opacity(alpha * 0.35), location: 0.55),
                .init(color: chalk.opacity(0.0), location: 1.0)
            ])
            var sc = ctx
            sc.translateBy(x: sx, y: sy)
            sc.rotate(by: .degrees((hash01(i * 19) - 0.5) * 28.0))
            sc.scaleBy(x: 1.85, y: 0.78)
            sc.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                    with: .radialGradient(g, center: .zero, startRadius: 1, endRadius: r))
        }

        // Fine chalk dust grains (slightly denser near bottom)
        let specks: Int = isMini ? 24 : 95
        for i in 0..<specks {
            let sx: Double = hash01(i * 41 + 3) * w
            let rawY: Double = hash01(i * 53 + 9)
            let sy: Double = pow(rawY, 0.78) * h
            let r: Double = 0.5 + hash01(i * 19) * 0.9
            let alpha: Double = 0.05 + hash01(i * 29) * 0.09
            ctx.fill(Path(ellipseIn: CGRect(x: sx, y: sy, width: r * 2, height: r * 2)),
                     with: .color(chalk.opacity(alpha)))
        }

        // Faint dusty chalk-tray line near the bottom
        let trayY: Double = h - (isMini ? 4 : 9)
        var trayLine = Path()
        trayLine.move(to: CGPoint(x: w * 0.08, y: trayY))
        trayLine.addLine(to: CGPoint(x: w * 0.92, y: trayY))
        ctx.stroke(trayLine, with: .color(tray.opacity(0.18)), lineWidth: isMini ? 1.0 : 1.5)
    }

    // 8. Parchment (Ember Typewriter): laid-paper texture, fibres, foxing, scorched corners & ember glow.
    private static func drawParchment(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                      size: CGSize, isMini: Bool) {
        let fibre = Color(nsColor: spec.patternTint)
        let ember = Color(nsColor: spec.patternSecondary)
        let charColor = Color(nsColor: NSColor(hex: "#3d1808")!)
        let w = Double(size.width)
        let h = Double(size.height)

        // Subtle horizontal laid-paper ribs (visible warm texture even at 1x)
        if !isMini {
            var ribs = Path()
            var ry: Double = 4
            while ry < h {
                ribs.move(to: CGPoint(x: 0, y: ry))
                ribs.addLine(to: CGPoint(x: w, y: ry))
                ry += 5.0
            }
            ctx.stroke(ribs, with: .color(fibre.opacity(0.036)), lineWidth: 0.8)
        }

        // Organic paper fibres & vintage foxing spots
        let count: Int = isMini ? 24 : 84
        for i in 0..<count {
            let x: Double = hash01(i * 31 + 7) * w
            let y: Double = hash01(i * 47 + 13) * h
            let angle: Double = hash01(i * 17) * Double.pi
            let len: Double = (isMini ? 3.5 : 6.0) + hash01(i * 23) * (isMini ? 4.0 : 10.0)
            var p = Path()
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + cos(angle) * len, y: y + sin(angle) * len))
            ctx.stroke(p, with: .color(fibre.opacity(0.08 + hash01(i * 11) * 0.08)), lineWidth: 0.9)
        }
        let specks: Int = isMini ? 14 : 46
        for i in 0..<specks {
            let sx: Double = hash01(i * 59 + 3) * w
            let sy: Double = hash01(i * 71 + 9) * h
            let r: Double = 0.7 + hash01(i * 13) * 1.4
            ctx.fill(Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)),
                     with: .color(fibre.opacity(0.06 + hash01(i * 29) * 0.07)))
        }

        // Scorched / toasted parchment corners (deep burnt umber + warm ember rim in bottom-right)
        let scorchCorners: [(Double, Double, Double, Color, Double)] = [
            (0.95, 0.94, 0.56, charColor, 0.28),
            (0.90, 0.92, 0.44, ember, 0.22),
            (0.04, 0.96, 0.40, charColor, 0.18),
            (0.96, 0.06, 0.36, charColor, 0.16)
        ]
        for (fx, fy, fracR, col, alpha) in scorchCorners {
            let cx: Double = w * fx
            let cy: Double = h * fy
            let cr: Double = min(w, h) * fracR
            let sg = Gradient(stops: [
                .init(color: col.opacity(alpha), location: 0.0),
                .init(color: col.opacity(alpha * 0.4), location: 0.48),
                .init(color: col.opacity(0.0), location: 1.0)
            ])
            ctx.fill(Path(ellipseIn: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2)),
                     with: .radialGradient(sg, center: CGPoint(x: cx, y: cy), startRadius: 1, endRadius: cr))
        }
    }

    // 9. Ruled (Field Notes): notebook blue-grey ruled lines + coral-red left margin + paper grain.
    private static func drawRuled(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                  size: CGSize, topInset: CGFloat, isMini: Bool) {
        let ruleColor = Color(nsColor: spec.patternTint)
        let marginColor = Color(nsColor: spec.patternSecondary)
        let w = Double(size.width)
        let h = Double(size.height)

        let spacing: Double = isMini ? 10.0 : 20.0
        let startY: Double = isMini ? 14.0 : (Double(topInset) + 21.0)
        var rules = Path()
        var y: Double = startY
        while y < h - (isMini ? 4 : 12) {
            rules.move(to: CGPoint(x: isMini ? 4 : 14, y: y))
            rules.addLine(to: CGPoint(x: w - (isMini ? 4 : 14), y: y))
            y += spacing
        }
        ctx.stroke(rules, with: .color(ruleColor.opacity(isMini ? 0.24 : 0.21)), lineWidth: isMini ? 0.6 : 0.85)

        // Vertical coral-red margin line
        let marginX: Double = isMini ? 13.0 : 28.0
        var margin = Path()
        margin.move(to: CGPoint(x: marginX, y: isMini ? 0 : Double(topInset)))
        margin.addLine(to: CGPoint(x: marginX, y: h))
        ctx.stroke(margin, with: .color(marginColor.opacity(isMini ? 0.36 : 0.33)), lineWidth: isMini ? 0.8 : 1.0)

        // Subtle warm paper grain flecks
        let specks: Int = isMini ? 12 : 42
        for i in 0..<specks {
            let sx: Double = hash01(i * 43 + 7) * w
            let sy: Double = hash01(i * 61 + 11) * h
            ctx.fill(Path(CGRect(x: sx, y: sy, width: 1.0, height: 1.0)),
                     with: .color(marginColor.opacity(0.04)))
        }
    }

    // 10. Blueprint: fine architectural minor grid + heavier major grid + technical inset frame.
    private static func drawBlueprint(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                      size: CGSize, topInset: CGFloat, isMini: Bool) {
        let cyan = Color(nsColor: spec.patternTint)
        let w = Double(size.width)
        let h = Double(size.height)
        let minor: Double = isMini ? 8.0 : 16.0
        let majorEvery: Int = 4

        var minorPath = Path()
        var majorPath = Path()
        var ix: Int = 1
        while Double(ix) * minor < w {
            let x: Double = Double(ix) * minor
            if ix % majorEvery == 0 {
                majorPath.move(to: CGPoint(x: x, y: 0))
                majorPath.addLine(to: CGPoint(x: x, y: h))
            } else {
                minorPath.move(to: CGPoint(x: x, y: 0))
                minorPath.addLine(to: CGPoint(x: x, y: h))
            }
            ix += 1
        }
        var iy: Int = 1
        while Double(iy) * minor < h {
            let y: Double = Double(iy) * minor
            if iy % majorEvery == 0 {
                majorPath.move(to: CGPoint(x: 0, y: y))
                majorPath.addLine(to: CGPoint(x: w, y: y))
            } else {
                minorPath.move(to: CGPoint(x: 0, y: y))
                minorPath.addLine(to: CGPoint(x: w, y: y))
            }
            iy += 1
        }
        ctx.stroke(minorPath, with: .color(cyan.opacity(isMini ? 0.10 : 0.08)), lineWidth: 0.6)
        ctx.stroke(majorPath, with: .color(cyan.opacity(isMini ? 0.22 : 0.18)), lineWidth: 0.9)

        // Technical corner registration ticks (full pad only)
        if !isMini {
            let insetX: Double = 18
            let topY: Double = Double(topInset) + 8
            let botY: Double = h - 14
            let tick: Double = 8
            var corners = Path()
            // Top-left
            corners.move(to: CGPoint(x: insetX, y: topY + tick))
            corners.addLine(to: CGPoint(x: insetX, y: topY))
            corners.addLine(to: CGPoint(x: insetX + tick, y: topY))
            // Top-right
            corners.move(to: CGPoint(x: w - insetX - tick, y: topY))
            corners.addLine(to: CGPoint(x: w - insetX, y: topY))
            corners.addLine(to: CGPoint(x: w - insetX, y: topY + tick))
            // Bottom-left
            corners.move(to: CGPoint(x: insetX, y: botY - tick))
            corners.addLine(to: CGPoint(x: insetX, y: botY))
            corners.addLine(to: CGPoint(x: insetX + tick, y: botY))
            ctx.stroke(corners, with: .color(cyan.opacity(0.32)), lineWidth: 1.0)
        }
    }

    // 11. Neon District: dual-tone magenta/cyan glow pools + low receding neon horizon grid.
    private static func drawNeonDistrict(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                         size: CGSize, time: Double, isMini: Bool) {
        let pink = Color(nsColor: spec.patternTint)
        let cyan = Color(nsColor: spec.patternSecondary)
        let w = Double(size.width)
        let h = Double(size.height)

        // Dual atmospheric neon pools in opposite corners
        let r1: Double = min(w, h) * 0.65
        let g1 = Gradient(stops: [.init(color: pink.opacity(0.14), location: 0), .init(color: pink.opacity(0), location: 1)])
        ctx.fill(Path(ellipseIn: CGRect(x: w * 0.85 - r1, y: h * 0.12 - r1, width: r1 * 2, height: r1 * 2)),
                 with: .radialGradient(g1, center: CGPoint(x: w * 0.85, y: h * 0.12), startRadius: 2, endRadius: r1))

        let g2 = Gradient(stops: [.init(color: cyan.opacity(0.12), location: 0), .init(color: cyan.opacity(0), location: 1)])
        ctx.fill(Path(ellipseIn: CGRect(x: w * 0.15 - r1, y: h * 0.90 - r1, width: r1 * 2, height: r1 * 2)),
                 with: .radialGradient(g2, center: CGPoint(x: w * 0.15, y: h * 0.90), startRadius: 2, endRadius: r1))

        // Low perspective horizon grid kept below the main note area so no bright line crosses text
        let horizonY: Double = h * (isMini ? 0.68 : 0.81)
        let floorH: Double = h - horizonY
        let hGrad = Gradient(stops: [
            .init(color: pink.opacity(isMini ? 0.34 : 0.24), location: 0.0),
            .init(color: pink.opacity(isMini ? 0.28 : 0.10), location: 0.45),
            .init(color: pink.opacity(isMini ? 0.34 : 0.26), location: 1.0)
        ])
        var horizon = Path()
        horizon.move(to: CGPoint(x: 0, y: horizonY))
        horizon.addLine(to: CGPoint(x: w, y: horizonY))
        ctx.stroke(horizon, with: .linearGradient(hGrad, startPoint: CGPoint(x: 0, y: horizonY), endPoint: CGPoint(x: w, y: horizonY)),
                   lineWidth: isMini ? 0.9 : 1.1)

        let vLines: Int = isMini ? 7 : 13
        var grid = Path()
        for i in 0..<vLines {
            let frac: Double = Double(i) / Double(vLines - 1) - 0.5
            let topX: Double = w * 0.5 + frac * w * 0.55
            let botX: Double = w * 0.5 + frac * w * 1.65
            grid.move(to: CGPoint(x: topX, y: horizonY))
            grid.addLine(to: CGPoint(x: botX, y: h))
        }
        let hLines: Int = isMini ? 4 : 5
        let scroll: Double = (time * 0.35).truncatingRemainder(dividingBy: 1.0)
        for j in 0..<hLines {
            let raw: Double = (Double(j) + scroll) / Double(hLines)
            let y: Double = horizonY + raw * raw * floorH
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: w, y: y))
        }
        let gridGrad = Gradient(stops: [
            .init(color: cyan.opacity(isMini ? 0.18 : 0.08), location: 0.0),
            .init(color: cyan.opacity(isMini ? 0.28 : 0.22), location: 1.0)
        ])
        ctx.stroke(grid, with: .linearGradient(gridGrad, startPoint: CGPoint(x: 0, y: horizonY), endPoint: CGPoint(x: 0, y: h)),
                   lineWidth: isMini ? 0.7 : 0.85)
    }

    // 12. Newsprint (Morning Edition): broadsheet masthead rules, subtle column rules & paper grain.
    private static func drawNewsprint(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                      size: CGSize, topInset: CGFloat, isMini: Bool) {
        let ink = Color(nsColor: spec.patternTint)
        let accent = Color(nsColor: spec.patternSecondary)
        let w = Double(size.width)
        let h = Double(size.height)

        // Fine newsprint paper grain
        let dots: Int = isMini ? 32 : 140
        for i in 0..<dots {
            let x: Double = hash01(i * 37 + 5) * w
            let y: Double = hash01(i * 53 + 11) * h
            let s: Double = 0.8 + hash01(i * 19) * 0.9
            ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)),
                     with: .color(ink.opacity(0.05 + hash01(i * 13) * 0.055)))
        }

        // Broadsheet double masthead rule below the toolbar
        let ruleY: Double = isMini ? 13.0 : (Double(topInset) + 3.0)
        let padX: Double = isMini ? 8.0 : 18.0
        var thick = Path()
        thick.move(to: CGPoint(x: padX, y: ruleY))
        thick.addLine(to: CGPoint(x: w - padX, y: ruleY))
        ctx.stroke(thick, with: .color(ink.opacity(0.36)), lineWidth: isMini ? 1.1 : 1.8)

        var thin = Path()
        thin.move(to: CGPoint(x: padX, y: ruleY + (isMini ? 2.4 : 3.6)))
        thin.addLine(to: CGPoint(x: w - padX, y: ruleY + (isMini ? 2.4 : 3.6)))
        ctx.stroke(thin, with: .color(accent.opacity(0.42)), lineWidth: isMini ? 0.6 : 0.8)

        // Subtle broadsheet column hairlines and bottom edition rule (full pad)
        if !isMini {
            let bodyTop: Double = ruleY + 10.0
            let footY: Double = h - 24.0
            var cols = Path()
            for frac in [0.34, 0.67] {
                let cx: Double = w * frac
                cols.move(to: CGPoint(x: cx, y: bodyTop))
                cols.addLine(to: CGPoint(x: cx, y: footY - 6.0))
            }
            ctx.stroke(cols, with: .color(ink.opacity(0.06)), lineWidth: 0.7)

            var foot = Path()
            foot.move(to: CGPoint(x: padX, y: footY))
            foot.addLine(to: CGPoint(x: w - padX, y: footY))
            ctx.stroke(foot, with: .color(ink.opacity(0.22)), lineWidth: 0.75)

            // Tiny editorial diamond ornaments at the masthead ends
            for ox in [padX + 2.5, w - padX - 2.5] {
                let oy: Double = ruleY + 1.8
                var d = Path()
                d.move(to: CGPoint(x: ox, y: oy - 2.2))
                d.addLine(to: CGPoint(x: ox + 2.2, y: oy))
                d.addLine(to: CGPoint(x: ox, y: oy + 2.2))
                d.addLine(to: CGPoint(x: ox - 2.2, y: oy))
                d.closeSubpath()
                ctx.fill(d, with: .color(accent.opacity(0.45)))
            }
        }
    }

    // 13. Synthwave: 80s twilight stars, banded sunset sun tucked lower-right, low scrolling laser grid.
    private static func drawSynthwave(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                      size: CGSize, time: Double, isMini: Bool) {
        let pink = Color(nsColor: spec.patternTint)
        let cyan = Color(nsColor: spec.patternSecondary)
        let gold = Color(nsColor: NSColor(hex: "#ffb84d")!)
        let w = Double(size.width)
        let h = Double(size.height)
        let horizonY: Double = h * (isMini ? 0.66 : 0.81)

        // Upper-sky stars
        let starCount: Int = isMini ? 10 : 26
        for i in 0..<starCount {
            let sx: Double = hash01(i * 29 + 3) * w
            let sy: Double = hash01(i * 43 + 7) * (horizonY * 0.78)
            let r: Double = isMini ? 0.6 : (0.7 + hash01(i * 11) * 0.8)
            let tw: Double = 0.55 + 0.45 * sin(time * 1.5 + Double(i) * 2.1)
            ctx.fill(Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)),
                     with: .color(Color.white.opacity(0.24 * tw)))
        }

        // Banded retro sunset sun tucked to the lower-right so it sits clear of left-aligned text
        let sunX: Double = w * (isMini ? 0.70 : 0.80)
        let sunR: Double = min(w, h) * (isMini ? 0.25 : 0.23)
        let sunY: Double = horizonY - sunR * 0.14
        var sunCtx = ctx
        sunCtx.clip(to: Path(CGRect(x: 0, y: 0, width: w, height: horizonY)))
        let sunRect = CGRect(x: sunX - sunR, y: sunY - sunR, width: sunR * 2, height: sunR * 2)
        let sunGrad = Gradient(stops: [
            .init(color: gold.opacity(0.28), location: 0.0),
            .init(color: pink.opacity(0.24), location: 0.65),
            .init(color: pink.opacity(0.15), location: 1.0)
        ])
        sunCtx.fill(Path(ellipseIn: sunRect),
                    with: .linearGradient(sunGrad, startPoint: CGPoint(x: sunX, y: sunRect.minY), endPoint: CGPoint(x: sunX, y: horizonY)))

        // Dark horizontal retro sunset slices across the lower half of the sun
        let sliceBG = Color(nsColor: NSColor(hex: "#260f3d")!)
        for s in 0..<4 {
            let sy: Double = sunY + sunR * (0.08 + Double(s) * 0.21)
            let sh: Double = (isMini ? 1.2 : 2.0) + Double(s) * (isMini ? 0.4 : 0.7)
            sunCtx.fill(Path(CGRect(x: sunX - sunR, y: sy, width: sunR * 2, height: sh)),
                        with: .color(sliceBG.opacity(0.75)))
        }

        // Horizon glow line (faded in the middle so text never clashes with a hard bar)
        let hGrad = Gradient(stops: [
            .init(color: pink.opacity(isMini ? 0.42 : 0.26), location: 0.0),
            .init(color: pink.opacity(isMini ? 0.34 : 0.12), location: 0.42),
            .init(color: pink.opacity(isMini ? 0.44 : 0.32), location: 1.0)
        ])
        var hLine = Path()
        hLine.move(to: CGPoint(x: 0, y: horizonY))
        hLine.addLine(to: CGPoint(x: w, y: horizonY))
        ctx.stroke(hLine, with: .linearGradient(hGrad, startPoint: CGPoint(x: 0, y: horizonY), endPoint: CGPoint(x: w, y: horizonY)),
                   lineWidth: isMini ? 1.0 : 1.2)

        // Low scrolling perspective laser grid floor
        let floorH: Double = h - horizonY
        let vLines: Int = isMini ? 7 : 13
        var grid = Path()
        for i in 0..<vLines {
            let frac: Double = Double(i) / Double(vLines - 1) - 0.5
            let topX: Double = w * 0.5 + frac * w * 0.52
            let botX: Double = w * 0.5 + frac * w * 1.7
            grid.move(to: CGPoint(x: topX, y: horizonY))
            grid.addLine(to: CGPoint(x: botX, y: h))
        }
        let hLines: Int = isMini ? 4 : 5
        let scroll: Double = (time * 0.42).truncatingRemainder(dividingBy: 1.0)
        for j in 0..<hLines {
            let raw: Double = (Double(j) + scroll) / Double(hLines)
            let y: Double = horizonY + raw * raw * floorH
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: w, y: y))
        }
        let gridGrad = Gradient(stops: [
            .init(color: cyan.opacity(isMini ? 0.20 : 0.10), location: 0.0),
            .init(color: cyan.opacity(isMini ? 0.30 : 0.24), location: 1.0)
        ])
        ctx.stroke(grid, with: .linearGradient(gridGrad, startPoint: CGPoint(x: 0, y: horizonY), endPoint: CGPoint(x: 0, y: h)),
                   lineWidth: isMini ? 0.7 : 0.85)
    }

    // 14. Aurora: undulating northern-lights curtain ribbons + crisp polar stars.
    private static func drawAurora(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                   size: CGSize, time: Double, isMini: Bool) {
        let emerald = Color(nsColor: spec.patternTint)
        let violet = Color(nsColor: spec.patternSecondary)
        let teal = Color(nsColor: NSColor(hex: "#2dd4bf")!)
        let w = Double(size.width)
        let h = Double(size.height)

        // Polar starfield
        let stars: Int = isMini ? 14 : 36
        for i in 0..<stars {
            let sx: Double = hash01(i * 19 + 5) * w
            let sy: Double = hash01(i * 31 + 11) * h * 0.78
            let r: Double = (isMini ? 0.5 : 0.65) + hash01(i * 7) * (isMini ? 0.5 : 0.9)
            let tw: Double = 0.55 + 0.45 * sin(time * (1.1 + hash01(i * 13)) + Double(i))
            ctx.fill(Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)),
                     with: .color(Color.white.opacity(0.26 * tw)))
        }

        // Three gently undulating aurora curtain ribbons
        let ribbonColors: [Color] = [emerald, teal, violet]
        let baseYs: [Double] = [0.24, 0.42, 0.32]
        let amps: [Double] = [0.10, 0.08, 0.09]
        let alphas: [Double] = [0.16, 0.12, 0.11]

        for r in 0..<3 {
            let steps: Int = 18
            let bandH: Double = h * (isMini ? 0.34 : 0.28)
            var topPts: [CGPoint] = []
            var botPts: [CGPoint] = []
            let phase: Double = time * (0.45 + Double(r) * 0.14) + Double(r) * 2.1
            for s in 0...steps {
                let frac: Double = Double(s) / Double(steps)
                let x: Double = frac * w
                let wave: Double = sin(frac * Double.pi * 2.1 + phase) * h * amps[r]
                    + cos(frac * Double.pi * 3.4 - phase * 0.7) * h * 0.03
                let cy: Double = h * baseYs[r] + wave + (frac - 0.5) * h * 0.14
                topPts.append(CGPoint(x: x, y: cy - bandH * 0.5))
                botPts.append(CGPoint(x: x, y: cy + bandH * 0.5))
            }
            var ribbon = Path()
            ribbon.move(to: topPts[0])
            for pt in topPts.dropFirst() { ribbon.addLine(to: pt) }
            for pt in botPts.reversed() { ribbon.addLine(to: pt) }
            ribbon.closeSubpath()

            let grad = Gradient(stops: [
                .init(color: ribbonColors[r].opacity(0), location: 0.0),
                .init(color: ribbonColors[r].opacity(alphas[r]), location: 0.45),
                .init(color: ribbonColors[r].opacity(alphas[r] * 0.35), location: 0.78),
                .init(color: ribbonColors[r].opacity(0), location: 1.0)
            ])
            ctx.fill(ribbon, with: .linearGradient(grad, startPoint: CGPoint(x: w * 0.5, y: 0), endPoint: CGPoint(x: w * 0.5, y: h * 0.85)))
        }
    }

    // 15. Deep Sea: angled underwater caustic light shafts + drifting bioluminescent plankton.
    private static func drawDeepSea(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                    size: CGSize, time: Double, isMini: Bool) {
        let aqua = Color(nsColor: spec.patternTint)
        let seafoam = Color(nsColor: spec.patternSecondary)
        let w = Double(size.width)
        let h = Double(size.height)

        // Soft caustic shafts angling down from the surface
        let shafts: Int = isMini ? 4 : 5
        for i in 0..<shafts {
            let sway: Double = sin(time * 0.55 + Double(i) * 1.3) * w * 0.035
            let topX: Double = w * (0.12 + Double(i) * 0.20) + sway
            let topW: Double = w * (0.06 + hash01(i * 17) * 0.06)
            let botShift: Double = w * 0.14
            let botW: Double = topW * 2.1
            var beam = Path()
            beam.move(to: CGPoint(x: topX - topW * 0.5, y: 0))
            beam.addLine(to: CGPoint(x: topX + topW * 0.5, y: 0))
            beam.addLine(to: CGPoint(x: topX + botShift + botW * 0.5, y: h))
            beam.addLine(to: CGPoint(x: topX + botShift - botW * 0.5, y: h))
            beam.closeSubpath()

            let alpha: Double = 0.075 + 0.025 * sin(time * 0.8 + Double(i) * 1.9)
            let grad = Gradient(stops: [
                .init(color: aqua.opacity(alpha), location: 0.0),
                .init(color: aqua.opacity(alpha * 0.35), location: 0.55),
                .init(color: aqua.opacity(0.0), location: 1.0)
            ])
            ctx.fill(beam, with: .linearGradient(grad, startPoint: CGPoint(x: topX, y: 0), endPoint: CGPoint(x: topX + botShift, y: h)))
        }

        // Drifting bioluminescent plankton motes
        let motes: Int = isMini ? 12 : 28
        for i in 0..<motes {
            let baseX: Double = hash01(i * 23 + 7) * w
            let dx: Double = sin(time * (0.4 + hash01(i * 11) * 0.4) + Double(i)) * (isMini ? 4 : 10)
            let speed: Double = 4.0 + hash01(i * 19) * 6.0
            let sy: Double = h - ((hash01(i * 37 + 5) * h + time * speed).truncatingRemainder(dividingBy: h + 16)) + 8
            let sx: Double = baseX + dx
            let r: Double = (isMini ? 1.0 : 1.5) + hash01(i * 7) * (isMini ? 0.8 : 1.4)
            let pulse: Double = 0.45 + 0.55 * sin(time * 1.6 + Double(i) * 1.7)
            let col = (i % 3 == 0 ? seafoam : aqua)
            let haloR: Double = r * 3.0
            let hg = Gradient(stops: [.init(color: col.opacity(0.24 * pulse), location: 0), .init(color: col.opacity(0), location: 1)])
            ctx.fill(Path(ellipseIn: CGRect(x: sx - haloR, y: sy - haloR, width: haloR * 2, height: haloR * 2)),
                     with: .radialGradient(hg, center: CGPoint(x: sx, y: sy), startRadius: 0.5, endRadius: haloR))
            ctx.fill(Path(ellipseIn: CGRect(x: sx - r * 0.6, y: sy - r * 0.6, width: r * 1.2, height: r * 1.2)),
                     with: .color(col.opacity(0.55 * pulse)))
        }
    }

    // 16. Liquid Glass: luminous frosted specular reflection bands + subtle cool iridescent refraction.
    private static func drawLiquidGlass(spec: ThemeBackdrop, in ctx: inout GraphicsContext,
                                        size: CGSize, isMini: Bool) {
        let iceBlue = Color(nsColor: spec.patternTint)
        let prism = Color(nsColor: spec.patternSecondary)
        let w = Double(size.width)
        let h = Double(size.height)

        // Subtle cool refracted corner tints
        let r1: Double = min(w, h) * 0.72
        let g1 = Gradient(stops: [.init(color: iceBlue.opacity(0.14), location: 0), .init(color: iceBlue.opacity(0), location: 1)])
        ctx.fill(Path(ellipseIn: CGRect(x: w * 0.14 - r1, y: h * 0.10 - r1, width: r1 * 2, height: r1 * 2)),
                 with: .radialGradient(g1, center: CGPoint(x: w * 0.14, y: h * 0.10), startRadius: 2, endRadius: r1))

        let g2 = Gradient(stops: [.init(color: prism.opacity(0.11), location: 0), .init(color: prism.opacity(0), location: 1)])
        ctx.fill(Path(ellipseIn: CGRect(x: w * 0.88 - r1, y: h * 0.90 - r1, width: r1 * 2, height: r1 * 2)),
                 with: .radialGradient(g2, center: CGPoint(x: w * 0.88, y: h * 0.90), startRadius: 2, endRadius: r1))

        // Crisp diagonal specular sheen band
        var band1 = Path()
        band1.move(to: CGPoint(x: w * 0.08, y: 0))
        band1.addLine(to: CGPoint(x: w * 0.42, y: 0))
        band1.addLine(to: CGPoint(x: w * 0.16, y: h))
        band1.addLine(to: CGPoint(x: -w * 0.14, y: h))
        band1.closeSubpath()
        let sheen1 = Gradient(stops: [
            .init(color: Color.white.opacity(0.46), location: 0.0),
            .init(color: Color.white.opacity(0.12), location: 0.6),
            .init(color: Color.white.opacity(0.0), location: 1.0)
        ])
        ctx.fill(band1, with: .linearGradient(sheen1, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: w * 0.3, y: h)))

        // Secondary slender highlight stripe
        var band2 = Path()
        band2.move(to: CGPoint(x: w * 0.48, y: 0))
        band2.addLine(to: CGPoint(x: w * 0.56, y: 0))
        band2.addLine(to: CGPoint(x: w * 0.30, y: h))
        band2.addLine(to: CGPoint(x: w * 0.22, y: h))
        band2.closeSubpath()
        ctx.fill(band2, with: .color(Color.white.opacity(0.22)))
    }
}

/// Build check helper: puts a plain white borderless window behind the pad so edges and glows can be
/// checked against a light desktop on the black-desktop build Mac. Active only when NOTCHPAD_DEBUG
/// and NOTCHPAD_DEBUG_WHITE_BG are set.
enum DebugWhiteDesktop {
    private static var window: NSWindow?

    static func showIfRequested() {
        guard notchPadDebug,
              ProcessInfo.processInfo.environment["NOTCHPAD_DEBUG_WHITE_BG"] != nil,
              window == nil,
              let screen = NSScreen.main else { return }
        let win = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.backgroundColor = .white
        win.isOpaque = true
        win.ignoresMouseEvents = true
        win.level = .normal
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.orderBack(nil)
        win.orderFront(nil)
        window = win
    }
}
