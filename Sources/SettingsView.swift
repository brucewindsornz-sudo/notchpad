import SwiftUI
import AppKit
import CoreText
import ServiceManagement

private struct OptionLabel: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Lets the settings window ask the notch controller to re-dock the pad.
enum NotchActions {
    static var dock: (() -> Void)?
    /// Plays a closing animation on the real pad (nil = whatever the current setting picks).
    static var previewClose: ((CloseEffect?) -> Void)?
}

struct SettingsView: View {
    @ObservedObject var s = Settings.shared
    @ObservedObject var themes = ThemeStore.shared
    @State private var themeFilter = 0   // 0 all, 1 dark, 2 light, 3 special (signature themes)
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmErase = false
    @State private var confirmReset = false
    @State private var clipboardCleared = false

    var body: some View {
        ScrollViewReader { scroller in
        Form {
            Section("How it opens and closes") {
                Toggle(isOn: $s.keepOpen) {
                    OptionLabel(title: "Keep the scratchpad open",
                                detail: "It stays open until you close it with the arrow button or Esc. Same as the pin button.")
                }
                Toggle(isOn: $s.openOnHover) {
                    OptionLabel(title: "Open just by hovering",
                                detail: "Opens when you rest the pointer on the notch, no click needed. Closes when you move away.")
                }
                Toggle(isOn: $s.closeOnClickOutside) {
                    OptionLabel(title: "Close when I click somewhere else",
                                detail: "Clicking another app tucks it back into the notch. Ignored while it's kept open.")
                }
                Toggle(isOn: $s.hotkeyEnabled) {
                    OptionLabel(title: "Keyboard shortcut: Control + Option + N",
                                detail: "Opens or closes the scratchpad from anywhere.")
                }
            }

            Section("Hover feel") {
                Toggle(isOn: $s.hoverNudge) {
                    OptionLabel(title: "Nudge when the pointer is over the notch",
                                detail: "The notch grows a little so you know it's there.")
                }
                Toggle(isOn: $s.haptics) {
                    OptionLabel(title: "Gentle trackpad tap on hover",
                                detail: "A light click you feel on Force Touch trackpads.")
                }
            }

            Section("Theme") {
                Toggle(isOn: $s.themeFollowsSystem) {
                    OptionLabel(title: "Match light and dark mode",
                                detail: "Uses one theme when your Mac is in Light mode and another in Dark mode, like Ghostty's light/dark themes.")
                }
                .id("theme")
                if s.themeFollowsSystem {
                    Text("Light mode: \(themes.theme(id: s.lightThemeID).name)   ·   Dark mode: \(themes.theme(id: s.darkThemeID).name)\nClick a light theme to use it in Light mode, or a dark theme for Dark mode.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(isOn: $s.colourText) {
                    OptionLabel(title: "Colourful text",
                                detail: "Gives headings, lists, numbers, links and tags their own theme colours.")
                }
                Toggle(isOn: $s.themeBackdrop) {
                    OptionLabel(title: "Theme backgrounds",
                                detail: "Draws each theme's own shading, pattern and edge instead of one flat colour.")
                }
                if s.themeBackdrop {
                    Toggle(isOn: $s.themeMotion) {
                        OptionLabel(title: "Moving backgrounds",
                                    detail: "Lets themes with gentle motion (falling code, twinkling stars) move while the pad is open.")
                    }
                }
                Picker("Show", selection: $themeFilter) {
                    Text("All").tag(0); Text("Dark").tag(1); Text("Light").tag(2); Text("Special").tag(3)
                }
                .pickerStyle(.segmented)
                .help("Special themes bring their own font, background, text colours and closing animation.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 12)], spacing: 12) {
                    ForEach(filteredThemes) { t in
                        ThemeTile(theme: t, selected: isSelected(t), badge: badge(for: t))
                            .id("theme-" + t.id)
                            .onTapGesture { themes.choose(t) }
                            .accessibilityAction { themes.choose(t) }
                            .contextMenu {
                                Button("Use this theme") { themes.choose(t) }
                                if t.isCustom { Button("Delete theme", role: .destructive) { themes.deleteCustom(t) } }
                            }
                    }
                }
                .padding(.vertical, 4)
                HStack {
                    Button("Import theme files…") { themes.presentImportPanel() }
                    Button("Open Themes folder") { NSWorkspace.shared.open(ThemeStore.folder) }
                    Button("Reload") { themes.loadCustom() }
                }
                if let msg = themes.lastImportMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
                Text("Theme files use Ghostty's format (background, foreground, cursor-color, selection-background), so any Ghostty theme can be imported as it is. A theme file can also choose its own font, text style, background and closing animation; the README shows how. Files you put in the Themes folder show up after Reload. Right-click your own themes to delete them.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            CloseAnimationSettingsSection()
            FlightAnimationSettingsSection()

            Section("Look") {
                Picker("Size", selection: Binding(get: { s.size }, set: { new in
                    s.size = new
                    s.customWidth = 0; s.customHeight = 0   // picking a preset replaces a dragged size
                })) {
                    ForEach(PadSize.allCases) { Text($0.label).tag($0) }
                }
                if s.hasCustomSize {
                    LabeledContent("Your size") {
                        HStack {
                            Text("\(Int(s.customWidth)) × \(Int(s.customHeight))").monospacedDigit()
                            Button("Use preset") { s.customWidth = 0; s.customHeight = 0 }
                        }
                    }
                }
                Picker(selection: $s.font) {
                    ForEach(PadFont.allCases) { Text($0.label).tag($0) }
                } label: {
                    OptionLabel(title: "Font",
                                detail: "\"Theme's own font\" uses the font your theme comes with, or the standard font if it has none. Pick any other font to use it with every theme instead.")
                }
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $s.fontSize, in: 11...24, step: 1)
                        Text("\(Int(s.fontSize)) pt").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent("See-through") {
                    HStack {
                        Slider(value: $s.opacity, in: 0.6...1.0)
                        Text(s.opacity > 0.99 ? "Solid" : "\(Int((1 - s.opacity) * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle(isOn: $s.showWordCount) {
                    OptionLabel(title: "Show word count", detail: "A small counter along the bottom.")
                }
            }

            Section("Pad buttons") {
                Text("The buttons along the top of the pad. Switch off the ones you don't use. Settings and Close always stay, so you can't lock yourself out.")
                    .font(.caption).foregroundStyle(.secondary)
                    .id("padButtons")
                ForEach(PadButton.allCases) { b in
                    Toggle(isOn: Binding(get: { s.shows(b) }, set: { s.setShows(b, $0) })) {
                        HStack(alignment: .top, spacing: 10) {
                            PadButtonIcon(button: b)
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 18)
                            OptionLabel(title: b.title, detail: b.detail)
                        }
                    }
                    .disabled(!b.canHide)
                }
                if !s.hiddenButtons.isEmpty {
                    Button("Show all buttons") { s.hiddenButtons = [] }
                }
            }

            Section("Size and position") {
                Toggle(isOn: $s.rememberLayout) {
                    OptionLabel(title: "Remember size and position",
                                detail: "After a restart it opens at the size you last dragged it to, in the same spot. If it was kept open, it reopens too.")
                }
                Text("Drag the move button (next to the bin) or the top bar to move it anywhere. Drag the bottom-right corner to resize. Bring it back near the notch and it snaps into the centre, like a magnet.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Put it back in the notch") { NotchActions.dock?() }
                        .disabled(!s.detached)
                    Button("Reset size and position") { s.resetLayout(); NotchActions.dock?() }
                        .disabled(!s.detached && !s.hasCustomSize)
                }
            }

            Section("Privacy") {
                Toggle(isOn: $s.hideFromCapture) {
                    OptionLabel(title: "Hide from screenshots and screen sharing",
                                detail: "Keeps your notes out of Zoom, Teams, FaceTime shares and screenshots.")
                }
                Toggle(isOn: $s.lockEnabled) {
                    OptionLabel(title: "Lock with Touch ID",
                                detail: "Asks for your fingerprint or Mac password before showing notes. Also locks when your Mac locks or sleeps.")
                }
                if s.lockEnabled {
                    Picker("Ask again", selection: $s.lockAfter) {
                        ForEach(LockAfter.allCases) { Text($0.label).tag($0) }
                    }
                }
                Toggle(isOn: $s.blurWhenAway) {
                    OptionLabel(title: "Blur notes when the pointer leaves",
                                detail: "Handy when it's kept open: text is blurred until you point at it.")
                }
                Picker(selection: $s.autoErase) {
                    ForEach(AutoErase.allCases) { Text($0.label).tag($0) }
                } label: {
                    OptionLabel(title: "Erase notes automatically", detail: "For notes you only need for a while.")
                }
                Toggle(isOn: $s.spellCheck) {
                    OptionLabel(title: "Spell check",
                                detail: "Underlines typos. Checking happens on this Mac.")
                }
                Button("Erase my notes now…", role: .destructive) { confirmErase = true }
                    .confirmationDialog("Erase everything in the scratchpad?", isPresented: $confirmErase) {
                        Button("Erase", role: .destructive) { NoteStore.shared.eraseAll() }
                    } message: { Text("This can't be undone.") }
            }

            Section("Clipboard") {
                Picker(selection: $s.clipboardClear) {
                    ForEach(ClipboardClear.allCases) { Text($0.label).tag($0) }
                } label: {
                    OptionLabel(title: "Clear the clipboard after copying",
                                detail: "After you use the copy button, the clipboard is wiped once this time is up. Anything you've copied from another app since is left alone.")
                }
                Toggle(isOn: $s.clipboardClearOnLock) {
                    OptionLabel(title: "Also clear it when my Mac locks or sleeps",
                                detail: "Also when you lock the pad or quit NotchPad. Only if the clipboard still holds text copied from NotchPad.")
                }
                Toggle(isOn: $s.clipboardThisMacOnly) {
                    OptionLabel(title: "Keep copies on this Mac",
                                detail: "Stops Universal Clipboard passing them to your iPhone, iPad or other Macs.")
                }
                Toggle(isOn: $s.clipboardHideFromHistory) {
                    OptionLabel(title: "Keep copies out of clipboard history apps",
                                detail: "Asks apps like Maccy, Raycast, Paste and Alfred not to save them. Most respect this.")
                }
                HStack {
                    Button(clipboardCleared ? "Clipboard cleared" : "Clear clipboard now") {
                        ClipboardGuard.shared.clearNow()
                        clipboardCleared = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { clipboardCleared = false }
                    }
                    Text("Wipes whatever is on the clipboard, from any app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Grouped so the form stays within what older Swift compilers accept in one block.
            Group {
            TerminalSettingsSection()

            Section("General") {
                Toggle(isOn: Binding(get: { launchAtLogin }, set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch { /* silent: no system log entries */ }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                })) {
                    OptionLabel(title: "Start when I log in", detail: "Works best once NotchPad is in your Applications folder.")
                }
                Toggle(isOn: $s.showMenuBarIcon) {
                    OptionLabel(title: "Show icon in the menu bar",
                                detail: "If hidden, open settings with the gear inside the scratchpad.")
                }
                HStack {
                    Button("Reset all settings…") { confirmReset = true }
                        .confirmationDialog("Put every setting back to how it started?", isPresented: $confirmReset) {
                            Button("Reset") { s.resetToDefaults() }
                        } message: { Text("Your notes are not touched.") }
                    Spacer()
                    Button("Quit NotchPad") { NSApp.terminate(nil) }
                }
            }

            Section {
                Label(privacySummary, systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 760)
        .onAppear {
            themes.loadCustom()
            // Build checks only: jump to a section so its screenshot can be looked at.
            if let section = ProcessInfo.processInfo.environment["NOTCHPAD_DEBUG_SETTINGS"], section.count > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { scroller.scrollTo(section, anchor: .top) }
            }
        }
        }
    }

    /// The one-paragraph promise at the bottom. Says so plainly when terminal mode is switched on.
    private var privacySummary: String {
        let promise = "NotchPad has no internet access. Notes are encrypted on this Mac with a key kept in your Keychain, and there's no tracking of any kind."
        guard s.terminalEnabled else { return promise }
        return promise + " Terminal mode is on: commands you run there run outside NotchPad, as they would in Terminal, and can use the internet and your files."
    }

    private var filteredThemes: [PadThemeSpec] {
        themes.all.filter { t in
            switch themeFilter {
            case 1: return t.isDark
            case 2: return !t.isDark
            case 3: return t.isSignature
            default: return true
            }
        }
    }

    private func isSelected(_ t: PadThemeSpec) -> Bool {
        s.themeFollowsSystem ? (t.id == s.lightThemeID || t.id == s.darkThemeID) : t.id == s.themeID
    }

    private func badge(for t: PadThemeSpec) -> String? {
        if t.isCustom && !isSelected(t) { return "Yours" }
        guard s.themeFollowsSystem else { return nil }
        if t.id == s.lightThemeID && t.id == s.darkThemeID { return "Both" }
        if t.id == s.lightThemeID { return "Light" }
        if t.id == s.darkThemeID { return "Dark" }
        return nil
    }
}

/// A small preview card: the pad's backdrop, a notch, sample text in the theme's ink colours, and the cursor.
struct ThemeTile: View {
    let theme: PadThemeSpec
    let selected: Bool
    let badge: String?
    @ObservedObject private var settings = Settings.shared

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    var body: some View {
        let ink = theme.ink
        let useInk = settings.colourText
        let titleColor = useInk ? Color(nsColor: ink.title) : sampleColour
        let markerColor = useInk ? Color(nsColor: ink.marker) : theme.accentColor
        let numberColor = useInk ? Color(nsColor: ink.number) : sampleColour.opacity(0.86)
        let tagColor = useInk ? Color(nsColor: ink.tag) : sampleColour

        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .top) {
                if settings.themeBackdrop && !testNoEffects {
                    ThemeBackdropView(theme: theme, shape: tileShape, isOpen: false, allowMotion: false, isMini: true)
                } else {
                    tileShape.fill(Color(nsColor: theme.background))
                }
                Capsule().fill(Color.black).frame(width: 34, height: 9).offset(y: -2)
                VStack(alignment: .leading, spacing: 2.5) {
                    Text("Trip plan")
                        .fontWeight(.semibold)
                        .foregroundColor(titleColor)
                        .lineLimit(1)
                    HStack(spacing: 0) {
                        Text("• ").foregroundColor(markerColor)
                        Text("ferry ").foregroundColor(sampleColour.opacity(0.86))
                        Text("9:30 ").foregroundColor(numberColor)
                        Text("#trip")
                            .foregroundColor(tagColor)
                            .padding(.horizontal, 1.5)
                            .background(Color(nsColor: theme.selection).opacity(0.75))
                        Rectangle().fill(theme.accentColor).frame(width: 1.4, height: 10).padding(.leading, 1)
                    }
                    .lineLimit(1)
                }
                .font(sampleFont)
                .modifier(SettingsGlow(color: glow))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 16)
                HStack(spacing: 2.5) {
                    if useInk {
                        Circle().fill(Color(nsColor: ink.title)).frame(width: 4.5, height: 4.5)
                        Circle().fill(Color(nsColor: ink.number)).frame(width: 4.5, height: 4.5)
                        Circle().fill(Color(nsColor: ink.tag)).frame(width: 4.5, height: 4.5)
                    } else {
                        Circle().fill(theme.accentColor).frame(width: 5.5, height: 5.5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 7)
                .padding(.top, 6)
            }
            .frame(height: 64)
            .clipShape(tileShape)
            .overlay(tileShape
                .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2.5 : 1))
            HStack(spacing: 4) {
                Text(theme.name).font(.caption).lineLimit(1)
                Spacer(minLength: 0)
                if let badge = badge { Text(badge).font(.caption2).foregroundStyle(.secondary) }
            }
            if !styleLine.isEmpty {
                HStack(spacing: 3) {
                    if let e = effect { Image(systemName: e.symbol) }
                    Text(styleLine).lineLimit(1).truncationMode(.tail)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .help(styleLine.isEmpty ? theme.name : theme.name + ": " + styleLine)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(theme.name + " theme"))
        .accessibilityValue(Text(accessibilityValueText))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    /// The theme's own font, so each tile shows its character whatever the Font setting says.
    private var sampleFont: Font {
        let f: NSFont = theme.font(.theme, size: 10)
        return Font(f as CTFont)
    }

    private var attributes: [NSAttributedString.Key: Any] { theme.textAttributes(.theme, size: 10) }

    private var sampleColour: Color {
        if let c = attributes[.foregroundColor] as? NSColor { return Color(nsColor: c) }
        return Color(nsColor: theme.text)
    }

    private var glow: Color? {
        guard let shadow = attributes[.shadow] as? NSShadow, let c = shadow.shadowColor else { return nil }
        return Color(nsColor: c)
    }

    private var effect: CloseEffect? {
        guard let id = theme.closeEffectID else { return nil }
        return CloseEffect(rawValue: id)
    }

    /// For example "Menlo · glow · Matrix close", or "" for a plain theme.
    private var styleLine: String {
        var parts: [String] = []
        let summary = theme.styleSummary
        if !summary.isEmpty { parts.append(summary) }
        if let e = effect, !summary.localizedCaseInsensitiveContains(e.label) {
            parts.append(e.label + " close")
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityValueText: String {
        var parts: [String] = []
        if selected { parts.append("Selected") }
        if let b = badge { parts.append(b) }
        if !styleLine.isEmpty { parts.append(styleLine) }
        return parts.joined(separator: ", ")
    }
}

/// A soft glow behind text, only for themes that ask for one.
private struct SettingsGlow: ViewModifier {
    let color: Color?
    @ViewBuilder func body(content: Content) -> some View {
        if let c = color, ProcessInfo.processInfo.environment["NOTCHPAD_NO_EFFECTS"] == nil {
            content.shadow(color: c, radius: 2)
        } else {
            content
        }
    }
}

// MARK: - Closing animation

/// The "Closing animation" section: a gallery like the theme one, then speed and a try-it button.
/// Only one preview moves at a time: the one under the pointer, or the one just clicked.
struct CloseAnimationSettingsSection: View {
    @ObservedObject var s = Settings.shared
    @ObservedObject var themes = ThemeStore.shared
    @State private var hoverKey: String?
    @State private var clickKey: String?
    @State private var clickToken = 0

    init() {}

    var body: some View {
        Section("Closing animation") {
            Text("How the pad tucks back into the notch. Point at one to watch it, click to choose it.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .id("closeAnimation")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 12)], spacing: 12) {
                matchThemeTile
                tile(key: "classic", title: "Classic", subtitle: "Shrinks back into the notch.",
                     symbol: "arrow.up.to.line", preview: AnyView(classicPreview(key: "classic")))
                tile(key: "random", title: "Surprise me", subtitle: "A different one each time.",
                     symbol: "shuffle", preview: AnyView(CloseSurprisePreview(theme: theme, font: padFont,
                                                                              playing: playingKey == "random")))
                ForEach(CloseEffect.allCases) { e in
                    tile(key: e.rawValue, title: e.label, subtitle: e.detail, symbol: e.symbol,
                         preview: AnyView(effectPreview(e, key: e.rawValue)))
                }
            }
            .padding(.vertical, 4)
            Picker("Speed", selection: $s.closeSpeed) {
                ForEach(CloseSpeed.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                Button("Try it on the pad") { NotchActions.previewClose?(nil) }
                Text("Plays your choice on the pad itself.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(motionCaption)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var theme: PadThemeSpec { themes.current }

    private var padFont: Font {
        let f: NSFont = theme.font(s.font, size: 9)
        return Font(f as CTFont)
    }

    private var playingKey: String? { hoverKey ?? clickKey }

    private var motionCaption: String {
        let base = "Closing animations are skipped when Reduce motion is on (System Settings, Accessibility, Display); the pad then simply closes."
        if reduceMotionOn {
            return "Reduce motion is on, so the pad closes without an animation. " + base
        }
        return base
    }

    /// "Match theme": shows what that means for the current theme right now.
    private var matchThemeTile: some View {
        let resolved: CloseEffect? = CloseEffect.resolve(setting: "theme", theme: theme)
        let subtitle: String
        let preview: AnyView
        if let e = resolved {
            subtitle = "Now: " + e.label + ", from " + theme.name + "."
            preview = AnyView(effectPreview(e, key: "theme"))
        } else {
            subtitle = "Now: Classic. " + theme.name + " has no animation of its own."
            preview = AnyView(classicPreview(key: "theme"))
        }
        return tile(key: "theme", title: "Match theme", subtitle: subtitle,
                    symbol: "paintpalette", preview: preview)
    }

    /// Restarts from the beginning when clicked: a new identity means a fresh preview.
    private func previewID(_ key: String) -> String {
        clickKey == key ? key + "-" + String(clickToken) : key
    }

    private func effectPreview(_ e: CloseEffect, key: String) -> some View {
        CloseEffectPreview(effect: e, theme: theme, playing: playingKey == key)
            .id(previewID(key))
    }

    private func classicPreview(key: String) -> some View {
        CloseClassicPreview(theme: theme, font: padFont, playing: playingKey == key)
            .id(previewID(key))
    }

    private func tile(key: String, title: String, subtitle: String, symbol: String, preview: AnyView) -> some View {
        CloseChoiceTile(title: title, subtitle: subtitle, symbol: symbol,
                        selected: s.closeEffect == key, preview: preview)
            .onHover { inside in
                if inside {
                    hoverKey = key
                } else if hoverKey == key {
                    hoverKey = nil
                }
            }
            .onTapGesture { choose(key) }
            .accessibilityAction { choose(key) }
    }

    /// Selects it and plays it once (about two seconds), even if the pointer moves away.
    private func choose(_ key: String) {
        s.closeEffect = key
        clickToken += 1
        let token = clickToken
        clickKey = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if clickToken == token { clickKey = nil }
        }
    }
}

/// One card in the closing animation gallery.
private struct CloseChoiceTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let selected: Bool
    let preview: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            preview
                .frame(maxWidth: .infinity)
                .frame(height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2.5 : 1))
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption2).foregroundStyle(.secondary)
                Text(title).font(.caption).lineLimit(1)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").font(.caption2).foregroundColor(Color.accentColor)
                }
            }
            Text(subtitle)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
        .help(title + ": " + subtitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title + " closing animation"))
        .accessibilityValue(Text(selected ? "Selected" : ""))
        .accessibilityHint(Text(subtitle))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// A tiny pad under a notch, drawn in the theme. `progress` 0 = open, 1 = tucked away.
private struct CloseMiniPad: View {
    let theme: PadThemeSpec
    let font: Font
    let progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Rectangle().fill(Color.secondary.opacity(0.14))
                pad
                    .frame(width: geo.size.width * 0.78, height: geo.size.height * 0.74)
                    .scaleEffect(x: 1 - 0.7 * progress, y: max(0.02, 1 - progress), anchor: .top)
                    .opacity(Double(1 - 0.85 * progress))
                    .padding(.top, 5)
                Capsule().fill(Color.black).frame(width: 34, height: 9).offset(y: -2)
            }
        }
    }

    private var pad: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(nsColor: theme.background))
            VStack(alignment: .leading, spacing: 2) {
                Text("Groceries").fontWeight(.semibold)
                Text("milk, eggs").opacity(0.8)
            }
            .font(font)
            .foregroundColor(Color(nsColor: theme.text))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.top, 9)
        }
    }
}

/// The classic close: the pad shrinks up into the notch, waits, then comes back.
private struct CloseClassicPreview: View {
    let theme: PadThemeSpec
    let font: Font
    let playing: Bool
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { context in
            CloseMiniPad(theme: theme, font: font, progress: playing ? progress(at: context.date) : 0)
        }
        .onAppear { start = Date() }
        .onChange(of: playing) { now in
            if now { start = Date() }
        }
    }

