import SwiftUI
import AppKit

/// Notch silhouette: flat top that flares out into the menu bar, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// When moved away from the notch it becomes a plain rounded card.
    var floating = false

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        if floating { return RoundedRectangle(cornerRadius: 18, style: .continuous).path(in: r) }
        let t = min(topRadius, r.width / 4)
        let b = min(bottomRadius, (r.width - 2 * t) / 2, r.height - t)
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
}

struct NotchRootView: View {
    @ObservedObject var controller: NotchController
    @ObservedObject var settings = Settings.shared
    @ObservedObject var themes = ThemeStore.shared

    private var notchSize: CGSize { controller.notch.rect.size }

    private var shapeSize: CGSize {
        // Closed: on a notched Mac the shape is a little smaller than the camera housing, so it's
        // completely hidden behind it (there are no pixels there). On other Macs it shows as a small pill.
        let hidden = controller.notch.hasNotch
        let collapsed = hidden
            ? CGSize(width: max(notchSize.width - 10, 40), height: max(notchSize.height - 4, 10))
            : CGSize(width: notchSize.width + 12, height: notchSize.height)
        // Hover: peeks just past the notch edges and a few points below it.
        let peek = CGSize(width: notchSize.width + 12 + 20, height: notchSize.height + 7)
        switch controller.state {
        case .collapsed: return collapsed
        case .hovering:
            return settings.hoverNudge ? peek : collapsed
        case .expanded: return controller.padSize
        }
    }

    private var expanded: Bool { controller.state == .expanded }

    private var fill: Color {
        expanded ? Color(nsColor: themes.current.background).opacity(settings.opacity) : .black
    }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(topRadius: expanded ? 12 : (controller.state == .hovering ? 6 : (controller.notch.hasNotch ? 0 : 6)),
                       bottomRadius: expanded ? 22 : (controller.state == .hovering ? 12 : 9),
                       floating: expanded && controller.showsDetached)
                .fill(fill)
                .frame(width: shapeSize.width, height: shapeSize.height)
                .modifier(PadShadow(on: expanded && !testNoEffects))
                .overlay(alignment: .bottomTrailing) {
                    if expanded {
                        ResizeGrip(controller: controller, color: themes.current.secondary)
                            .padding(.trailing, controller.showsDetached ? 5 : 16)
                            .padding(.bottom, 5)
                    }
                }

            if expanded {
                ScratchpadView(controller: controller)
                    .frame(width: controller.padSize.width - (controller.showsDetached ? 16 : 24),
                           height: controller.padSize.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Under a closing animation the pad snaps shut at once; the animation is what you see.
        .animation(controller.closingWithEffect ? nil : .spring(response: 0.34, dampingFraction: 0.76), value: controller.state)
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: settings.size)
    }
}

struct ScratchpadView: View {
    @ObservedObject var controller: NotchController
    @ObservedObject var settings = Settings.shared
    @ObservedObject var store = NoteStore.shared
    @ObservedObject var lock = LockManager.shared
    @State private var confirmErase = false
    @State private var copied = false
    @State private var clipCleared = false
    @State private var confirmClearClip = false

    @ObservedObject var themes = ThemeStore.shared
    private var theme: PadThemeSpec { themes.current }
    /// Height of the menu bar strip beside the notch. Nothing clickable goes here: macOS's menu bar takes those clicks.
    private var menuBarHeight: CGFloat { controller.notch.menuBarHeight }

    var body: some View {
        VStack(spacing: 0) {
            if !controller.showsDetached {
                // Sits in the menu bar row, either side of the camera. Kept empty on purpose.
                Color.clear.frame(height: menuBarHeight)
            }
            toolbar
            if lock.isLocked {
                lockedView
            } else if terminalOn {
                TerminalView(controller: controller)
                    .modifier(PadBlur(on: shouldBlur && !testNoEffects))
                    .animation(.easeInOut(duration: 0.2), value: shouldBlur)
            } else {
                PadTextView(text: $store.text,
                            theme: theme,
                            font: settings.font,
                            fontSize: CGFloat(settings.fontSize),
                            spellCheck: settings.spellCheck,
                            focusToken: controller.focusToken)
                    .modifier(PadBlur(on: shouldBlur && !testNoEffects))
                    .animation(.easeInOut(duration: 0.2), value: shouldBlur)
                if settings.showWordCount { footer }
            }
        }
        .padding(.bottom, 10)
    }

