import SwiftUI
import AppKit

// Terminal mode's views: the command line shown in the pad, and its section in Settings.
// The running of commands lives in Terminal.swift; nothing here touches the disk.

/// Shown in the pad in place of the note editor and word-count footer while terminal mode is on.
struct TerminalView: View {
    @ObservedObject var controller: NotchController
    @ObservedObject var session = TerminalSession.shared
    @ObservedObject var addOn = TerminalAddOn.shared
    @ObservedObject var settings = Settings.shared
    @ObservedObject var themes = ThemeStore.shared
    @State private var copiedOutput = false
    @State private var addedToNote = false
    @State private var copiedInstall = false

    init(controller: NotchController) {
        self.controller = controller
    }

    private var theme: PadThemeSpec { themes.current }
    /// A point smaller than the note text: command output is often wide.
    private var textSize: Double { max(10, settings.fontSize - 1) }
    private var inputFont: NSFont { theme.monoFont(size: CGFloat(min(textSize, 15))) }
    private var lastEntry: TerminalEntry? { session.entries.last }

    var body: some View {
        VStack(spacing: 0) {
            mainArea
            if addOn.status == .ready {
                separator
                inputRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { addOn.refresh() }
        .onChange(of: controller.focusToken) { _ in addOn.refresh() }
    }

    @ViewBuilder private var mainArea: some View {
        if addOn.status != .ready {
            setupView
        } else if session.entries.isEmpty {
            emptyView
        } else {
            TerminalTranscriptView(entries: session.entries, theme: theme, fontSize: textSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(theme.secondary.opacity(0.3))
            .frame(height: 1)
            .padding(.horizontal, 4)
    }

    // MARK: Input row

    /// Long folders keep their end, which is the part that tells you where you are.
    private var shortDirectory: String {
        let dir = session.directory
        if dir.count <= 22 { return dir }
        return "…" + String(dir.suffix(21))
    }

    private var inputRow: some View {
        HStack(spacing: 4) {
            Text(shortDirectory)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.secondary)
                .lineLimit(1)
                .fixedSize()
            Text("$")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(theme.accentColor)
                .fixedSize()
            inputField
            if session.isRunning {
                runningControls
            }
            actionButtons
        }
        .padding(.leading, 6)
        // The resize grip sits under the bottom-right corner: keep clear of it.
        .padding(.trailing, 22)
        .frame(height: 24)
    }

    private var inputField: some View {
        TerminalInputLine(font: inputFont,
                          textColor: theme.text,
                          dimColor: theme.text.withAlphaComponent(0.45),
                          accentColor: theme.accent,
                          selectionColor: theme.selection,
                          placeholder: session.isRunning ? "Running… (Control-C stops it)" : "Type a command",
                          focusToken: controller.focusToken)
            .frame(maxWidth: .infinity)
            .background(GeometryReader { g in
                Color.clear.onAppear { reportFieldPosition(g.frame(in: .global)) }
            })
    }

    private func reportFieldPosition(_ f: CGRect) {
        // Report the field's on-screen centre (top-left origin) for the build checks.
        let w = controller.panel.frame
        let screenTop = controller.notch.screenFrame.maxY
        debugLog("NOTCHPAD_TERMFIELD_AT x=\(Int(w.minX + f.midX)) y=\(Int(screenTop - w.maxY + f.midY))")
    }

    private var runningControls: some View {
        HStack(spacing: 2) {
            TerminalBusyDots(color: theme.accentColor)
            iconButton("stop.fill", help: "Stop (Control-C)", tint: theme.accentColor) {
                session.stop()
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            iconButton(copiedOutput ? "checkmark" : "doc.on.doc", help: "Copy the last output") {
                copyLastOutput()
            }
            .disabled(lastEntry == nil || (lastEntry?.output.isEmpty ?? true))
            iconButton(addedToNote ? "checkmark" : "text.append", help: "Add the last command and its output to the note") {
                addLastToNote()
            }
            .disabled(lastEntry == nil)
            iconButton("clear", help: "Clear (Control-L)") {
                session.clear()
            }
            .disabled(!session.entries.contains(where: { !$0.isRunning }))
        }
    }

    private func copyLastOutput() {
        guard let entry = lastEntry, !entry.output.isEmpty else { return }
        ClipboardGuard.shared.copy(entry.output)
        copiedOutput = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedOutput = false }
    }

    private func addLastToNote() {
        guard let entry = lastEntry, !LockManager.shared.isLocked else { return }
        let block = TerminalSession.text(of: entry)
        let store = NoteStore.shared
        var text = store.text
        if !text.isEmpty { text += text.hasSuffix("\n") ? "\n" : "\n\n" }
        store.text = text + block
        addedToNote = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { addedToNote = false }
    }

    private func iconButton(_ symbol: String, help: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(tint ?? theme.secondary)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: Empty and setup states

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Type a command below and press Return. It runs in your usual shell, as you, and what it prints shows here.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Programs that ask for a password (like sudo) or fill the screen (like vim) need Terminal.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .foregroundColor(theme.secondary)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var setupTitle: String {
        addOn.status == .needsUpdate ? "The terminal add-on needs updating" : "Terminal mode needs a small add-on"
    }

    private var setupDetail: String {
        if addOn.status == .needsUpdate {
            return "This version of NotchPad comes with a newer one. Copy this command, paste it into Terminal and press Return, then click Check again."
        }
        return "macOS only lets you install it, so NotchPad can't do it for you. Copy this command, paste it into Terminal and press Return, then click Check again."
    }

    private var setupView: some View {
        ScrollView(.vertical) {
            // The buttons come straight after the title, so they stay in view on the smallest pad.
            VStack(alignment: .leading, spacing: 5) {
                Text(setupTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(nsColor: theme.text))
                    .lineLimit(1)
                    .truncationMode(.tail)
                setupButtons
                Text(setupDetail)
                    .font(.system(size: 11))
                    .foregroundColor(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                installBox
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var installBox: some View {
        Text(addOn.installCommand)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundColor(Color(nsColor: theme.text))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: theme.text).opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(theme.secondary.opacity(0.4), lineWidth: 1))
    }

    /// Side by side when they fit (tightened first on a narrow pad), otherwise one under another.
    private var setupButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { setupButtonItems(compact: false) }
            HStack(spacing: 4) { setupButtonItems(compact: true) }
            VStack(alignment: .leading, spacing: 4) { setupButtonItems(compact: true) }
        }
    }

    /// Drawn in the theme's own colours: system-styled buttons follow Light or Dark mode, not the pad.
    @ViewBuilder private func setupButtonItems(compact: Bool) -> some View {
        Button(copiedInstall ? "Copied" : "Copy command") {
            ClipboardGuard.shared.copy(addOn.installCommand)
            copiedInstall = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedInstall = false }
        }
        .buttonStyle(TerminalPillButtonStyle(fill: theme.accentColor,
                                             label: TerminalPillButtonStyle.readableLabel(on: theme.accent),
                                             outline: theme.accentColor,
                                             padding: compact ? 6 : 8))
        Button("Check again") { addOn.refresh() }
            .buttonStyle(plainPill(compact: compact))
        Button("Open Settings") { controller.openSettings() }
            .buttonStyle(plainPill(compact: compact))
    }

    private func plainPill(compact: Bool) -> TerminalPillButtonStyle {
        TerminalPillButtonStyle(fill: Color.clear, label: Color(nsColor: theme.text),
                                outline: theme.secondary, padding: compact ? 6 : 8)
    }
}

/// A small rounded button in the given colours, the same on every theme and in Light or Dark mode.
private struct TerminalPillButtonStyle: ButtonStyle {
    var fill: Color
    var label: Color
    var outline: Color
    var padding: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundColor(label)
            .padding(.horizontal, padding)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(outline, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    /// Black or white text, whichever reads better on this colour.
    static func readableLabel(on colour: NSColor) -> Color {
        let c = colour.usingColorSpace(.sRGB) ?? colour
        let lum = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return lum > 0.6 ? Color.black : Color.white
    }
}

/// Three dots that light up in turn while a command runs. Plain fills only, no effects.
private struct TerminalBusyDots: View {
    var color: Color

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 0.25)) { context in
            dots(lit: Int(context.date.timeIntervalSinceReferenceDate * 4) % 3)
        }
        .frame(width: 20, height: 16)
        .accessibilityElement()
        .accessibilityLabel("Running")
    }

    private func dots(lit: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .opacity(i == lit ? 1 : 0.3)
            }
        }
    }
}

