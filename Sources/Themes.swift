import AppKit
import SwiftUI
import Combine

/// A colour and typography theme. Built-ins live in code; custom themes use Ghostty's format
/// (`background = #282a36`, `foreground = …`, `cursor-color = …`, `selection-background = …`).
struct PadThemeSpec: Identifiable, Equatable {
    var id: String            // stable key saved in settings
    var name: String          // shown in the gallery
    var background: NSColor
    var text: NSColor
    var accent: NSColor       // cursor, pin, highlights
    var selection: NSColor
    var isCustom = false
    var isSignature = false
    var style: PadThemeStyle? = nil

    var secondary: Color { Color(nsColor: text).opacity(0.55) }
    var accentColor: Color { Color(nsColor: accent) }

    var isDark: Bool {
        let c = background.usingColorSpace(.sRGB) ?? background
        let lum = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return lum < 0.5
    }

    var hasOwnFont: Bool { style?.typeface != nil || style?.face != nil }

    func font(_ setting: PadFont, size: CGFloat) -> NSFont {
        let scaled = size * (style?.scale ?? 1)
        if setting == .theme, let style, hasOwnFont { return style.resolvedFont(size: scaled) }
        return setting.nsFont(size: scaled)
    }

    func monoFont(size: CGFloat) -> NSFont {
        if hasOwnFont, let style {
            // Keep terminal sizes controlled by the terminal, not the note's size scale.
            let font = style.resolvedFont(size: size)
            if font.isFixedPitch { return font }
        }
        return PadFont.mono.nsFont(size: size)
    }

    func textAttributes(_ setting: PadFont, size: CGFloat) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font(setting, size: size), .foregroundColor: text]
        if let spacing = style?.tracking, spacing != 0 { attributes[.kern] = spacing }
        if let spacing = style?.leading, spacing != 0 {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = spacing
            attributes[.paragraphStyle] = paragraph
        }
        if let glow = style?.glow {
            let shadow = NSShadow()
            shadow.shadowColor = glow.withAlphaComponent(0.33)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = .zero
            attributes[.shadow] = shadow
        }
        return attributes
    }

    var closeEffectID: String? { style?.close }

    var styleSummary: String {
        guard let style else { return "" }
        var parts: [String] = []
        if let typeface = style.typeface {
            switch typeface {
            case .design: parts.append(typeface.label)
            case .named: parts.append(style.resolvedFont(size: 13).familyName ?? typeface.label)
            }
        }
        if let face = style.face, face != .regular { parts.append(face.rawValue) }
        if style.glow != nil { parts.append("glow") }
        if parts.isEmpty, style.scale != 1 || style.leading != 0 || style.tracking != 0 {
            parts.append("Custom typography")
        }
        return parts.joined(separator: " · ")
    }
}

struct PadThemeStyle: Equatable {
    enum Typeface: Equatable {
        case design(PadFont)
        case named([String], fallback: PadFont)

        var label: String {
            switch self {
            case .design(.mono): return "Monospaced"
            case .design(.serif): return "Serif"
            case .design(.rounded): return "Rounded"
            case .design: return "System"
            case .named(let names, _): return names.first ?? "System"
            }
        }

        init(custom value: String) {
            switch value.lowercased() {
            case "mono", "monospace", "monospaced": self = .design(.mono)
            case "serif": self = .design(.serif)
            case "rounded": self = .design(.rounded)
            case "system": self = .design(.system)
            default: self = .named([value], fallback: .system)
            }
        }
    }

    enum Face: String {
        case regular = "Regular", light = "Light", medium = "Medium", semibold = "Semibold"
        case bold = "Bold", italic = "Italic", boldItalic = "Bold Italic"

        init?(custom raw: String) {
            let value = raw.lowercased().filter { !($0.isWhitespace || $0 == "-" || $0 == "_") }
            switch value {
            case "regular", "normal": self = .regular
            case "light": self = .light
            case "medium": self = .medium
            case "semibold", "demibold": self = .semibold
            case "bold": self = .bold
            case "italic", "oblique": self = .italic
            case "bolditalic", "boldoblique": self = .boldItalic
            default: return nil
            }
        }