    private var copyHelp: String {
        let rule = settings.clipboardClear
        return rule == .never ? "Copy everything" : "Copy everything (clipboard clears \(rule.label.lowercased()))"
    }

    private var shouldBlur: Bool { settings.blurWhenAway && !controller.mouseInside }

    /// The pad is showing the command line instead of the note. Hiding its button switches it back to the note.
    private var terminalOn: Bool { settings.terminalEnabled && settings.terminalMode && settings.shows(.terminal) }

    /// Buttons row, just below the menu bar. The empty middle is the drag handle.
    private var toolbar: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                if settings.shows(.copy) {
                    iconButton(copied ? "checkmark" : "doc.on.doc", help: copyHelp) {
                        ClipboardGuard.shared.copy(store.text)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    }
                    .disabled(lock.isLocked || store.text.isEmpty)
                }
                if settings.shows(.clearClipboard) {
                    // Clear clipboard: wipes whatever is on the clipboard, from any app. Works while locked too.
                    // Two clicks, like the bin: the first arms it (turns red), the second within 3 seconds clears.
                    Button {
                        if confirmClearClip {
                            ClipboardGuard.shared.clearNow()
                            confirmClearClip = false
                            clipCleared = true
                            debugLog("NOTCHPAD_CLEARCLIP=cleared")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { clipCleared = false }
                        } else {
                            confirmClearClip = true
                            debugLog("NOTCHPAD_CLEARCLIP=armed")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmClearClip = false }
                        }
                    } label: {
                        Group {
                            if clipCleared {
                                Image(systemName: "checkmark")
                            } else {
                                Image(systemName: confirmClearClip ? "doc.on.clipboard.fill" : "doc.on.clipboard")
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 7, weight: .bold))
                                            .offset(x: 3, y: 2)
                                    }
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(confirmClearClip ? .red : theme.secondary)
                    .help(confirmClearClip ? "Click again to clear clipboard" : "Clear clipboard")
                    .accessibilityLabel(confirmClearClip ? "Click again to clear clipboard" : "Clear clipboard")
                    .background(GeometryReader { g in
                        Color.clear.onAppear {
                            // Report this button's on-screen centre (top-left origin) for the click test.
                            let f = g.frame(in: .global), w = controller.panel.frame
                            let screenTop = controller.notch.screenFrame.maxY
                            debugLog("NOTCHPAD_CLEARCLIP_AT x=\(Int(w.minX + f.midX)) y=\(Int(screenTop - w.maxY + f.midY))")
                        }
                    })
                }
                if settings.shows(.erase) {
                    iconButton(confirmErase ? "trash.fill" : "trash", help: confirmErase ? "Click again to erase" : "Erase note",
                               tint: confirmErase ? .red : nil) {
                        if confirmErase {
                            store.eraseAll(); confirmErase = false
                        } else {
                            confirmErase = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmErase = false }
                        }
                    }
                    .disabled(lock.isLocked || store.text.isEmpty)
                }
                if settings.shows(.move) {
                    MoveHandle(controller: controller, color: theme.secondary)
                }
                if settings.lockEnabled && !lock.isLocked && settings.shows(.lock) {
                    iconButton("lock", help: "Lock now") {
                        if settings.clipboardClearOnLock { ClipboardGuard.shared.clearIfOurs() }
                        lock.lock()
                    }
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                if settings.terminalEnabled && settings.shows(.terminal) {
                    // Terminal mode: lights up in the accent colour while the pad is a command line.
                    iconButton(terminalOn ? "terminal.fill" : "terminal",
                               help: terminalOn ? "Terminal mode is on (click for your note)" : "Terminal mode",
                               tint: terminalOn ? theme.accentColor : nil) {
                        settings.terminalMode.toggle()
                    }
                    .background(GeometryReader { g in
                        Color.clear.onAppear {
                            // Report this button's on-screen centre (top-left origin) for the click test.
                            let f = g.frame(in: .global), w = controller.panel.frame
                            let screenTop = controller.notch.screenFrame.maxY
                            debugLog("NOTCHPAD_TERM_AT x=\(Int(w.minX + f.midX)) y=\(Int(screenTop - w.maxY + f.midY))")
                        }
                    })
                }
                if settings.shows(.pin) {
                    iconButton(settings.keepOpen ? "pin.fill" : "pin",
                               help: settings.keepOpen ? "Stays open (click to stop)" : "Keep open",
                               tint: settings.keepOpen ? theme.accentColor : nil) {
                        settings.keepOpen.toggle()
                    }
                    .background(GeometryReader { g in
                        Color.clear.onAppear {
                            // Report the pin button's on-screen centre (top-left origin) for the click test.
                            let f = g.frame(in: .global), w = controller.panel.frame
                            let screenTop = controller.notch.screenFrame.maxY
                            debugLog("NOTCHPAD_PIN_AT x=\(Int(w.minX + f.midX)) y=\(Int(screenTop - w.maxY + f.midY))")
                        }
                    })
                }
                if controller.showsDetached && settings.shows(.dock) {
                    // Boomerang: flies the pad back to the notch in a curve.
                    Button { controller.boomerang() } label: {
                        PadButtonIcon(button: .dock)
                            .frame(width: 22, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(theme.secondary)
                    .help("Boomerang: send it back to the notch")
                    .accessibilityLabel("Boomerang: send it back to the notch")
                    .background(GeometryReader { g in
                        Color.clear.onAppear {
                            // Report this button's on-screen centre (top-left origin) for the click test.
                            let f = g.frame(in: .global), w = controller.panel.frame
                            let screenTop = controller.notch.screenFrame.maxY
                            debugLog("NOTCHPAD_BOOMERANG_AT x=\(Int(w.minX + f.midX)) y=\(Int(screenTop - w.maxY + f.midY))")
                        }
                    })
                }
                iconButton("gearshape", help: "Settings") { controller.openSettings() }
                iconButton("chevron.up", help: "Close (Esc)") { controller.collapse() }
                    .background(GeometryReader { g in
                        Color.clear.onAppear {
                            // Report the close button's on-screen centre (top-left origin) for the click test.
                            let f = g.frame(in: .global), w = controller.panel.frame
                            let screenTop = controller.notch.screenFrame.maxY
                            debugLog("NOTCHPAD_CLOSE_AT x=\(Int(w.minX + f.midX)) y=\(Int(screenTop - w.maxY + f.midY)) menubar=\(Int(controller.notch.menuBarHeight))")
                        }
                    })
            }
        }
        .padding(.top, controller.showsDetached ? 6 : 2)
        .frame(height: 30)
        .contentShape(Rectangle())
        .help("Drag to move")
        // Right-click anywhere on the top bar: a way out that doesn't depend on the menu bar icon.
        .contextMenu {
            Button("Close") { controller.collapse() }
            Button("Put Back in Notch") { controller.dock() }
            Button("Reset Position and Size") { controller.resetPosition() }
            Divider()
            Button("Settings…") { controller.openSettings() }
            Button("Quit NotchPad") { NSApp.terminate(nil) }
        }
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { v in controller.moveDrag(translation: v.translation) }
            .onEnded { _ in controller.endMove() })
    }

    private var footer: some View {
        let words = store.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return HStack {
            Text("\(words) \(words == 1 ? "word" : "words") · \(store.text.count) characters")
            Spacer()
            if settings.keepOpen { Text("Pinned open") }
        }
        .font(.system(size: 10))
        .foregroundColor(theme.secondary)
        .padding(.leading, 6)
        .padding(.trailing, 22)
        .padding(.top, 4)
    }

    private var lockedView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "lock.fill").font(.system(size: 22))
            Text("Your scratchpad is locked").font(.system(size: 13, weight: .medium))
            Button("Unlock with Touch ID or password") { lock.unlock() }
                .buttonStyle(.borderedProminent)
                .tint(theme.accentColor)
                .controlSize(.small)
            Spacer()
        }
        .foregroundColor(Color(nsColor: theme.text))
        .frame(maxWidth: .infinity)
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
    }
}

