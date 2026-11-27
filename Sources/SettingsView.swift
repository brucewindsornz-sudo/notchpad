import SwiftUI
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
enum NotchActions { static var dock: (() -> Void)? }

struct SettingsView: View {
    @ObservedObject var s = Settings.shared
    @ObservedObject var themes = ThemeStore.shared
    @State private var themeFilter = 0   // 0 all, 1 dark, 2 light
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmErase = false
    @State private var confirmReset = false

    var body: some View {
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
                if s.themeFollowsSystem {
                    Text("Light mode: \(themes.theme(id: s.lightThemeID).name)   ·   Dark mode: \(themes.theme(id: s.darkThemeID).name)\nClick a light theme to use it in Light mode, or a dark theme for Dark mode.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Show", selection: $themeFilter) {
                    Text("All").tag(0); Text("Dark").tag(1); Text("Light").tag(2)
                }
                .pickerStyle(.segmented)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 12)], spacing: 12) {
                    ForEach(filteredThemes) { t in
                        ThemeTile(theme: t, selected: isSelected(t), badge: badge(for: t))
                            .onTapGesture { themes.choose(t) }
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
                Text("Theme files use Ghostty's format (background, foreground, cursor-color, selection-background), so any Ghostty theme can be imported as it is. Files you put in the Themes folder show up after Reload. Right-click your own themes to delete them.")
                    .font(.caption).foregroundStyle(.secondary)
            }

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
                Picker("Font", selection: $s.font) {
                    ForEach(PadFont.allCases) { Text($0.label).tag($0) }
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

            Section("Size and position") {
                Toggle(isOn: $s.rememberLayout) {
                    OptionLabel(title: "Remember size and position",
                                detail: "After a restart it opens at the size you last dragged it to, in the same spot. If it was kept open, it reopens too.")
                }
                Text("Drag the top bar to move it anywhere. Drag the bottom-right corner to resize. Drop it near the notch to tuck it back in.")
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

            Section("General") {
                Toggle(isOn: Binding(get: { launchAtLogin }, set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch { NSLog("NotchPad: login item change failed: \(error.localizedDescription)") }
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
                Label("NotchPad has no internet access. Notes are encrypted on this Mac with a key kept in your Keychain, and there's no tracking of any kind.",
                      systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 760)
        .onAppear { themes.loadCustom() }
    }

    private var filteredThemes: [PadThemeSpec] {
        themes.all.filter { themeFilter == 0 || (themeFilter == 1 ? $0.isDark : !$0.isDark) }
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

/// A small preview card: the pad's colours, a notch, sample text, a selection and the cursor.
struct ThemeTile: View {
    let theme: PadThemeSpec
    let selected: Bool
    let badge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(nsColor: theme.background))
                Capsule().fill(Color.black).frame(width: 34, height: 9).offset(y: -2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Groceries").fontWeight(.semibold)
                    HStack(spacing: 0) {
                        Text("milk, ").foregroundColor(Color(nsColor: theme.text).opacity(0.8))
                        Text("eggs").padding(.horizontal, 1).background(Color(nsColor: theme.selection))
                        Rectangle().fill(theme.accentColor).frame(width: 1.5, height: 11).padding(.leading, 1)
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: theme.text))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.top, 16)
                Circle().fill(theme.accentColor).frame(width: 6, height: 6)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 8).padding(.top, 6)
            }
            .frame(height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2.5 : 1))
            HStack(spacing: 4) {
                Text(theme.name).font(.caption).lineLimit(1)
                Spacer(minLength: 0)
                if let badge = badge { Text(badge).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .contentShape(Rectangle())
        .help(theme.name)
    }
}