// MARK: - Transcript

/// Colours and fonts for the transcript, worked out once per update.
private struct TerminalTextStyle {
    let output: [NSAttributedString.Key: Any]
    let directory: [NSAttributedString.Key: Any]
    let command: [NSAttributedString.Key: Any]
    let dimSmall: [NSAttributedString.Key: Any]
    let redSmall: [NSAttributedString.Key: Any]
    /// The first line of every entry but the first gets a little space above it.
    let spacedDirectory: [NSAttributedString.Key: Any]
    let selection: [NSAttributedString.Key: Any]
    let signature: String

    init(theme: PadThemeSpec, fontSize: Double) {
        let size = CGFloat(fontSize)
        let font = theme.monoFont(size: size)
        let small = theme.monoFont(size: max(9, size - 2))
        let bold: NSFont
        if font.fontName == PadFont.mono.nsFont(size: size).fontName {
            bold = NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
        } else {
            let candidate = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            bold = candidate.isFixedPitch ? candidate : font
        }
        let dim: NSColor = theme.text.withAlphaComponent(0.55)
        // A red that reads on dark and light backgrounds alike.
        let red: NSColor = theme.isDark
            ? NSColor(srgbRed: 1.0, green: 0.45, blue: 0.42, alpha: 1)
            : NSColor(srgbRed: 0.74, green: 0.11, blue: 0.11, alpha: 1)

        let plain = NSMutableParagraphStyle()
        plain.lineBreakMode = .byCharWrapping
        let spaced = NSMutableParagraphStyle()
        spaced.lineBreakMode = .byCharWrapping
        spaced.paragraphSpacingBefore = 6

        output = [.font: font, .foregroundColor: theme.text, .paragraphStyle: plain]
        directory = [.font: font, .foregroundColor: dim, .paragraphStyle: plain]
        spacedDirectory = [.font: font, .foregroundColor: dim, .paragraphStyle: spaced]
        command = [.font: bold, .foregroundColor: theme.accent, .paragraphStyle: plain]
        dimSmall = [.font: small, .foregroundColor: dim, .paragraphStyle: plain]
        redSmall = [.font: small, .foregroundColor: red, .paragraphStyle: plain]
        selection = [.backgroundColor: theme.selection, .foregroundColor: theme.text]
        signature = "\(theme.id)|\(theme.name)|\(theme.isCustom)|\(theme.text)|\(theme.accent)|\(theme.selection)|\(theme.isDark)|\(font.fontName)|\(font.pointSize)|\(small.fontName)|\(small.pointSize)|\(bold.fontName)"
    }
}