        var systemWeight: NSFont.Weight {
            switch self {
            case .bold, .boldItalic: return .bold
            case .semibold: return .semibold
            case .medium: return .medium
            case .light: return .light
            case .regular, .italic: return .regular
            }
        }

        // NSFontManager uses its own relative weight scale (5 is regular, 9 is bold).
        var familyWeight: Int {
            switch self {
            case .light: return 3
            case .medium: return 6
            case .semibold: return 8
            case .bold, .boldItalic: return 9
            case .regular, .italic: return 5
            }
        }

        var traits: NSFontTraitMask {
            switch self {
            case .bold: return .boldFontMask
            case .italic: return .italicFontMask
            case .boldItalic: return [.boldFontMask, .italicFontMask]
            default: return []
            }
        }
    }

    var typeface: Typeface? = nil
    var face: Face? = nil
    var scale: CGFloat = 1
    var leading: CGFloat = 0
    var tracking: CGFloat = 0
    var glow: NSColor? = nil
    var close: String? = nil

    func resolvedFont(size: CGFloat) -> NSFont {
        let face = self.face ?? .regular
        let manager = NSFontManager.shared
        let fallback: PadFont
        switch typeface {
        case .named(let names, let design):
            for name in names {
                if let exact = NSFont(name: name, size: size) {
                    if self.face == nil { return exact }
                    if let family = exact.familyName,
                       let styled = manager.font(withFamily: family, traits: face.traits, weight: face.familyWeight, size: size) {
                        return styled
                    }
                    var styled = exact
                    let convertibleTraits: [NSFontTraitMask] = [.boldFontMask, .italicFontMask]
                    for trait in convertibleTraits where face.traits.contains(trait) {
                        styled = manager.convert(styled, toHaveTrait: trait)
                    }
                    return styled
                }
                if let font = manager.font(withFamily: name, traits: face.traits, weight: face.familyWeight, size: size)
                    ?? manager.font(withFamily: name, traits: [], weight: 5, size: size) {
                    return font
                }
            }
            fallback = design
        case .design(let design): fallback = design
        case nil: fallback = .system
        }

        let base: NSFont
        if fallback == .mono {
            base = NSFont.monospacedSystemFont(ofSize: size, weight: face.systemWeight)
        } else {
            let standard = NSFont.systemFont(ofSize: size, weight: face.systemWeight)
            let design: NSFontDescriptor.SystemDesign? = fallback == .serif ? .serif : (fallback == .rounded ? .rounded : nil)
            if let design, let descriptor = standard.fontDescriptor.withDesign(design),
               let designed = NSFont(descriptor: descriptor, size: size) {
                base = designed
            } else {
                base = standard
            }
        }
        if face.traits.contains(.italicFontMask) {
            return manager.convert(base, toHaveTrait: .italicFontMask)
        }
        return base
    }
}

extension NSColor {
    /// "#rrggbb", "rrggbb" or "#rgb".
    convenience init?(hex raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, s.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}

final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published private(set) var custom: [PadThemeSpec] = []
    @Published private(set) var systemIsDark = false
    @Published private(set) var lastImportMessage: String?

    private var appearanceObservation: NSKeyValueObservation?
    private let settings = Settings.shared