/// Plain-text editor with full control over spell check, fonts and colours.
///
/// Uses TextKit 1 on purpose, built by hand rather than with `NSTextView.scrollableTextView()` (which gives
/// TextKit 2 on recent macOS): theme "ink" is drawn with the layout manager's temporary attributes, which colour
/// the text on screen without ever touching what is stored, saved, copied, undone or counted. That behaves the
/// same on macOS 13 through 26.
struct PadTextView: NSViewRepresentable {
    @Binding var text: String
    var theme: PadThemeSpec
    var font: PadFont
    var fontSize: CGFloat
    var spellCheck: Bool
    var focusToken: Int
    /// Build checks only: colour the text whatever the setting says.
    var colourOverride: Bool? = nil

    struct TextStyle: Equatable {
        let theme: PadThemeSpec
        let font: PadFont
        let size: CGFloat
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = PadTextView.makeScrollView(coordinator: context.coordinator)
        if let tv = scroll.documentView as? NSTextView {
            apply(to: tv, coordinator: context.coordinator)
        }
        if notchPadDebug { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { PadTextView.runInkSelfTest() } }
        return scroll
    }

    static func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let tv = NSTextView(frame: .zero, textContainer: container)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder

        tv.delegate = coordinator
        tv.drawsBackground = false
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        storage.delegate = coordinator
        coordinator.attach(tv, scroll: scroll, storage: storage)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        apply(to: tv, coordinator: context.coordinator)
        if context.coordinator.lastFocus != focusToken {
            context.coordinator.lastFocus = focusToken
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
    }

