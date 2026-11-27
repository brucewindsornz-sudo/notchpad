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
        .animation(.spring(response: 0.34, dampingFraction: 0.76), value: controller.state)
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
            } else {
                PadTextView(text: $store.text,
                            font: settings.font.nsFont(size: CGFloat(settings.fontSize)),
                            textColor: theme.text,
                            accentColor: theme.accent,
                            selectionColor: theme.selection,
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
struct PadTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor
    var accentColor: NSColor
    var selectionColor: NSColor
    var spellCheck: Bool
    var focusToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        if let tv = scroll.documentView as? NSTextView {
            tv.delegate = context.coordinator
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
            tv.string = text
            apply(to: tv)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        apply(to: tv)
        if context.coordinator.lastFocus != focusToken {
            context.coordinator.lastFocus = focusToken
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
    }

    private func apply(to tv: NSTextView) {
        if tv.font != font { tv.font = font }
        tv.textColor = textColor
        tv.insertionPointColor = accentColor
        tv.selectedTextAttributes = [.backgroundColor: selectionColor, .foregroundColor: textColor]
        tv.typingAttributes = [.font: font, .foregroundColor: textColor]
        if tv.isContinuousSpellCheckingEnabled != spellCheck { tv.isContinuousSpellCheckingEnabled = spellCheck }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PadTextView
        var lastFocus = -1
        init(_ parent: PadTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
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
