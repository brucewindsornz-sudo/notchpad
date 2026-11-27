import AppKit
import SwiftUI
import Combine

enum PadState { case collapsed, hovering, expanded }

struct NotchInfo: Equatable {
    /// The camera housing (or a virtual one on Macs without a notch), in screen coordinates.
    var rect: CGRect
    var screenFrame: CGRect
    var hasNotch: Bool

    static func current() -> NotchInfo {
        let screens = NSScreen.screens
        let screen = screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? screens.first
        guard let s = screen else {
            return NotchInfo(rect: CGRect(x: 0, y: 0, width: 190, height: 32), screenFrame: .zero, hasNotch: false)
        }
        let f = s.frame
        if s.safeAreaInsets.top > 0, let left = s.auxiliaryTopLeftArea, let right = s.auxiliaryTopRightArea {
            let w = f.width - left.width - right.width
            let h = s.safeAreaInsets.top
            return NotchInfo(rect: CGRect(x: f.minX + left.width, y: f.maxY - h, width: w, height: h),
                             screenFrame: f, hasNotch: true)
        }
        let menuBar = max(f.maxY - s.visibleFrame.maxY, 24)
        let w: CGFloat = 190
        return NotchInfo(rect: CGRect(x: f.midX - w / 2, y: f.maxY - menuBar, width: w, height: menuBar),
                         screenFrame: f, hasNotch: false)
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
                                               object: nil, queue: .main) { [weak self] _ in self?.layout() }
        let lockNow: (Notification) -> Void = { [weak self] _ in
            LockManager.shared.lock()
            if self?.state == .expanded, self?.settings.keepOpen == false { self?.collapse() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: lockNow)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main, using: lockNow)
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: lockNow)
    }

    /// Called once at launch: forget or restore the last size/position, and reopen if it was pinned open.
    func restoreOnLaunch() {
        if !settings.rememberLayout { settings.resetLayout() }
        if settings.keepOpen && settings.wasOpen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.expand(byHover: false) }
        } else {
            settings.wasOpen = false
        }
    }

    // MARK: Geometry

    var padSize: CGSize {
        if settings.hasCustomSize {
            return CGSize(width: min(max(settings.customWidth, Self.minSize.width), Self.maxSize.width),
                          height: min(max(settings.customHeight, Self.minSize.height), Self.maxSize.height))
        }
        return settings.size.size
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
            top = min(max(top, sf.minY + s.height), sf.maxY)
            return NSRect(x: midX - w / 2, y: top - h, width: w, height: h)
        }
        let w = max(s.width, notch.rect.width + 80) + margin * 2
        let h = s.height + margin
        return NSRect(x: notch.rect.midX - w / 2, y: sf.maxY - h, width: w, height: h)
    }

    func layout() {
        notch = NotchInfo.current()
        let floating = state == .expanded && settings.detached
        showsDetached = floating
        panel.setFrame(panelFrame(floating: floating), display: true)
        if notchPadDebug {
            let f = panel.frame
            FileHandle.standardError.write("NOTCHPAD_FRAME top=\(f.maxY) screenTop=\(notch.screenFrame.maxY) notch=\(notch.rect)\n".data(using: .utf8)!)
        }
    }

    // MARK: Move and resize

    func moveDrag() {
        guard state == .expanded else { return }
        let m = NSEvent.mouseLocation
        guard let m0 = moveStartMouse else {
            moveStartMouse = m
            moveStartFrame = panel.frame
            openedByHover = false
            leaveWork?.cancel(); leaveWork = nil
            return
        }
        var f = moveStartFrame
        f.origin.x += m.x - m0.x
        f.origin.y += m.y - m0.y
        let sf = notch.screenFrame
        if f.maxY > sf.maxY { f.origin.y = sf.maxY - f.height }
        panel.setFrame(f, display: true)
        let dx = f.midX - notch.rect.midX
        let dy = sf.maxY - f.maxY
        let away = abs(dx) > 8 || dy > 8
        if away != showsDetached { showsDetached = away }
    }

    func endMove() {
        guard moveStartMouse != nil else { return }
        moveStartMouse = nil
        let f = panel.frame
        let dx = f.midX - notch.rect.midX
        let dy = notch.screenFrame.maxY - f.maxY
        if abs(dx) < 60 && dy < 36 {
            dock()                    // close enough: snap back into the notch
        } else {
            settings.offsetX = Double(dx)
            settings.offsetY = Double(dy)
            settings.detached = true
        }
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
    func dock() {
        settings.detached = false
        settings.offsetX = 0
        settings.offsetY = 0
        showsDetached = false
        guard state == .expanded else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panel.animator().setFrame(panelFrame(floating: false), display: true)
        }
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
        moveStartMouse = nil; resizeStartMouse = nil
        settings.wasOpen = false
        let wasFloating = showsDetached
        state = .collapsed
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