    private func apply(to tv: NSTextView, coordinator: Coordinator) {
        let style = TextStyle(theme: theme, font: font, size: fontSize)
        let styleChanged = coordinator.style != style
        let replaceText = coordinator.representedText != text
        if styleChanged {
            coordinator.style = style
            coordinator.attributes = theme.textAttributes(font, size: fontSize)
            let paragraph = coordinator.attributes[.paragraphStyle] as? NSParagraphStyle ?? NSParagraphStyle.default
            tv.defaultParagraphStyle = paragraph
            coordinator.attributes[.paragraphStyle] = paragraph
            tv.insertionPointColor = theme.accent
            tv.selectedTextAttributes = [.backgroundColor: theme.selection, .foregroundColor: theme.text]
        }
        if replaceText {
            coordinator.representedText = text
            tv.string = text
        }
        if styleChanged || replaceText {
            if let storage = tv.textStorage, storage.length > 0 {
                // Do not replace characters when a theme changes. Undo, selection and spelling
                // annotations are managed by AppKit separately from these permanent attributes.
                storage.beginEditing()
                coordinator.applyStyle(to: storage, range: NSRange(location: 0, length: storage.length))
                storage.endEditing()
            }
            tv.typingAttributes = coordinator.attributes
        }
        if tv.isContinuousSpellCheckingEnabled != spellCheck { tv.isContinuousSpellCheckingEnabled = spellCheck }
        // Ink follows the theme and the "Colourful text" setting (this view is redrawn when settings change).
        let wanted: ThemeInk? = (colourOverride ?? Settings.shared.colourText) ? theme.ink : nil
        if styleChanged || replaceText || coordinator.ink != wanted {
            coordinator.ink = wanted
            coordinator.refreshInk(force: true)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        private static let styleKeys: [NSAttributedString.Key] = [.font, .foregroundColor, .paragraphStyle, .kern, .shadow]
        /// The only attributes ink sets. All are temporary (drawing only), never in the text storage.
        static let inkKeys: [NSAttributedString.Key] = [.foregroundColor, .strikethroughStyle, .strikethroughColor]
        /// Notes up to this long are coloured whole; longer ones only around what is on screen.
        static let wholeNoteLimit = 20_000
        /// Lines in one sweep of a gradient theme's body colours.
        static let gradientLines: Double = 8

        var parent: PadTextView
        var representedText: String?
        var style: TextStyle?
        var attributes: [NSAttributedString.Key: Any] = [:]
        var lastFocus = -1
        var ink: ThemeInk?

        /// The hand-built TextKit 1 stack: the storage owns the layout manager, so it is kept here.
        private var storage: NSTextStorage?
        private weak var textView: NSTextView?
        private var observers: [NSObjectProtocol] = []
        private var inkShown = false
        private var inkedRange = NSRange(location: NSNotFound, length: 0)
        private var editCount = 0
        private var inkedEditCount = -1
        private var lastWidth: CGFloat = -1
        private(set) var lastCounts: [ThemeInk.Kind: Int] = [:]

        init(_ parent: PadTextView) { self.parent = parent }

        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

        func attach(_ tv: NSTextView, scroll: NSScrollView, storage: NSTextStorage) {
            self.storage = storage
            textView = tv
            let centre = NotificationCenter.default
            scroll.contentView.postsBoundsChangedNotifications = true
            observers.append(centre.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView,
                                                queue: .main) { [weak self] _ in self?.refreshInk() })
            tv.postsFrameChangedNotifications = true
            observers.append(centre.addObserver(forName: NSView.frameDidChangeNotification, object: tv,
                                                queue: .main) { [weak self, weak tv] _ in
                // A new width rewraps lines, which moves gradient colours and what is on screen.
                guard let self, let tv, tv.frame.width != self.lastWidth else { return }
                self.lastWidth = tv.frame.width
                self.refreshInk(force: true)
            })
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let updated = tv.string
            representedText = updated
            tv.typingAttributes = attributes
            parent.text = updated
            editCount += 1
            refreshInk()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, style != nil else { return }
            tv.typingAttributes = attributes
        }

        func applyStyle(to storage: NSTextStorage, range: NSRange) {
            storage.addAttributes(attributes, range: range)
            for key in Self.styleKeys where attributes[key] == nil {
                storage.removeAttribute(key, range: range)
            }
        }

        func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard style != nil, editedMask.contains(.editedCharacters), editedRange.length > 0,
                  NSMaxRange(editedRange) <= textStorage.length else { return }
            // Undo and paste can supply old attributes. Inspect only the edited range and
            // leave already-correct text (including ordinary keystrokes) alone.
            var mismatched: [NSRange] = []
            textStorage.enumerateAttributes(in: editedRange, options: []) { existing, range, _ in
                if Self.styleKeys.contains(where: { key in
                    let before = existing[key] as? NSObject
                    let after = self.attributes[key] as? NSObject
                    return before != after
                }) {
                    mismatched.append(range)
                }
            }
            for range in mismatched { applyStyle(to: textStorage, range: range) }
        }

