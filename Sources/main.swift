import AppKit
import SwiftUI
import Combine

/// Test hooks, only active when NOTCHPAD_DEBUG is set (used by the GitHub build checks).
let notchPadDebug = ProcessInfo.processInfo.environment["NOTCHPAD_DEBUG"] != nil
func debugLog(_ message: String) {
    guard notchPadDebug else { return }
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = NotchController()
    private let settings = Settings.shared
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var bag = Set<AnyCancellable>()
    private var eraseTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NoteStore.shared.autoEraseIfNeeded(settings.autoErase)

        controller.onOpenSettings = { [weak self] in self?.showSettings() }
        controller.isSettingsVisible = { [weak self] in self?.settingsWindow?.isVisible ?? false }
        controller.start()
        NotchActions.dock = { [weak self] in self?.controller.dock() }
        controller.restoreOnLaunch()
        if notchPadDebug {
            settings.$keepOpen.dropFirst().sink { on in debugLog("NOTCHPAD_PIN=\(on)") }.store(in: &bag)
            if ProcessInfo.processInfo.environment["NOTCHPAD_DEBUG_SETTINGS"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.showSettings() }
            }
            if ProcessInfo.processInfo.environment["NOTCHPAD_DEBUG_OPEN"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.controller.expand(byHover: false) }
            }
        }

        hotKey = HotKey { [weak self] in self?.controller.toggle() }
        settings.$hotkeyEnabled.sink { [weak self] on in
            DispatchQueue.main.async {
                if on { self?.hotKey?.register() } else { self?.hotKey?.unregister() }
            }
        }.store(in: &bag)
        settings.$showMenuBarIcon.sink { [weak self] on in
            DispatchQueue.main.async { self?.updateStatusItem(on) }
        }.store(in: &bag)
        settings.$lockEnabled.dropFirst().sink { on in
            if !on { DispatchQueue.main.async { LockManager.shared.isLocked = false } }
        }.store(in: &bag)

        eraseTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            NoteStore.shared.autoEraseIfNeeded(self.settings.autoErase)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoteStore.shared.saveNow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func updateStatusItem(_ show: Bool) {
        if !show {
            if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = AppDelegate.menuBarIcon()
        let menu = NSMenu()
        menu.addItem(withTitle: "Open or Close Scratchpad  (⌃⌥N)", action: #selector(togglePad), keyEquivalent: "").target = self
        let pin = menu.addItem(withTitle: "Keep Open", action: #selector(togglePin), keyEquivalent: "")
        pin.target = self
        menu.addItem(withTitle: "Put Back in Notch", action: #selector(dockPad), keyEquivalent: "").target = self
        let themeItem = menu.addItem(withTitle: "Theme", action: nil, keyEquivalent: "")
        themeItem.submenu = NSMenu(title: "Theme")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NotchPad", action: #selector(quit), keyEquivalent: "q").target = self
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Menu bar icon: a little notepad with a notch cut into its top edge (adapts to light/dark).
    static func menuBarIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let body = NSBezierPath(roundedRect: NSRect(x: 2, y: 1.5, width: 14, height: 13), xRadius: 3, yRadius: 3)
            body.lineWidth = 1.4
            body.stroke()
            // The notch, hanging from the top edge.
            let notch = NSBezierPath(roundedRect: NSRect(x: 6.5, y: 10.5, width: 5, height: 4.6), xRadius: 1.4, yRadius: 1.4)
            notch.fill()
            // Text lines.
            for (i, w) in [8.0, 6.0, 7.0].enumerated() {
                let line = NSBezierPath(roundedRect: NSRect(x: 5, y: 7.4 - Double(i) * 2.4, width: w, height: 1.2), xRadius: 0.6, yRadius: 0.6)
                line.fill()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "NotchPad"
        return img
    }

    @objc private func togglePad() { controller.toggle() }
    @objc private func togglePin() { settings.keepOpen.toggle() }
    @objc private func dockPad() { controller.dock() }
    @objc private func pickTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ThemeStore.shared.choose(ThemeStore.shared.theme(id: id))
    }
    @objc private func importThemes() { ThemeStore.shared.presentImportPanel() }
    @objc private func openSettings() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    func showSettings() {
        if settingsWindow == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 760),
                               styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            win.title = "NotchPad Settings"
            win.contentViewController = NSHostingController(rootView: SettingsView())
            win.isReleasedWhenClosed = false
            win.center()
            settingsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menu.item(withTitle: "Keep Open")?.state = settings.keepOpen ? .on : .off
        if let sub = menu.item(withTitle: "Theme")?.submenu {
            sub.removeAllItems()
            let store = ThemeStore.shared
            let current = store.current.id
            for t in store.all {
                let item = sub.addItem(withTitle: t.name, action: #selector(pickTheme(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = t.id
                item.state = t.id == current ? .on : .off
            }
            sub.addItem(.separator())
            sub.addItem(withTitle: "Import Theme Files…", action: #selector(importThemes), keyEquivalent: "").target = self
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
