import AppKit
import SwiftUI
import Combine

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
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "NotchPad")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open or Close Scratchpad  (⌃⌥N)", action: #selector(togglePad), keyEquivalent: "").target = self
        let pin = menu.addItem(withTitle: "Keep Open", action: #selector(togglePin), keyEquivalent: "")
        pin.target = self
        menu.addItem(withTitle: "Put Back in Notch", action: #selector(dockPad), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NotchPad", action: #selector(quit), keyEquivalent: "q").target = self
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    @objc private func togglePad() { controller.toggle() }
    @objc private func togglePin() { settings.keepOpen.toggle() }
    @objc private func dockPad() { controller.dock() }
    @objc private func openSettings() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    func showSettings() {
        if settingsWindow == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
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
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