/// Transcript text view. Copies go through ClipboardGuard so the clipboard privacy settings apply.
final class TerminalTranscriptTextView: NSTextView {
    override func copy(_ sender: Any?) {
        let all = string as NSString
        var parts: [String] = []
        for value in selectedRanges {
            let r = value.rangeValue
            if r.length > 0 && NSMaxRange(r) <= all.length { parts.append(all.substring(with: r)) }
        }
        guard !parts.isEmpty else { return }
        ClipboardGuard.shared.copy(parts.joined(separator: "\n"))
    }
}

/// Read-only, selectable list of commands and what they printed. Appends what changed instead
/// of redrawing everything, so a long, fast-moving output stays smooth.
struct TerminalTranscriptView: NSViewRepresentable {
    var entries: [TerminalEntry]
    var theme: PadThemeSpec
    var fontSize: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        // Built by hand on the classic text system so long text can be laid out lazily.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let tv = TerminalTranscriptTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100), textContainer: container)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.importsGraphics = false
        tv.allowsUndo = false
        tv.textContainerInset = NSSize(width: 4, height: 4)
        tv.setAccessibilityLabel("Command output")

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        let style = TerminalTextStyle(theme: theme, fontSize: fontSize)
        context.coordinator.render(entries, style: style, in: tv)
    }

    final class Coordinator {
        /// What is in the text view right now.
        private var rendered: [TerminalEntry] = []
        private var signature = ""
        /// Where the last entry's text starts (including the line break before it).
        private var lastBlockStart = 0
        /// Where the last entry's status lines start, just after its output.
        private var lastTailStart = 0
        /// How much of the last entry's output is shown, in UTF-16 units.
        private var lastShown = 0
        /// The end of that shown output, to notice when text was dropped from the front.
        private var lastSample = ""

        fileprivate func render(_ entries: [TerminalEntry], style: TerminalTextStyle, in tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let restyle = style.signature != signature
            if !restyle && entries == rendered { return }
            if restyle { tv.selectedTextAttributes = style.selection }
            let wasAtBottom = isAtBottom(tv)

            storage.beginEditing()
            if restyle || !keepsEarlierEntries(entries) {
                rebuild(entries, style: style, storage: storage)
            } else {
                update(entries, style: style, storage: storage)
            }
            storage.endEditing()

            rendered = entries
            signature = style.signature
            if wasAtBottom {
                tv.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
            }
        }

        private func isAtBottom(_ tv: NSTextView) -> Bool {
            guard let scroll = tv.enclosingScrollView else { return true }
            let visible = scroll.contentView.bounds
            return visible.maxY >= tv.frame.height - 8
        }

        /// True when everything shown before the last rendered entry is unchanged and that entry is still there.
        private func keepsEarlierEntries(_ entries: [TerminalEntry]) -> Bool {
            let old = rendered
            guard !old.isEmpty, entries.count >= old.count else { return false }
            let last = old.count - 1
            for i in 0..<last where old[i] != entries[i] { return false }
            let a = old[last], b = entries[last]
            return a.id == b.id && a.command == b.command && a.directory == b.directory
        }

        private func rebuild(_ entries: [TerminalEntry], style: TerminalTextStyle, storage: NSTextStorage) {
            let built = NSMutableAttributedString()
            lastBlockStart = 0; lastTailStart = 0; lastShown = 0; lastSample = ""
            for entry in entries { appendBlock(entry, to: built, style: style) }
            storage.setAttributedString(built)
        }

        private func update(_ entries: [TerminalEntry], style: TerminalTextStyle, storage: NSTextStorage) {
            let index = rendered.count - 1
            let entry = entries[index]
            let out = entry.output as NSString
            let shown = Coordinator.shownLength(out)
            var grew = shown >= lastShown && lastTailStart <= storage.length
            if grew && lastShown > 0 {
                let n = (lastSample as NSString).length
                grew = out.substring(with: NSRange(location: lastShown - n, length: n)) == lastSample
            }
            if grew {
                // Only new output (and possibly a status line): swap the status lines for the new text.
                storage.deleteCharacters(in: NSRange(location: lastTailStart, length: storage.length - lastTailStart))
                if shown > lastShown {
                    let piece = out.substring(with: NSRange(location: lastShown, length: shown - lastShown))
                    let text = lastShown == 0 ? "\n" + piece : piece
                    storage.append(NSAttributedString(string: text, attributes: style.output))
                }
                lastTailStart = storage.length
                lastShown = shown
                lastSample = Coordinator.sample(out, shown)
                storage.append(Coordinator.statusLines(entry, style: style))
            } else {
                // Its output was cut from the front, or changed some other way: redo just this entry.
                let start = min(lastBlockStart, storage.length)
                storage.deleteCharacters(in: NSRange(location: start, length: storage.length - start))
                appendBlock(entry, to: storage, style: style)
            }
            if entries.count > rendered.count {
                for entry in entries[rendered.count...] { appendBlock(entry, to: storage, style: style) }
            }
        }

        /// One entry: the prompt line, its output, then any status lines. Never ends in a line break.
        private func appendBlock(_ entry: TerminalEntry, to text: NSMutableAttributedString, style: TerminalTextStyle) {
            lastBlockStart = text.length
            let first = text.length == 0
            if !first { text.append(NSAttributedString(string: "\n", attributes: style.output)) }
            text.append(NSAttributedString(string: entry.directory + " $ ",
                                           attributes: first ? style.directory : style.spacedDirectory))
            text.append(NSAttributedString(string: entry.command, attributes: style.command))
            let out = entry.output as NSString
            let shown = Coordinator.shownLength(out)
            if shown > 0 {
                let body = out.substring(with: NSRange(location: 0, length: shown))
                text.append(NSAttributedString(string: "\n" + body, attributes: style.output))
            }
            lastTailStart = text.length
            lastShown = shown
            lastSample = Coordinator.sample(out, shown)
            text.append(Coordinator.statusLines(entry, style: style))
        }

        /// Only when worth saying: NotchPad's note, "stopped", or a non-zero exit status.
        private static func statusLines(_ entry: TerminalEntry, style: TerminalTextStyle) -> NSAttributedString {
            let lines = NSMutableAttributedString()
            if let note = entry.note, !note.isEmpty {
                lines.append(NSAttributedString(string: "\n" + note, attributes: style.dimSmall))
            }
            guard let status = entry.exitStatus else { return lines }   // still running
            if status < 0 { return lines }                              // couldn't run at all: the note says why
            if entry.stopped {
                lines.append(NSAttributedString(string: "\nstopped", attributes: style.dimSmall))
            } else if status != 0 {
                lines.append(NSAttributedString(string: "\nexit \(status)", attributes: style.redSmall))
            }
            return lines
        }

        /// The output's length without one trailing line break (the next line starts the next entry).
        private static func shownLength(_ out: NSString) -> Int {
            let length = out.length
            if length > 0 && out.character(at: length - 1) == 10 { return length - 1 }
            return length
        }

        private static func sample(_ out: NSString, _ shown: Int) -> String {
            let n = min(32, shown)
            return out.substring(with: NSRange(location: shown - n, length: n))
        }
    }
}

