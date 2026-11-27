import AppKit
import SwiftUI
import Combine

enum PadState { case collapsed, hovering, expanded }

struct NotchInfo: Equatable {
    /// The camera housing (or a virtual one on Macs without a notch), in screen coordinates.
    var rect: CGRect
    var screenFrame: CGRect
    var hasNotch: Bool
    /// Height of the strip at the top of the screen where macOS's menu bar takes the clicks.
    /// Nothing clickable may ever sit in it. Never smaller than the camera housing.
    var menuBarHeight: CGFloat

    static func current() -> NotchInfo {
        let screens = NSScreen.screens
        let screen = screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? screens.first
        guard let s = screen else {
            return NotchInfo(rect: CGRect(x: 0, y: 0, width: 190, height: 32), screenFrame: .zero, hasNotch: false, menuBarHeight: 32)
        }
        let f = s.frame
        if s.safeAreaInsets.top > 0, let left = s.auxiliaryTopLeftArea, let right = s.auxiliaryTopRightArea {
            let w = f.width - left.width - right.width
            let h = s.safeAreaInsets.top
            return NotchInfo(rect: CGRect(x: f.minX + left.width, y: f.maxY - h, width: w, height: h),
                             screenFrame: f, hasNotch: true, menuBarHeight: barHeight(of: s))
        }
        let menuBar = barHeight(of: s)
        let w: CGFloat = 190
        return NotchInfo(rect: CGRect(x: f.midX - w / 2, y: f.maxY - menuBar, width: w, height: menuBar),
                         screenFrame: f, hasNotch: false, menuBarHeight: menuBar)
    }