        // MARK: Ink

        /// Colours the note's parts (or, for a long note, the lines on and near the screen).
        /// Cheap to call often: scrolling within what is already coloured does nothing.
        func refreshInk(force: Bool = false) {
            guard let tv = textView, let layout = tv.layoutManager, let container = tv.textContainer,
                  let storage = tv.textStorage else { return }
            let length = storage.length
            guard let ink, length > 0 else {
                if inkShown {
                    let all = NSRange(location: 0, length: length)
                    for key in Self.inkKeys { layout.removeTemporaryAttribute(key, forCharacterRange: all) }
                    inkShown = false
                    inkedRange = NSRange(location: NSNotFound, length: 0)
                    lastCounts = [:]
                }
                return
            }
            // Leave text being composed (Japanese, Chinese, accents) alone; it is coloured once committed.
            if tv.hasMarkedText() { return }
            let text: NSString = storage.mutableString
            let range: NSRange
            if length <= Self.wholeNoteLimit {
                range = NSRange(location: 0, length: length)
            } else {
                let visible = tv.visibleRect
                let origin = tv.textContainerOrigin
                // One screen above and below, so short scrolls are already coloured.
                let area = NSRect(x: visible.minX - origin.x, y: visible.minY - origin.y - visible.height,
                                  width: visible.width, height: visible.height * 3)
                let glyphs = layout.glyphRange(forBoundingRect: area, in: container)
                let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                range = text.lineRange(for: chars)
            }
            let unchanged = inkShown && inkedEditCount == editCount && inkedRange.location != NSNotFound
                && NSIntersectionRange(inkedRange, range).length == range.length
            if !force && unchanged { return }

            let started = CFAbsoluteTimeGetCurrent()
            let spans = InkScanner.scan(text, in: range, title: InkScanner.titleLine(in: text))
            for key in Self.inkKeys { layout.removeTemporaryAttribute(key, forCharacterRange: range) }
            let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 13)
            let lineHeight: CGFloat = max(1, layout.defaultLineHeight(for: font))
            var counts: [ThemeInk.Kind: Int] = [:]
            for span in spans where span.range.length > 0 && NSMaxRange(span.range) <= length {
                let colour: NSColor?
                if span.kind == .body {
                    guard !ink.body.isEmpty else { continue }
                    let glyph = layout.glyphIndexForCharacter(at: span.range.location)
                    let y: CGFloat = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
                    let phase: Double = Double(y / lineHeight) / Self.gradientLines
                    colour = ink.bodyColor(phase: phase)
                } else {
                    colour = ink.color(for: span.kind)
                }
                guard let colour else { continue }
                var paint: [NSAttributedString.Key: Any] = [.foregroundColor: colour]
                if span.kind == .done {
                    paint[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    paint[.strikethroughColor] = colour
                }
                layout.addTemporaryAttributes(paint, forCharacterRange: span.range)
                counts[span.kind, default: 0] += 1
            }
            inkShown = true
            inkedRange = range
            inkedEditCount = editCount
            lastCounts = counts
            if notchPadDebug {
                let ms: Double = (CFAbsoluteTimeGetCurrent() - started) * 1000
                let summary = ThemeInk.Kind.allCases.compactMap { kind in counts[kind].map { "\(kind.rawValue)=\($0)" } }
                debugLog("NOTCHPAD_INK chars=\(length) coloured=\(range.length) \(summary.joined(separator: " ")) ms=\(String(format: "%.2f", ms))")
            }
        }
    }

    // MARK: Build check

    private static var selfTestRan = false

    /// Debug builds only: an off-screen editor is put through typing, undo, redo, every theme and the
    /// colour switch, checking each time that the stored note is exactly what was typed and holds no ink.
    static func runInkSelfTest() {
        guard notchPadDebug, !selfTestRan else { return }
        selfTestRan = true
        let sample = "Weekend plan\n- Call the plumber about the tap\n- [x] Book the ferry for Friday 9:30\n"
            + "- [ ] milk, eggs, $12.50 of coffee\n# Deck ideas\n1. wider steps, 2 seats\n> measure twice\n"
            + "\"quoted\" and `code` https://example.com/deck #home @sam\nSHOPPING\nTo do:\n"
        let themes = ThemeStore.shared.all
        var model = PadTextView(text: .constant(sample), theme: themes[0], font: .theme, fontSize: 14,
                                spellCheck: true, focusToken: 0, colourOverride: true)
        let coordinator = model.makeCoordinator()
        let scroll = makeScrollView(coordinator: coordinator)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 320), styleMask: [.borderless],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        guard let tv = scroll.documentView as? NSTextView, let layout = tv.layoutManager,
              let storage = tv.textStorage else { debugLog("NOTCHPAD_INK_SELFTEST failed=no-text-view"); return }
        var failures: [String] = []
        func ink(at index: Int) -> NSColor? {
            layout.temporaryAttribute(.foregroundColor, atCharacterIndex: index, effectiveRange: nil) as? NSColor
        }
        func storedIsPlain(_ base: NSColor, _ label: String) {
            var leaked = false
            storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length), options: []) { value, _, _ in
                if (value as? NSColor) != base { leaked = true }
            }
            if leaked { failures.append("stored-colour:" + label) }
            if storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) != nil { failures.append("stored-strike:" + label) }
        }

        // Every theme: same characters, base colour only in storage, title painted with that theme's ink.
        for theme in themes {
            model.theme = theme
            model.apply(to: tv, coordinator: coordinator)
            if storage.string != sample { failures.append("text:" + theme.id) }
            storedIsPlain(theme.text, theme.id)
            if ink(at: 0) != theme.ink.title { failures.append("title-ink:" + theme.id) }
        }
        let counts = coordinator.lastCounts
        let summary = ThemeInk.Kind.allCases.compactMap { kind in counts[kind].map { "\(kind.rawValue)=\($0)" } }

        // Typing, undo and redo.
        let typed = "\n- paid $45 at 9:30 #done @kim"
        var typing = "ok"
        if let undo = tv.undoManager {
            undo.groupsByEvent = false
            undo.beginUndoGrouping()
            tv.setSelectedRange(NSRange(location: storage.length, length: 0))
            tv.insertText(typed, replacementRange: tv.selectedRange())
            undo.endUndoGrouping()
            if storage.string != sample + typed || coordinator.representedText != sample + typed { typing = "typed-mismatch" }
            let money = (storage.string as NSString).range(of: "$45")
            if money.location == NSNotFound || ink(at: money.location) != model.theme.ink.number { typing = "typed-not-inked" }
            undo.undo()
            if storage.string != sample { typing = "undo-mismatch" }
            undo.redo()
            if storage.string != sample + typed { typing = "redo-mismatch" }
            undo.undo()
            if storage.string != sample { typing = "undo2-mismatch" }
            storedIsPlain(model.theme.text, "after-undo")
        } else {
            typing = "no-undo-manager"
        }
        if typing != "ok" { failures.append(typing) }

        // Switching ink off removes every colour.
        model.colourOverride = false
        model._text = .constant(storage.string)
        model.apply(to: tv, coordinator: coordinator)
        if ink(at: 0) != nil { failures.append("off-still-inked") }
        model.colourOverride = true
        model.apply(to: tv, coordinator: coordinator)

        // A long note: colour only around the screen, and time one keystroke in the middle.
        tv.allowsUndo = false
        var long = ""
        while long.utf16.count < 100_000 { long += sample }
        model._text = .constant(long)
        let loadStart = CFAbsoluteTimeGetCurrent()
        model.apply(to: tv, coordinator: coordinator)
        let loadMs: Double = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        let middle = NSRange(location: storage.length / 2, length: 0)
        tv.scrollRangeToVisible(middle)
        tv.setSelectedRange(middle)
        let keyStart = CFAbsoluteTimeGetCurrent()
        tv.insertText("x", replacementRange: middle)
        let keyMs: Double = (CFAbsoluteTimeGetCurrent() - keyStart) * 1000
        if storage.string.utf16.count != long.utf16.count + 1 { failures.append("long-typing") }
        window.contentView = nil
        window.close()
        debugLog("NOTCHPAD_INK_SELFTEST themes=\(themes.count) \(summary.joined(separator: " ")) typing=\(typing) "
                 + "long-load-ms=\(String(format: "%.1f", loadMs)) long-key-ms=\(String(format: "%.2f", keyMs)) "
                 + "failures=\(failures.isEmpty ? "none" : failures.joined(separator: ","))")
    }
}