// MARK: - Input field

/// One-line field for typing commands. Picks up keyboard focus as soon as it is on screen.
final class TerminalInputField: NSTextField {
    var accent: NSColor = .controlAccentColor
    var selection: NSColor = .selectedTextBackgroundColor
    var tint: NSColor = .textColor
    var focusWhenShown = true

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { styleEditor() }
        return ok
    }

    /// The shared field editor does the drawing while typing: give it the theme's cursor and selection colours.
    func styleEditor() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = accent
        editor.selectedTextAttributes = [.backgroundColor: selection, .foregroundColor: tint]
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusWhenShown, window != nil else { return }
        focusWhenShown = false
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let w = self.window else { return }
            w.makeFirstResponder(self)
        }
    }
}

struct TerminalInputLine: NSViewRepresentable {
    var font: NSFont
    var textColor: NSColor
    var dimColor: NSColor
    var accentColor: NSColor
    var selectionColor: NSColor
    var placeholder: String
    var focusToken: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TerminalInputField {
        let field = TerminalInputField(frame: NSRect(x: 0, y: 0, width: 200, height: 18))
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.lineBreakMode = .byClipping
        field.maximumNumberOfLines = 1
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        field.setAccessibilityLabel("Command")
        field.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        field.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        context.coordinator.field = field
        context.coordinator.lastFocus = focusToken
        context.coordinator.installMonitor()
        apply(to: field, coordinator: context.coordinator)
        return field
    }