    /// How tall the menu bar is on this screen. On some display scalings it's a few points taller
    /// than the camera housing; when it's set to hide automatically it can't be measured, so allow a little extra.
    private static func barHeight(of s: NSScreen) -> CGFloat {
        let housing = s.safeAreaInsets.top
        let measured = s.frame.maxY - s.visibleFrame.maxY
        if measured >= 20 { return min(max(measured, housing, 24), max(housing, 24) + 40) }
        return housing > 0 ? housing + 6 : 24
    }
}

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// macOS normally pushes windows down so they sit below the menu bar. NotchPad has to
    /// live up in the menu bar, inside the camera housing, so keep the frame exactly as asked.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchController: ObservableObject {
    @Published private(set) var state: PadState = .collapsed
    @Published private(set) var mouseInside = false
    @Published private(set) var focusToken = 0
    @Published private(set) var notch: NotchInfo = NotchInfo.current()
    /// Drawn as a floating card (not a notch) — true while dragged away or when restored detached.
    @Published private(set) var showsDetached = false

    let panel = NotchPanel()
    var onOpenSettings: (() -> Void)?
    var isSettingsVisible: (() -> Bool)?

    private let settings = Settings.shared
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()
    private var collapsedAt = Date.distantPast
    private var openedByHover = false
    private var hoverOpenWork: DispatchWorkItem?
    private var leaveWork: DispatchWorkItem?
    private weak var previousApp: NSRunningApplication?

    private let margin: CGFloat = 40
    static let minSize = CGSize(width: 320, height: 170)
    static let maxSize = CGSize(width: 1100, height: 760)

    private var moveStartMouse: NSPoint?
    private var moveStartFrame = NSRect.zero
    /// True while the magnet has caught the pad and it's sitting in the notch spot.
    private var magnetLocked = false
    /// Whether the pad was drawn floating when this drag began (its content sits higher when floating).
    private var moveStartDetached = false
    private var moveMonitor: Any?
    /// Magnet field: inside `magnetReach` points the notch starts pulling; inside `magnetCatch` it snaps in.
    private let magnetReach: CGFloat = 140
    private let magnetCatch: CGFloat = 30
    private let magnetRelease: CGFloat = 58

    // Spring that moves the window smoothly every display frame.
    private var springTimer: Timer?
    private var springPos = CGPoint.zero
    private var springVel = CGVector.zero
    private var springTarget = CGPoint.zero
    private var springOmega: CGFloat = 40
    private var springZeta: CGFloat = 1
    private var springLast = CACurrentMediaTime()
    private var springDone: (() -> Void)?
    private var springStarted = CACurrentMediaTime()
    /// Spring frames since the last drag event was handled. If the button is up and nothing has arrived
    /// for a moment, the mouse-up went somewhere else (screen lock, Mission Control...) and the move is
    /// ended for you. Counted in frames, not seconds, so a busy moment can't be mistaken for silence.
    private var framesSinceDrag = 0
    /// Set when a screen change dropped a drag mid-hold: the rest of that hold is ignored.
    private var ignoreDragUntilUp = false
    private var layoutPending = false

    private var resizeStartMouse: NSPoint?
    private var resizeStartSize = CGSize.zero
    private var resizeStartLeft: CGFloat = 0

    func start() {
        let host = FirstMouseHostingView(rootView: NotchRootView(controller: self))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        layout()
        applyPrivacy()
        panel.orderFrontRegardless()

        let mouseMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] _ in self?.mouseMoved() }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mouseMask, handler: { [weak self] e in self?.mouseMoved(); return e }) { monitors.append(l) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] e in self?.globalClick(e) }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard let self = self else { return e }
            if e.keyCode == 53, self.state == .expanded { self.collapse(); return nil } // Esc
            if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "q" { NSApp.terminate(nil); return nil }
            if e.window === self.panel, self.editingShortcut(e) { return nil }
            return e
        }) { monitors.append(l) }

        settings.$keepOpen.dropFirst().sink { [weak self] on in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.settings.wasOpen = on && self.state == .expanded
            }
        }.store(in: &bag)
        settings.$customWidth.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.layout() } }.store(in: &bag)
        settings.$customHeight.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.layout() } }.store(in: &bag)
        settings.$detached.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.layout() } }.store(in: &bag)
        settings.$size.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.layout() } }.store(in: &bag)
        settings.$hideFromCapture.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.applyPrivacy() } }.store(in: &bag)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.screenChanged() }
        let lockNow: (Notification) -> Void = { [weak self] _ in
            if self?.settings.clipboardClearOnLock == true { ClipboardGuard.shared.clearIfOurs() }
            LockManager.shared.lock()
            if self?.state == .expanded, self?.settings.keepOpen == false { self?.collapse() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: lockNow)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main, using: lockNow)
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: lockNow)
    }

    /// Command-C, V, X, A and Z in the pad. NotchPad has no menu bar of its own, and on a Mac these
    /// shortcuts normally come from the Edit menu, so without this they would do nothing.
    private func editingShortcut(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection([.command, .control, .option, .shift])
        guard flags == .command || flags == [.command, .shift] else { return false }
        let key = (e.charactersIgnoringModifiers ?? "").lowercased()
        let action: Selector
        switch (key, flags == .command) {
        case ("c", true): action = #selector(NSText.copy(_:))
        case ("v", true): action = #selector(NSText.paste(_:))
        case ("x", true): action = #selector(NSText.cut(_:))
        case ("a", true): action = #selector(NSResponder.selectAll(_:))
        case ("z", true): action = Selector(("undo:"))
        case ("z", false): action = Selector(("redo:"))
        default: return false
        }
        return NSApp.sendAction(action, to: nil, from: self)
    }

    /// A display was added, removed or rescaled: drop any drag or pull in flight (its numbers belong
    /// to the old screen) and lay the pad out again for the new one.
    private func screenChanged() {
        if moveStartMouse != nil { ignoreDragUntilUp = NSEvent.pressedMouseButtons & 1 != 0 }
        moveStartMouse = nil
        if let mon = moveMonitor { NSEvent.removeMonitor(mon); moveMonitor = nil }
        magnetLocked = false
        springDone = nil
        stopSpring()
        resizeStartMouse = nil
        layout()
    }

    /// Escape hatch: back in the notch, default size, not pinned, closed.
    func resetPosition() {
        cancelMove(); resizeStartMouse = nil
        settings.resetLayout()
        settings.keepOpen = false; settings.wasOpen = false
        if state == .expanded { collapse() } else { layout() }
    }

    /// Called once at launch: forget or restore the last size/position, and reopen if it was pinned open.
    func restoreOnLaunch() {
        // Holding Option while NotchPad starts resets its position (for when it's stuck somewhere).
        if NSEvent.modifierFlags.contains(.option) { resetPosition(); return }
        if !settings.rememberLayout { settings.resetLayout() }
        if ![settings.offsetX, settings.offsetY, settings.customWidth, settings.customHeight].allSatisfy({ $0.isFinite }) {
            settings.resetLayout()
        }
        if settings.keepOpen && settings.wasOpen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.expand(byHover: false) }
        } else {
            settings.wasOpen = false
        }
    }

    // MARK: Geometry

    var padSize: CGSize {
        var size = settings.size.size
        if settings.hasCustomSize {
            size = CGSize(width: min(max(settings.customWidth, Self.minSize.width), Self.maxSize.width),
                          height: min(max(settings.customHeight, Self.minSize.height), Self.maxSize.height))
        }
        // Never bigger than the screen it's on (a large pad on a small external display).
        let sf = notch.screenFrame
        if sf.width > 0, sf.height > 0 {
            size.width = min(size.width, max(sf.width, 200))
            size.height = min(size.height, max(sf.height - notch.menuBarHeight, 120))
        }
        return size
    }

    /// Area that counts as "over the notch".
    private var hotRect: CGRect { notch.rect.insetBy(dx: -14, dy: -8) }

    /// The visible pad, in screen coordinates (always top-centred in the panel).
    private var expandedRect: CGRect {
        let s = padSize
        let f = panel.frame
        return CGRect(x: f.midX - s.width / 2, y: f.maxY - s.height, width: s.width, height: s.height)
    }

    /// Panel frame for the docked (notch) spot, or the remembered floating spot.
    private func panelFrame(floating: Bool) -> NSRect {
        let s = padSize
        let sf = notch.screenFrame
        if floating {
            let w = s.width + margin * 2
            let h = s.height + margin
            var midX = notch.rect.midX + CGFloat(settings.offsetX)
            var top = sf.maxY - CGFloat(settings.offsetY)
            // Keep the whole pad on screen, even if the display changed since last time.
            midX = min(max(midX, sf.minX + s.width / 2), sf.maxX - s.width / 2)
            // ...and never let its toolbar sit in the menu bar strip, where macOS takes the clicks
            // (older versions could save a floating spot right at the top of the screen).
            top = min(max(top, sf.minY + s.height), floatingTopLimit)
            return NSRect(x: midX - w / 2, y: top - h, width: w, height: h)
        }
        let w = max(s.width, notch.rect.width + 80) + margin * 2
        let h = s.height + margin
        return NSRect(x: notch.rect.midX - w / 2, y: sf.maxY - h, width: w, height: h)
    }

    func layout() {
        notch = NotchInfo.current()
        // A drag or a magnet pull is moving the window; it saves its own position when it lands.
        if moveStartMouse != nil || springTimer != nil { layoutPending = true; return }
        layoutPending = false
        let floating = state == .expanded && settings.detached
        showsDetached = floating
        panel.setFrame(panelFrame(floating: floating), display: true)
        if notchPadDebug {
            let f = panel.frame
            FileHandle.standardError.write("NOTCHPAD_FRAME top=\(f.maxY) screenTop=\(notch.screenFrame.maxY) notch=\(notch.rect)\n".data(using: .utf8)!)
            if state == .expanded {
                debugLog("NOTCHPAD_OPEN floating=\(floating) top=\(Int(f.maxY)) limit=\(Int(floatingTopLimit)) left=\(Int(expandedRect.minX)) right=\(Int(expandedRect.maxX)) screen=\(Int(notch.screenFrame.minX))...\(Int(notch.screenFrame.maxX))")
            }
        }
    }

    // MARK: Move and resize

    /// Called by the drag gestures. The first call starts the move; after that, every mouse event
    /// (not just the ones SwiftUI passes on) drives it, so it tracks the pointer smoothly.
    /// `translation` is how far the pointer had already travelled when the gesture was recognised
    /// (window coordinates, y down), so the pad doesn't lag behind by that much.
    func moveDrag(translation: CGSize = .zero) {
        guard state == .expanded else { return }
        if ignoreDragUntilUp {
            if NSEvent.pressedMouseButtons & 1 == 0 { ignoreDragUntilUp = false } else { return }
        }
        framesSinceDrag = 0
        // A move whose mouse-up never reached us (screen lock, Mission Control, app switch...) must not
        // block every later drag: drop it and start fresh.
        // (The spring watchdog normally ends it; if the spring isn't running, nothing else will.)
        if moveStartMouse != nil, springTimer == nil { cancelMove() }
        guard moveStartMouse == nil else { return }
        let m = NSEvent.mouseLocation
        let lead = translation.width.isFinite && translation.height.isFinite ? translation : .zero
        moveStartMouse = NSPoint(x: m.x - lead.width, y: m.y + lead.height)
        moveStartFrame = panel.frame
        moveStartDetached = showsDetached
        magnetLocked = !showsDetached
        openedByHover = false
        leaveWork?.cancel(); leaveWork = nil
        springPos = panel.frame.origin
        springVel = .zero
        springTarget = springPos
        springDone = nil
        moveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] e in
            if e.type == .leftMouseUp { self?.endMove() } else { self?.framesSinceDrag = 0; self?.dragMoved() }
            return e
        }
        startSpring()
    }

    /// Floating pads drop the menu-bar strip, so their content sits this much higher in the window.
    private var floatingShift: CGFloat { max(notch.menuBarHeight - 2, 0) }
    /// Highest a floating pad's top edge may go: its buttons must start below the menu bar,
    /// because macOS's menu bar takes every click in that strip (and the camera housing hides part of it).
    private var floatingTopLimit: CGFloat { notch.screenFrame.maxY - notch.menuBarHeight }

    /// Keeps a floating pad where every button can be reached: below the menu bar and fully on screen.
    /// `origin` is the window origin; the pad is drawn top-centred inside the window.
    private func clampFloating(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let sf = notch.screenFrame
        guard sf.width > 0, sf.height > 0 else { return origin }
        let s = padSize
        var p = origin
        let inset = (size.width - s.width) / 2                  // transparent margin each side of the pad
        p.x = max(p.x, sf.minX - inset)
        p.x = min(p.x, max(sf.maxX - s.width - inset, sf.minX - inset))
        p.y = max(p.y, sf.minY + s.height - size.height)        // bottom edge stays on screen...
        p.y = min(p.y, floatingTopLimit - size.height)          // ...but the top limit always wins
        return p
    }

    /// Moves the window to a spring position, but never draws it where its buttons can't be clicked:
    /// a floating pad stays below the menu bar and on screen, a docked one never rises past the top.
    private func present(_ p: CGPoint, rounded: Bool = false) {
        var q = rounded ? CGPoint(x: p.x.rounded(), y: p.y.rounded()) : p
        let size = panel.frame.size
        let sf = notch.screenFrame
        if showsDetached {
            q = clampFloating(q, size: size)
        } else if sf.height > 0 {
            q.y = min(q.y, sf.maxY - size.height)
        }
        // Hit a limit: stop there rather than pushing on past it.
        if abs(q.x - p.x) > 0.6 { springPos.x = q.x; springVel.dx = 0 }
        if abs(q.y - p.y) > 0.6 { springPos.y = q.y; springVel.dy = 0 }
        panel.setFrameOrigin(q)
    }

    private func dragMoved() {
        guard let m0 = moveStartMouse else { return }
        let m = NSEvent.mouseLocation
        let sf = notch.screenFrame
        var free = moveStartFrame
        free.origin.x += m.x - m0.x
        free.origin.y += m.y - m0.y
        // Keep whatever you grabbed under the pointer when the layout switches between notch and card.
        if moveStartDetached { free.origin.y += floatingShift }      // express in notch layout
        if free.maxY > sf.maxY { free.origin.y = sf.maxY - free.height }
        let home = CGPoint(x: notch.rect.midX - free.width / 2, y: sf.maxY - free.height)

        let d = distanceFromNotch(free)
        let wasLocked = magnetLocked
        magnetLocked = d < (wasLocked ? magnetRelease : magnetCatch)

        var target = free.origin
        if magnetLocked {
            target = home
        } else if d < magnetReach {
            // Smooth pull that grows as it nears the notch (no sudden step at the edge of the field).
            let t = min(max((magnetReach - d) / (magnetReach - magnetCatch), 0), 1)
            let pull = t * t * (3 - 2 * t) * 0.7
            target.x += (home.x - target.x) * pull
            target.y += (home.y - target.y) * pull
        }
        if !magnetLocked {
            target.y -= floatingShift                                 // floating layout sits lower
            target = clampFloating(target, size: free.size)
        }

        if magnetLocked != wasLocked {
            // Swap layouts and move the window by the same amount in one go, so nothing jumps.
            springPos.y += magnetLocked ? floatingShift : -floatingShift
            showsDetached = !magnetLocked
            present(springPos)
            if magnetLocked && settings.haptics {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        springTarget = target
        if magnetLocked {
            springOmega = 26; springZeta = 0.62          // caught: a quick pull with a small settle, like a magnet
        } else if d < magnetReach {
            springOmega = 34; springZeta = 0.9
        } else {
            springOmega = 55; springZeta = 1             // free: follows the pointer closely, just smoothed
        }
    }

    /// How far the pad's top-centre is from its spot in the notch, in points (notch layout).
    private func distanceFromNotch(_ f: NSRect) -> CGFloat {
        let dx = f.midX - notch.rect.midX
        let dy = notch.screenFrame.maxY - f.maxY
        return (dx * dx + dy * dy).squareRoot()
    }

    /// `trackPointer` is false when the move is ended for you (its mouse-up never arrived): the pointer
    /// may be anywhere by then, so the pad settles where it last was instead of chasing it.
    func endMove(trackPointer: Bool = true) {
        ignoreDragUntilUp = false
        guard moveStartMouse != nil else { return }
        if trackPointer { dragMoved() }   // decide from where the pointer finally is, not where the spring has got to
        moveStartMouse = nil
        springStarted = CACurrentMediaTime()
        if let mon = moveMonitor { NSEvent.removeMonitor(mon); moveMonitor = nil }
        let sf = notch.screenFrame
        let f = panel.frame
        var aim = NSRect(origin: springTarget, size: f.size)
        if showsDetached { aim.origin.y += floatingShift }           // back to notch-layout terms
        if magnetLocked || distanceFromNotch(aim) < magnetReach * 0.55 {
            magnetLocked = false
            debugLog("NOTCHPAD_DROP docked=true")
            if showsDetached {
                springPos.y += floatingShift
                showsDetached = false
                present(springPos)
            }
            // Let go near the notch: it's drawn into the exact centre.
            springTarget = CGPoint(x: notch.rect.midX - f.width / 2, y: sf.maxY - f.height)
            springOmega = 22; springZeta = 0.68
            springDone = { [weak self] in self?.dock(animated: false) }
        } else {
            magnetLocked = false
            debugLog("NOTCHPAD_DROP docked=false")
            // Glide to rest where it was let go (never under the menu bar or off screen), then remember the spot.
            springTarget = clampFloating(springTarget, size: f.size)
            springOmega = 30; springZeta = 1
            springDone = { [weak self] in
                guard let self = self else { return }
                let f = self.panel.frame
                self.settings.offsetX = Double(f.midX - self.notch.rect.midX)
                self.settings.offsetY = Double(self.notch.screenFrame.maxY - f.maxY)
                self.settings.detached = true
            }
        }
    }

    /// Stops a drag or pull in progress without saving a new spot (used when the pad closes mid-drag).
    private func cancelMove() {
        moveStartMouse = nil
        if let mon = moveMonitor { NSEvent.removeMonitor(mon); moveMonitor = nil }
        magnetLocked = false
        let done = springDone
        springDone = nil
        stopSpring()
        if done != nil { springPos = springTarget; present(springPos) }
        done?()             // a drop or dock already decided: save it rather than lose it
    }

    // MARK: Spring

    private func startSpring() {
        springLast = CACurrentMediaTime()
        springStarted = springLast
        guard springTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.springTick() }
        RunLoop.main.add(t, forMode: .common)
        springTimer = t
    }

    private func stopSpring() {
        springTimer?.invalidate()
        springTimer = nil
    }

    private func springTick() {
        let now = CACurrentMediaTime()
        var dt = min(now - springLast, 1.0 / 30.0)
        springLast = now
        let w = springOmega, z = springZeta
        // Small fixed steps keep the spring stable whatever the frame rate.
        while dt > 0 {
            let h = min(dt, 1.0 / 480.0)
            let ax = w * w * (springTarget.x - springPos.x) - 2 * z * w * springVel.dx
            let ay = w * w * (springTarget.y - springPos.y) - 2 * z * w * springVel.dy
            springVel.dx += ax * h; springVel.dy += ay * h
            springPos.x += springVel.dx * h; springPos.y += springVel.dy * h
            dt -= h
        }
        let still = abs(springTarget.x - springPos.x) < 0.3 && abs(springTarget.y - springPos.y) < 0.3
            && abs(springVel.dx) < 4 && abs(springVel.dy) < 4
        // Watchdog: the button is up but we never saw the mouse-up -> end the move here.
        if moveStartMouse != nil {
            framesSinceDrag += 1
            if framesSinceDrag > 60, NSEvent.pressedMouseButtons & 1 == 0 {
                debugLog("NOTCHPAD_MOVE_ENDED_FOR_YOU")
                endMove(trackPointer: false)
            }
        }
        // Never animate forever (NaN, a target that keeps moving...): land after 2 s without a drag.
        let stuck = moveStartMouse == nil && (now - springStarted > 2 || !springPos.x.isFinite || !springPos.y.isFinite)
        if stuck { springVel = .zero; springPos = springTarget }
        if (still || stuck) && moveStartMouse == nil {
            springPos = springTarget
            present(springPos, rounded: true)
            stopSpring()
            let done = springDone; springDone = nil
            done?()
            if layoutPending, springTimer == nil { layout() }
            return
        }
        present(springPos)
    }

    func resizeDrag() {
        guard state == .expanded else { return }
        let m = NSEvent.mouseLocation
        guard let m0 = resizeStartMouse else {
            resizeStartMouse = m
            resizeStartSize = padSize
            resizeStartLeft = expandedRect.minX
            openedByHover = false
            leaveWork?.cancel(); leaveWork = nil
            return
        }
        let dx = m.x - m0.x
        let dy = m.y - m0.y
        // Docked pads grow from the centre, so the corner follows the pointer at twice the speed.
        var w = resizeStartSize.width + (settings.detached ? dx : dx * 2)
        var h = resizeStartSize.height - dy
        w = min(max(w, Self.minSize.width), Self.maxSize.width).rounded()
        h = min(max(h, Self.minSize.height), Self.maxSize.height).rounded()
        settings.customWidth = Double(w)
        settings.customHeight = Double(h)
        if settings.detached {
            settings.offsetX = Double(resizeStartLeft + w / 2 - notch.rect.midX)   // keep the left edge still
        }
        layout()
    }

    func endResize() { resizeStartMouse = nil }

    /// Put the pad back in the notch (keeps its size).
    func dock() { dock(animated: true) }

    /// The boomerang button: the pad swings out in a curve and flies back into the notch.
    func boomerang() { dock(animated: true, boomerang: true) }

    func dock(animated: Bool, boomerang: Bool = false) {
        if moveStartMouse != nil { cancelMove() }    // "Put back in notch" must always win
        let wasDetached = showsDetached
        let saveDocked = { [weak self] in
            guard let self = self else { return }
            self.settings.detached = false
            self.settings.offsetX = 0
            self.settings.offsetY = 0
        }
        showsDetached = false
        let home = panelFrame(floating: false)
        guard state == .expanded, animated, moveStartMouse == nil else {
            stopSpring()
            saveDocked()
            if state == .expanded { panel.setFrame(home, display: true) }
            return
        }
        // Same magnet-style pull as dragging it back.
        var start = panel.frame
        if wasDetached { start.origin.y += floatingShift }
        panel.setFrame(NSRect(origin: start.origin, size: home.size), display: true)
        springPos = start.origin
        springVel = .zero
        springTarget = home.origin
        springOmega = 22; springZeta = 0.68
        if boomerang {
            // Throw it sideways as it's pulled home: the path bends into an arc, like a boomerang coming back.
            // The swing is always downward first, away from the top of the screen.
            let dx = home.origin.x - start.origin.x, dy = home.origin.y - start.origin.y
            let dist = (dx * dx + dy * dy).squareRoot()
            if dist > 40 {
                springOmega = 13
                let side: CGFloat = dx >= 0 ? 1 : -1
                let swing = min(0.75 * springOmega * dist, 7000)
                springVel = CGVector(dx: side * dy / dist * swing, dy: -side * dx / dist * swing)
                debugLog("NOTCHPAD_BOOMERANG distance=\(Int(dist))")
            }
        }
        saveDocked()            // layout() waits for the spring, so saving now can't jerk it mid-pull
        springDone = { [weak self] in self?.panel.setFrame(home, display: true) }
        startSpring()
    }

    private func applyPrivacy() {
        let testCapture = ProcessInfo.processInfo.environment["NOTCHPAD_ALLOW_CAPTURE"] != nil   // build checks only
        panel.sharingType = settings.hideFromCapture && !testCapture ? .none : .readOnly
    }

    // MARK: Mouse

    private func mouseMoved() {
        let p = NSEvent.mouseLocation
        switch state {
        case .collapsed:
            if hotRect.contains(p) { enterHover() }
        case .hovering:
            if !hotRect.contains(p) {
                hoverOpenWork?.cancel()
                state = .collapsed
            }
        case .expanded:
            let inside = expandedRect.insetBy(dx: -6, dy: -6).contains(p)
            if inside != mouseInside { mouseInside = inside }
            if openedByHover && !settings.keepOpen {
                if inside {
                    leaveWork?.cancel(); leaveWork = nil
                } else if leaveWork == nil {
                    let work = DispatchWorkItem { [weak self] in self?.collapse() }
                    leaveWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
                }
            }
        }
    }

    private func enterHover() {
        state = .hovering
        if settings.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if settings.openOnHover {
            hoverOpenWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.state == .hovering else { return }
                self.expand(byHover: true)
            }
            hoverOpenWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    private func globalClick(_ e: NSEvent) {
        let p = NSEvent.mouseLocation
        if state != .expanded {
            if hotRect.contains(p), e.type == .leftMouseDown { expand(byHover: false) }
        } else if !expandedRect.contains(p) {
            if !settings.keepOpen && settings.closeOnClickOutside { collapse(restoreFocus: false) }
        }
    }

    // MARK: Open / close

    func toggle() {
        if state == .expanded { collapse() } else { expand(byHover: false) }
    }

    func expand(byHover: Bool) {
        hoverOpenWork?.cancel()
        leaveWork?.cancel(); leaveWork = nil
        openedByHover = byHover
        if settings.lockEnabled,
           Date().timeIntervalSince(collapsedAt) >= TimeInterval(settings.lockAfter.rawValue) {
            LockManager.shared.lock()
        }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        mouseInside = true
        cancelMove()
        panel.alphaValue = 1
        state = .expanded
        layout()
        if settings.keepOpen { settings.wasOpen = true }
        panel.ignoresMouseEvents = false
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        focusToken += 1
        if LockManager.shared.isLocked { LockManager.shared.unlock() }
    }

    func collapse(restoreFocus: Bool = true) {
        guard state == .expanded else { state = .collapsed; return }
        leaveWork?.cancel(); leaveWork = nil
        NoteStore.shared.saveNow()
        cancelMove(); resizeStartMouse = nil
        settings.wasOpen = false
        let wasFloating = showsDetached
        state = .collapsed
        debugLog("NOTCHPAD_STATE=collapsed")
        if wasFloating {
            // Fade out where it floats, then tuck back into the notch.
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self = self else { return }
                if self.state != .expanded { self.layout() }
                self.panel.alphaValue = 1
            })
        } else {
            layout()
        }
        collapsedAt = Date()
        if settings.lockEnabled && settings.lockAfter == .immediately { LockManager.shared.lock() }
        panel.ignoresMouseEvents = true
        panel.resignKey()
        if restoreFocus, !(isSettingsVisible?() ?? false) {
            previousApp?.activate(options: [])
        }
        // Keep the panel visible above the menu bar.
        panel.orderFrontRegardless()
    }

    func openSettings() {
        if !settings.keepOpen { collapse(restoreFocus: false) }
        onOpenSettings?()
    }
}