    /// A 1.8 second loop: hold open, close with an ease-in, stay closed.
    private func progress(at date: Date) -> CGFloat {
        let cycle: Double = 1.8
        let t: Double = date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle) / cycle
        if t < 0.15 { return 0 }
        if t > 0.6 { return 1 }
        let x: Double = (t - 0.15) / 0.45
        return CGFloat(x * x)
    }
}

/// "Surprise me": the pad with a shuffle sign; while playing it flicks through the animations' symbols.
private struct CloseSurprisePreview: View {
    let theme: PadThemeSpec
    let font: Font
    let playing: Bool

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 0.45)) { context in
            CloseMiniPad(theme: theme, font: font, progress: 0)
                .overlay(badge(symbol: symbol(at: context.date)).padding(6), alignment: .bottomTrailing)
        }
    }

    private func symbol(at date: Date) -> String {
        guard playing else { return "shuffle" }
        let all: [CloseEffect] = CloseEffect.allCases
        if all.isEmpty { return "shuffle" }
        let i: Int = Int(date.timeIntervalSinceReferenceDate / 0.45) % all.count
        return all[i].symbol
    }

    private func badge(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(theme.accentColor)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color(nsColor: theme.background)))
            .overlay(Circle().stroke(theme.accentColor.opacity(0.6), lineWidth: 1))
    }
}