    func updateNSView(_ field: TerminalInputField, context: Context) {
        apply(to: field, coordinator: context.coordinator)
        if context.coordinator.lastFocus != focusToken {
            context.coordinator.lastFocus = focusToken
            DispatchQueue.main.async { [weak field] in
                guard let f = field else { return }
                f.window?.makeFirstResponder(f)
            }
        }
    }

    static func dismantleNSView(_ field: TerminalInputField, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    private func apply(to field: TerminalInputField, coordinator: Coordinator) {
        let key = "\(font.pointSize)|\(textColor)|\(accentColor)|\(selectionColor)|\(placeholder)"
        guard key != coordinator.styleKey else { return }
        coordinator.styleKey = key
        field.font = font
        field.textColor = textColor
        field.accent = accentColor
        field.selection = selectionColor
        field.tint = textColor
        field.placeholderAttributedString = NSAttributedString(string: placeholder,
                                                               attributes: [.font: font, .foregroundColor: dimColor])
        field.styleEditor()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        weak var field: TerminalInputField?
        var lastFocus = 0
        var styleKey = ""
        /// Where we are in the history while walking it with the arrows; nil when on the line being typed.
        private var historyIndex: Int?
        /// The half-typed line, kept while walking the history.
        private var draft = ""
        private var monitor: Any?

        deinit { removeMonitor() }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                if self.handleKey(event) { return nil }
                return event
            }
        }

        func removeMonitor() {
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
        }