    init() {
        systemIsDark = ThemeStore.appearanceIsDark()
        loadCustom()
        appearanceObservation = NSApp?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.systemIsDark = ThemeStore.appearanceIsDark() }
        }
    }

    private static func appearanceIsDark() -> Bool {
        let a = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        return a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    var all: [PadThemeSpec] { ThemeStore.builtIn + custom }

    func theme(id: String) -> PadThemeSpec {
        all.first(where: { $0.id == id }) ?? ThemeStore.builtIn[0]
    }

    /// The theme to draw right now (follows light/dark mode if that's switched on).
    var current: PadThemeSpec {
        if settings.themeFollowsSystem {
            return theme(id: systemIsDark ? settings.darkThemeID : settings.lightThemeID)
        }
        return theme(id: settings.themeID)
    }

    /// Pick a theme. In follow-system mode it fills the slot matching the theme's own brightness.
    func choose(_ t: PadThemeSpec) {
        if settings.themeFollowsSystem {
            if t.isDark { settings.darkThemeID = t.id } else { settings.lightThemeID = t.id }
        } else {
            settings.themeID = t.id
        }
        objectWillChange.send()
        logCurrentStyle()
    }

    // MARK: Custom theme files

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("NotchPad/Themes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func loadCustom() {
        let files = (try? FileManager.default.contentsOfDirectory(at: ThemeStore.folder, includingPropertiesForKeys: nil)) ?? []
        custom = files
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { ThemeStore.parse(file: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        debugLog("NOTCHPAD_THEMES custom=\(custom.map { $0.name })")
        logCurrentStyle()
    }

    private func logCurrentStyle() {
        guard notchPadDebug else { return }
        let theme = current
        let font = theme.font(settings.font, size: CGFloat(settings.fontSize))
        debugLog("NOTCHPAD_THEME_STYLE name=\(theme.name) font=\(font.fontName) close=\(theme.closeEffectID ?? "none")")
    }

    /// Reads a Ghostty-style theme file. Needs at least `background` and `foreground`.
    static func parse(file: URL) -> PadThemeSpec? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        var palette: [Int: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#") { continue }
            let parts = l.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0] == "palette" {
                // palette = 4=#7aa2f7
                let p = parts[1].split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                if p.count == 2, let n = Int(p[0]) { palette[n] = p[1] }
            } else {
                values[parts[0]] = parts[1]
            }
        }
        guard let bg = values["background"].flatMap(NSColor.init(hex:)),
              let fg = values["foreground"].flatMap(NSColor.init(hex:)) else { return nil }
        let accent = values["cursor-color"].flatMap(NSColor.init(hex:))
            ?? palette[4].flatMap(NSColor.init(hex:))
            ?? NSColor.controlAccentColor
        let selection = values["selection-background"].flatMap(NSColor.init(hex:))
            ?? (bg.blended(withFraction: 0.25, of: fg) ?? bg)
        let name = file.deletingPathExtension().lastPathComponent
        func number(_ key: String, in range: ClosedRange<Double>, default fallback: CGFloat) -> CGFloat {
            guard let raw = values[key], let number = Double(raw), number.isFinite, range.contains(number) else { return fallback }
            return CGFloat(number)
        }
        let close = values["notchpad-close"].flatMap { raw in
            CloseEffect.allCases.first { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }?.rawValue
        }
        let style = PadThemeStyle(
            typeface: values["font-family"].flatMap { $0.isEmpty ? nil : PadThemeStyle.Typeface(custom: $0) },
            face: values["font-style"].flatMap(PadThemeStyle.Face.init(custom:)),
            scale: number("notchpad-font-size-scale", in: 0.75...1.5, default: 1),
            leading: number("notchpad-line-spacing", in: 0...12, default: 0),
            tracking: number("notchpad-letter-spacing", in: -1...4, default: 0),
            glow: values["notchpad-glow"].flatMap(NSColor.init(hex:)),
            close: close)
        return PadThemeSpec(id: "custom:" + file.lastPathComponent, name: name, background: bg, text: fg,
                            accent: accent, selection: selection, isCustom: true,
                            style: style == PadThemeStyle() ? nil : style)
    }

    /// Copies a theme file the user picked into NotchPad's Themes folder.
    func importThemes(from urls: [URL]) {
        var ok = 0, bad: [String] = []
        for url in urls {
            guard ThemeStore.parse(file: url) != nil else { bad.append(url.lastPathComponent); continue }
            let dest = ThemeStore.folder.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            do { try FileManager.default.copyItem(at: url, to: dest); ok += 1 } catch { bad.append(url.lastPathComponent) }
        }
        loadCustom()
        if bad.isEmpty {
            lastImportMessage = ok == 1 ? "Imported 1 theme." : "Imported \(ok) themes."
        } else {
            lastImportMessage = "Imported \(ok). Couldn't read: \(bad.joined(separator: ", ")) (needs background and foreground colours)."
        }
        if ok == 1, urls.count == 1, let t = custom.first(where: { $0.id == "custom:" + urls[0].lastPathComponent }) { choose(t) }
    }

    func deleteCustom(_ t: PadThemeSpec) {
        guard t.isCustom else { return }
        let file = String(t.id.dropFirst("custom:".count))
        try? FileManager.default.removeItem(at: ThemeStore.folder.appendingPathComponent(file))
        loadCustom()
    }

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import NotchPad or Ghostty themes"
        panel.message = "Pick theme files. Ghostty theme files work as they are."
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let ghostty = URL(fileURLWithPath: "/Applications/Ghostty.app/Contents/Resources/ghostty/themes")
        if FileManager.default.fileExists(atPath: ghostty.path) { panel.directoryURL = ghostty }
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { importThemes(from: panel.urls) }
    }

    // MARK: Built-in themes

    private static func t(_ id: String, _ name: String, _ bg: String, _ fg: String, _ accent: String, _ sel: String) -> PadThemeSpec {
        PadThemeSpec(id: id, name: name, background: NSColor(hex: bg)!, text: NSColor(hex: fg)!,
                     accent: NSColor(hex: accent)!, selection: NSColor(hex: sel)!)
    }

    private static func signature(
        _ id: String, _ name: String, _ bg: String, _ fg: String, _ accent: String, _ sel: String,
        fonts: [String], fallback: PadFont, face: PadThemeStyle.Face? = nil, scale: CGFloat = 1,
        leading: CGFloat = 2, tracking: CGFloat = 0, glow: String? = nil, close: String
    ) -> PadThemeSpec {
        var theme = t(id, name, bg, fg, accent, sel)
        theme.isSignature = true
        theme.style = PadThemeStyle(typeface: .named(fonts, fallback: fallback), face: face, scale: scale,
                                   leading: leading, tracking: tracking, glow: glow.flatMap(NSColor.init(hex:)), close: close)
        return theme
    }

    static let builtIn: [PadThemeSpec] = [
        t("notch", "Notch Black", "#000000", "#f2f2f2", "#0a84ff", "#2c2c2e"),
        t("graphite", "Graphite", "#29292b", "#ebebeb", "#0a84ff", "#3d3d40"),
        t("midnight", "Midnight Blue", "#0f1730", "#e0ebff", "#6ea8ff", "#22305a"),
        t("paper", "Paper", "#faf5e6", "#26241f", "#e8782a", "#eadfc4"),
        t("catppuccin-mocha", "Catppuccin Mocha", "#1e1e2e", "#cdd6f4", "#cba6f7", "#45475a"),
        t("catppuccin-latte", "Catppuccin Latte", "#eff1f5", "#4c4f69", "#8839ef", "#ccd0da"),
        t("dracula", "Dracula", "#282a36", "#f8f8f2", "#bd93f9", "#44475a"),
        t("nord", "Nord", "#2e3440", "#d8dee9", "#88c0d0", "#434c5e"),
        t("tokyo-night", "Tokyo Night", "#1a1b26", "#c0caf5", "#7aa2f7", "#33467c"),
        t("gruvbox-dark", "Gruvbox Dark", "#282828", "#ebdbb2", "#fabd2f", "#504945"),
        t("gruvbox-light", "Gruvbox Light", "#fbf1c7", "#3c3836", "#d65d0e", "#d5c4a1"),
        t("solarized-dark", "Solarized Dark", "#002b36", "#93a1a1", "#268bd2", "#073642"),
        t("solarized-light", "Solarized Light", "#fdf6e3", "#586e75", "#268bd2", "#eee8d5"),
        t("rose-pine", "Rosé Pine", "#191724", "#e0def4", "#ebbcba", "#403d52"),
        t("rose-pine-dawn", "Rosé Pine Dawn", "#faf4ed", "#575279", "#d7827e", "#dfdad9"),
        t("one-dark", "One Dark", "#282c34", "#abb2bf", "#61afef", "#3e4451"),
        t("monokai", "Monokai", "#272822", "#f8f8f2", "#a6e22e", "#49483e"),
        t("kanagawa", "Kanagawa", "#1f1f28", "#dcd7ba", "#7e9cd8", "#2d4f67"),
        t("everforest-dark", "Everforest Dark", "#2d353b", "#d3c6aa", "#a7c080", "#475258"),
        t("github-dark", "GitHub Dark", "#0d1117", "#e6edf3", "#2f81f7", "#1f3a5f"),
        t("github-light", "GitHub Light", "#ffffff", "#1f2328", "#0969da", "#ddf4ff"),
        signature("matrix", "Matrix", "#07110b", "#9dffab", "#48ed75", "#173e24",
                  fonts: ["Menlo-Regular", "Monaco"], fallback: .mono, tracking: 0.15, glow: "#3bfa73", close: "matrix"),
        signature("stargate", "Stargate", "#091821", "#c8f4ff", "#ffb875", "#243c53",
                  fonts: ["Futura-Medium", "AvenirNext-Medium"], fallback: .rounded, tracking: 0.4, glow: "#69d4ff", close: "stargate"),
        signature("storm", "Storm", "#171c2c", "#e2edff", "#b2b9ff", "#333c57",
                  fonts: ["Avenir Next", "Helvetica Neue"], fallback: .system, face: .medium, glow: "#9eaaff", close: "lightning"),
        signature("transporter", "Transporter", "#191329", "#f4deff", "#f7aafd", "#3d2c52",
                  fonts: ["Avenir Next", "Futura"], fallback: .rounded, face: .semibold, tracking: 0.3, glow: "#dc79ff", close: "teleport"),
        signature("singularity", "Singularity", "#100b16", "#fde8ee", "#ff946e", "#3b263b",
                  fonts: ["Baskerville", "Georgia"], fallback: .serif, face: .regular, scale: 1.13, leading: 3, close: "blackHole"),
        signature("phosphor", "Phosphor", "#1c1207", "#ffda94", "#ffb454", "#493014",
                  fonts: ["Monaco", "Menlo-Regular"], fallback: .mono, tracking: 0.25, glow: "#ffad47", close: "tv"),
        signature("chalkboard", "Chalkboard", "#192a25", "#f0f2dc", "#bfdcaa", "#374d44",
                  fonts: ["ChalkboardSE-Regular", "MarkerFelt-Thin"], fallback: .rounded, scale: 1.1, leading: 3, close: "dust"),
        signature("ember-typewriter", "Ember Typewriter", "#fff1d8", "#352417", "#963b1e", "#e4c5a0",
                  fonts: ["AmericanTypewriter", "CourierNewPSMT"], fallback: .serif, leading: 3, close: "burn"),
        signature("field-notes", "Field Notes", "#faf1db", "#332f22", "#725024", "#dfd0a9",
                  fonts: ["Noteworthy-Bold", "ChalkboardSE-Regular"], fallback: .rounded, scale: 1.15, leading: 4, close: "dust"),
        signature("blueprint", "Blueprint", "#0e2640", "#d0efff", "#79d8ff", "#294664",
                  fonts: ["Menlo", "Monaco"], fallback: .mono, face: .regular, tracking: 0.45, close: "teleport"),
        signature("neon-district", "Neon District", "#201025", "#ffd9ec", "#70e8e1", "#492346",
                  fonts: ["Futura-MediumItalic", "AvenirNext-Italic"], fallback: .rounded, tracking: 0.25, glow: "#ff73b8", close: "lightning"),
        signature("morning-edition", "Morning Edition", "#f8f7f1", "#282924", "#71402e", "#dbd8ca",
                  fonts: ["Georgia", "Baskerville"], fallback: .serif, face: .regular, scale: 1.06, leading: 3, close: "dust"),
    ]
}
