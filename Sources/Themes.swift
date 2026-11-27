import AppKit
import SwiftUI
import Combine

/// A colour theme. Built-in ones live in code; custom ones are theme files in Ghostty's format
/// (`background = #282a36`, `foreground = …`, `cursor-color = …`, `selection-background = …`).
struct PadThemeSpec: Identifiable, Equatable {
    var id: String            // stable key saved in settings
    var name: String          // shown in the gallery
    var background: NSColor
    var text: NSColor
    var accent: NSColor       // cursor, pin, highlights
    var selection: NSColor
    var isCustom = false

    var secondary: Color { Color(nsColor: text).opacity(0.55) }
    var accentColor: Color { Color(nsColor: accent) }

    var isDark: Bool {
        let c = background.usingColorSpace(.sRGB) ?? background
        let lum = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return lum < 0.5
    }

    static func == (a: PadThemeSpec, b: PadThemeSpec) -> Bool { a.id == b.id && a.isCustom == b.isCustom && a.name == b.name }
}

extension NSColor {
    /// "#rrggbb", "rrggbb" or "#rgb".
    convenience init?(hex raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
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
        loadCustom()
        systemIsDark = ThemeStore.appearanceIsDark()
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
        return PadThemeSpec(id: "custom:" + file.lastPathComponent, name: name, background: bg, text: fg,
                            accent: accent, selection: selection, isCustom: true)
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
    ]
}
