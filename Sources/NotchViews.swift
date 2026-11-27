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
        expanded ? Color(nsColor: settings.theme.background).opacity(settings.opacity) : .black
    }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(topRadius: expanded ? 12 : (controller.state == .hovering ? 6 : (controller.notch.hasNotch ? 0 : 6)),
                       bottomRadius: expanded ? 22 : (controller.state == .hovering ? 12 : 9),
                       floating: expanded && controller.showsDetached)
                .fill(fill)
                .frame(width: shapeSize.width, height: shapeSize.height)
                .shadow(color: .black.opacity(expanded ? 0.35 : 0), radius: 14, y: 6)
                .overlay(alignment: .bottomTrailing) {
                    if expanded {
                        ResizeGrip(controller: controller, color: settings.theme.secondary)
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

    private var theme: PadTheme { settings.theme }
    private var headerHeight: CGFloat { max(controller.notch.rect.height, 28) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if lock.isLocked {
                lockedView
            } else {
                PadTextView(text: $store.text,
                            font: settings.font.nsFont(size: CGFloat(settings.fontSize)),
                            textColor: theme.text,
                            spellCheck: settings.spellCheck,
                            focusToken: controller.focusToken)
                    .blur(radius: shouldBlur ? 9 : 0)
                    .animation(.easeInOut(duration: 0.2), value: shouldBlur)
                if settings.showWordCount { footer }
            }
        }
        .padding(.bottom, 10)
    }

    private var shouldBlur: Bool { settings.blurWhenAway && !controller.mouseInside }

    private var header: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                iconButton(copied ? "checkmark" : "doc.on.doc", help: "Copy everything") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                .disabled(lock.isLocked || store.text.isEmpty)
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
                if settings.lockEnabled && !lock.isLocked {
                    iconButton("lock", help: "Lock now") { lock.lock() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !controller.showsDetached {
                Color.clear.frame(width: controller.notch.rect.width + 4, height: 1)
            }

            HStack(spacing: 2) {
                iconButton(settings.keepOpen ? "pin.fill" : "pin",
                           help: settings.keepOpen ? "Stays open (click to stop)" : "Keep open",
                           tint: settings.keepOpen ? .accentColor : nil) {
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
                if controller.showsDetached {
                    iconButton("arrow.up.to.line", help: "Put back in the notch") { controller.dock() }
                }
                iconButton("gearshape", help: "Settings") { controller.openSettings() }
                iconButton("chevron.up", help: "Close (Esc)") { controller.collapse() }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: headerHeight)
        .contentShape(Rectangle())
        .help("Drag to move")
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { _ in controller.moveDrag() }
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
        tv.insertionPointColor = textColor
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

/// Drag the bottom-right corner to resize. The new size is remembered.
struct ResizeGrip: View {
    @ObservedObject var controller: NotchController
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            for i in 0..<3 {
                let o = CGFloat(i) * 4
                var p = Path()
                p.move(to: CGPoint(x: size.width - 2, y: o + 2))
                p.addLine(to: CGPoint(x: o + 2, y: size.height - 2))
                ctx.stroke(p, with: .color(color), lineWidth: 1.2)
            }
        }
        .frame(width: 12, height: 12)
        .padding(3)
        .contentShape(Rectangle())
        .help("Drag to resize")
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { _ in controller.resizeDrag() }
            .onEnded { _ in controller.endResize() })
    }
}