/// Drag this button to move the pad. Bring it back near the notch and it snaps into the centre.
struct MoveHandle: View {
    @ObservedObject var controller: NotchController
    var color: Color
    @State private var dragging = false
    @State private var hovering = false

    var body: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 22, height: 20)
            .foregroundColor(color)
            .contentShape(Rectangle())
            .help("Drag to move. Bring it back to the notch and it snaps in.")
            .accessibilityLabel("Drag to move")
            .onHover { inside in
                guard inside != hovering else { return }
                hovering = inside
                if dragging { return }                 // the drag sorts the cursor out when it ends
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                // Closed mid-hover or mid-drag: don't leave a hand cursor pushed.
                if dragging || hovering { NSCursor.pop() }
                dragging = false; hovering = false
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    if !dragging {
                        dragging = true
                        if hovering { NSCursor.pop() }   // swap the open hand for a closed one
                        NSCursor.closedHand.push()
                    }
                    controller.moveDrag(translation: v.translation)
                }
                .onEnded { _ in
                    if dragging {
                        dragging = false
                        NSCursor.pop()
                        if hovering { NSCursor.openHand.push() }
                    }
                    controller.endMove()
                })
            .background(GeometryReader { g in
                Color.clear.onAppear {
                    // Report this button's on-screen centre (top-left origin) for the drag test.
                    let f = g.frame(in: .global), w = controller.panel.frame
                    let screenTop = controller.notch.screenFrame.maxY
                    debugLog("NOTCHPAD_MOVE_AT x=\(Int(w.minX + f.midX)) y=\(Int(screenTop - w.maxY + f.midY))")
                }
            })
    }
}