        /// Control-C stops and Control-L clears, while the field or the transcript has focus.
        /// (Command-C, V, X, A and Z are handled for the whole pad by NotchController.)
        private func handleKey(_ event: NSEvent) -> Bool {
            guard let field = field, let window = field.window, event.window === window else { return false }
            let responder = window.firstResponder
            let editor = field.currentEditor()
            let inField = editor != nil && responder === editor
            let inTranscript = responder is TerminalTranscriptTextView
            guard inField || inTranscript else { return false }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let key = (event.charactersIgnoringModifiers ?? "").lowercased()
            if flags == .control {
                if key == "c" { TerminalSession.shared.stop(); return true }
                if key == "l" { TerminalSession.shared.clear(); return true }
            }
            return false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) { submit(); return true }
            if commandSelector == #selector(NSResponder.moveUp(_:)) { walkHistory(back: true); return true }
            if commandSelector == #selector(NSResponder.moveDown(_:)) { walkHistory(back: false); return true }
            return false
        }

        /// Return: runs the line. Does nothing while a command is still running (typing ahead is fine).
        private func submit() {
            let session = TerminalSession.shared
            guard let field = field, !session.isRunning else { return }
            let line = field.stringValue
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            session.run(line)
            field.stringValue = ""
            historyIndex = nil
            draft = ""
        }

        private func walkHistory(back: Bool) {
            guard let field = field else { return }
            let history = TerminalSession.shared.history
            guard !history.isEmpty else { return }
            if back {
                if let i = historyIndex {
                    if i > 0 { historyIndex = i - 1 }
                } else {
                    draft = field.stringValue
                    historyIndex = history.count - 1
                }
            } else {
                guard let i = historyIndex else { return }
                historyIndex = i + 1 < history.count ? i + 1 : nil
            }
            var line = draft
            if let i = historyIndex, i >= 0, i < history.count { line = history[i] }
            field.stringValue = line
            field.currentEditor()?.selectedRange = NSRange(location: (line as NSString).length, length: 0)
        }
    }
}

// MARK: - Settings

/// A title with a short explanation under it, like the other settings.
private struct TerminalOptionLabel: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The "Terminal mode" section of the Settings window.
struct TerminalSettingsSection: View {
    @ObservedObject var s = Settings.shared
    @ObservedObject var addOn = TerminalAddOn.shared
    @State private var copiedInstall = false
    @State private var copiedRemove = false

    init() {}

    var body: some View {
        Section("Terminal mode") {
            Toggle(isOn: $s.terminalEnabled) {
                TerminalOptionLabel(title: "Terminal mode",
                                    detail: "Adds a button to the pad that turns it into a command line: type a command, it runs in your shell and what it prints shows in the pad. One command at a time. Needs a small add-on that you install yourself.")
            }
            .id("terminalMode")
            if s.terminalEnabled {
                Group {
                    statusRow
                    installRows
                    Toggle(isOn: $s.terminalFullShell) {
                        TerminalOptionLabel(title: "Load my full shell setup",
                                            detail: "Aliases and functions from your shell's startup file (such as ~/.zshrc) work too. Slower to start, and a noisy setup can add stray text to the output.")
                    }
                    removeRow
                }
            }
            Text("NotchPad itself still has no internet access and can't read your files (only theme files you choose to import). Commands you run here run outside NotchPad, as you, much as they would in Terminal, so they can use the internet and your files. Commands and their output are kept in memory only and never saved, unless you add them to your note. macOS only lets you install the add-on yourself: NotchPad can't switch this on by itself.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { addOn.refresh() }
    }

    private var statusText: String {
        switch addOn.status {
        case .ready: return "Add-on installed and ready"
        case .needsUpdate: return "Add-on needs updating"
        case .notInstalled: return "Add-on not installed"
        }
    }

    private var statusColour: Color {
        switch addOn.status {
        case .ready: return .green
        case .needsUpdate: return .orange
        case .notInstalled: return .red
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColour).frame(width: 8, height: 8)
            Text(statusText)
            Spacer()
        }
    }

    private var installRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("To install or update it, paste this into Terminal and press Return:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(addOn.installCommand)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.secondary.opacity(0.12)))
            HStack {
                Button(copiedInstall ? "Copied" : "Copy install command") {
                    ClipboardGuard.shared.copy(addOn.installCommand)
                    copiedInstall = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedInstall = false }
                }
                Button("Check again") { addOn.refresh() }
            }
        }
    }

    private var removeRow: some View {
        HStack {
            Button(copiedRemove ? "Copied" : "Copy remove command") {
                ClipboardGuard.shared.copy(addOn.removeCommand)
                copiedRemove = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedRemove = false }
            }
            Text("Paste it into Terminal to take the add-on off again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
