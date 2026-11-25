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
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchController: ObservableObject {
    @Published private(set) var state: PadState = .collapsed
    @Published private(set) var mouseInside = false
    @Published private(set) var focusToken = 0
    @Published private(set) var notch: NotchInfo = NotchInfo.current()

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

    // MARK: Geometry

    var padSize: CGSize { settings.size.size }

    /// Area that counts as "over the notch".
    private var hotRect: CGRect { notch.rect.insetBy(dx: -14, dy: -8) }

    private var expandedRect: CGRect {
        let s = padSize
        return CGRect(x: notch.rect.midX - s.width / 2, y: notch.screenFrame.maxY - s.height, width: s.width, height: s.height)
    }

    func layout() {
        notch = NotchInfo.current()
        let s = padSize
        let w = max(s.width, notch.rect.width + 80) + margin * 2
        let h = s.height + margin
        let frame = NSRect(x: notch.rect.midX - w / 2, y: notch.screenFrame.maxY - h, width: w, height: h)
        panel.setFrame(frame, display: true)
    }

    private func applyPrivacy() {
        panel.sharingType = settings.hideFromCapture ? .none : .readOnly
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

    func toggle() { state == .expanded ? collapse() : expand(byHover: false) }

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
        state = .collapsed
        collapsedAt = Date()
        if settings.lockEnabled && settings.lockAfter == .immediately { LockManager.shared.lock() }
        panel.ignoresMouseEvents = true
        panel.resignKey()
        if restoreFocus, !(isSettingsVisible?() ?? false) {
            previousApp?.activate()
        }
        // Keep the panel visible above the menu bar.
        panel.orderFrontRegardless()
    }

    func openSettings() {
        if !settings.keepOpen { collapse(restoreFocus: false) }
        onOpenSettings?()
    }
}