/// A boomerang: two tapered arms meeting at a rounded elbow.
struct BoomerangShape: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var p = Path()
        p.move(to: pt(0.05, 0.42))
        p.addQuadCurve(to: pt(0.72, 0.06), control: pt(0.38, 0.07))    // top edge of the long arm
        p.addQuadCurve(to: pt(0.95, 0.30), control: pt(0.96, 0.05))    // round the elbow
        p.addQuadCurve(to: pt(0.66, 0.95), control: pt(0.94, 0.64))    // outer edge of the short arm
        p.addQuadCurve(to: pt(0.50, 0.90), control: pt(0.56, 1.02))    // its tip
        p.addQuadCurve(to: pt(0.66, 0.40), control: pt(0.72, 0.60))    // inner edge, back up to the elbow
        p.addQuadCurve(to: pt(0.52, 0.32), control: pt(0.62, 0.30))
        p.addQuadCurve(to: pt(0.13, 0.56), control: pt(0.32, 0.36))    // inner edge of the long arm
        p.addQuadCurve(to: pt(0.05, 0.42), control: pt(0.00, 0.60))    // its tip
        p.closeSubpath()
        return p
    }
}

/// The icon for one of the pad's buttons, as shown on the pad and in Settings › Pad buttons.
struct PadButtonIcon: View {
    let button: PadButton
    var body: some View {
        if button == .dock {
            BoomerangShape().frame(width: 14, height: 14)
        } else {
            Image(systemName: button.symbol).font(.system(size: 11, weight: .semibold))
        }
    }
}

/// Three short diagonal lines, like a window's resize corner.
struct GripLines: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<3 {
            let o = CGFloat(i) * 4
            p.move(to: CGPoint(x: r.maxX - 2, y: r.minY + o + 2))
            p.addLine(to: CGPoint(x: r.minX + o + 2, y: r.maxY - 2))
        }
        return p
    }
}

/// Drag the bottom-right corner to resize. The new size is remembered.
struct ResizeGrip: View {
    @ObservedObject var controller: NotchController
    var color: Color

    var body: some View {
        GripLines()
            .stroke(color, lineWidth: 1.2)
            .frame(width: 12, height: 12)
            .padding(3)
        .contentShape(Rectangle())
        .help("Drag to resize")
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { _ in controller.resizeDrag() }
            .onEnded { _ in controller.endResize() })
    }
}

/// Set by the GitHub build checks: their virtual Macs have no graphics card, and SwiftUI's
/// shadow/blur effects crash without one. Never set in normal use.
let testNoEffects = ProcessInfo.processInfo.environment["NOTCHPAD_NO_EFFECTS"] != nil

struct PadShadow: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        if on { content.shadow(color: .black.opacity(0.35), radius: 14, y: 6) } else { content }
    }
}

struct PadBlur: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        if on { content.blur(radius: 9) } else { content }
    }
}
