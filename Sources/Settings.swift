import SwiftUI
import AppKit

enum PadSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
    var size: CGSize {
        switch self {
        case .small: return CGSize(width: 380, height: 210)
        case .medium: return CGSize(width: 500, height: 290)
        case .large: return CGSize(width: 640, height: 400)
        }
    }
}

enum PadFont: String, CaseIterable, Identifiable {
    case system, rounded, mono, serif
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Standard"
        case .rounded: return "Rounded"
        case .mono: return "Typewriter (monospaced)"
        case .serif: return "Book (serif)"
        }
    }
    func nsFont(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        switch self {
        case .system: return base
        case .mono: return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .rounded:
            if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
            return base
        case .serif:
            if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
            return base
        }
    }
}

enum LockAfter: Int, CaseIterable, Identifiable {
    case immediately = 0, oneMinute = 60, fiveMinutes = 300, oneHour = 3600
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .immediately: return "Every time it closes"
        case .oneMinute: return "After 1 minute closed"
        case .fiveMinutes: return "After 5 minutes closed"
        case .oneHour: return "After 1 hour closed"
        }
    }
}

enum AutoErase: Int, CaseIterable, Identifiable {
    case never = 0, oneHour = 3600, oneDay = 86400, oneWeek = 604800
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .never: return "Never"
        case .oneHour: return "1 hour after my last edit"
        case .oneDay: return "1 day after my last edit"
        case .oneWeek: return "1 week after my last edit"
        }
    }
}

/// The buttons along the top of the pad, in the order they appear. Settings and Close can't be hidden
/// (Settings is the way back in if the menu bar icon is off).
enum PadButton: String, CaseIterable, Identifiable {
    case copy, clearClipboard, erase, move, lock, pin, dock, settings, close
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .clearClipboard: return "doc.on.clipboard"
        case .erase: return "trash"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .lock: return "lock"
        case .pin: return "pin"
        case .dock: return "arrow.uturn.backward"   // drawn as a boomerang instead (see PadButtonIcon)
        case .settings: return "gearshape"
        case .close: return "chevron.up"
        }
    }
    var title: String {
        switch self {
        case .copy: return "Copy"
        case .clearClipboard: return "Clear clipboard"
        case .erase: return "Erase note"
        case .move: return "Move"
        case .lock: return "Lock now"
        case .pin: return "Keep open"
        case .dock: return "Boomerang"
        case .settings: return "Settings"
        case .close: return "Close"
        }
    }
    var detail: String {
        switch self {
        case .copy: return "Copies the whole note. The clipboard clears itself afterwards, as set under Clipboard."
        case .clearClipboard: return "Click twice to wipe the clipboard, whatever app it came from."
        case .erase: return "Click twice to erase the note. It can't be undone."
        case .move: return "Drag to move the pad anywhere. Bring it back to the notch and it snaps into the centre."
        case .lock: return "Hides the note until Touch ID or your password. Only shown when Lock with Touch ID is on."
        case .pin: return "Keeps the pad open until you close it."
        case .dock: return "Flies a moved pad back into the notch, like a boomerang. Only shown while it's been moved."
        case .settings: return "Opens these settings. Always shown, so you can't lock yourself out."
        case .close: return "Tucks the pad back into the notch. Esc does the same. Always shown."
        }
    }
    var canHide: Bool { self != .settings && self != .close }
}

/// All user options, saved in UserDefaults (on this Mac only).
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    // Behaviour
    @Published var keepOpen: Bool { didSet { d.set(keepOpen, forKey: "keepOpen") } }
    @Published var openOnHover: Bool { didSet { d.set(openOnHover, forKey: "openOnHover") } }
    @Published var hoverNudge: Bool { didSet { d.set(hoverNudge, forKey: "hoverNudge") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    @Published var closeOnClickOutside: Bool { didSet { d.set(closeOnClickOutside, forKey: "closeOnClickOutside") } }
    @Published var hotkeyEnabled: Bool { didSet { d.set(hotkeyEnabled, forKey: "hotkeyEnabled") } }
    @Published var showMenuBarIcon: Bool { didSet { d.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }

    // Look
    @Published var size: PadSize { didSet { d.set(size.rawValue, forKey: "size") } }
    @Published var font: PadFont { didSet { d.set(font.rawValue, forKey: "font") } }
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize") } }
    /// Theme used when not following light/dark mode. Saved under the old "theme" key so earlier picks carry over.
    @Published var themeID: String { didSet { d.set(themeID, forKey: "theme") } }
    @Published var themeFollowsSystem: Bool { didSet { d.set(themeFollowsSystem, forKey: "themeFollowsSystem") } }
    @Published var lightThemeID: String { didSet { d.set(lightThemeID, forKey: "lightTheme") } }
    @Published var darkThemeID: String { didSet { d.set(darkThemeID, forKey: "darkTheme") } }
    @Published var opacity: Double { didSet { d.set(opacity, forKey: "opacity") } }
    @Published var showWordCount: Bool { didSet { d.set(showWordCount, forKey: "showWordCount") } }

    // Size and position (remembered across restarts)
    @Published var rememberLayout: Bool { didSet { d.set(rememberLayout, forKey: "rememberLayout") } }
    @Published var customWidth: Double { didSet { d.set(customWidth, forKey: "customWidth") } }
    @Published var customHeight: Double { didSet { d.set(customHeight, forKey: "customHeight") } }
    /// True when the pad has been dragged away from the notch.
    @Published var detached: Bool { didSet { d.set(detached, forKey: "detached") } }
    /// Offset of the pad's top-centre from the notch's top-centre, in points (y grows downward).
    @Published var offsetX: Double { didSet { d.set(offsetX, forKey: "offsetX") } }
    @Published var offsetY: Double { didSet { d.set(offsetY, forKey: "offsetY") } }
    /// Whether the pad was open (and pinned) when the app last quit.
    @Published var wasOpen: Bool { didSet { d.set(wasOpen, forKey: "wasOpen") } }

    // Privacy
    @Published var hideFromCapture: Bool { didSet { d.set(hideFromCapture, forKey: "hideFromCapture") } }
    @Published var lockEnabled: Bool { didSet { d.set(lockEnabled, forKey: "lockEnabled") } }
    @Published var lockAfter: LockAfter { didSet { d.set(lockAfter.rawValue, forKey: "lockAfter") } }
    @Published var blurWhenAway: Bool { didSet { d.set(blurWhenAway, forKey: "blurWhenAway") } }
    @Published var autoErase: AutoErase { didSet { d.set(autoErase.rawValue, forKey: "autoErase") } }
    @Published var spellCheck: Bool { didSet { d.set(spellCheck, forKey: "spellCheck") } }

    // Pad buttons
    @Published var hiddenButtons: Set<String> { didSet { d.set(Array(hiddenButtons).sorted(), forKey: "hiddenButtons") } }
    func shows(_ b: PadButton) -> Bool { !b.canHide || !hiddenButtons.contains(b.rawValue) }
    func setShows(_ b: PadButton, _ on: Bool) {
        guard b.canHide else { return }
        if on { hiddenButtons.remove(b.rawValue) } else { hiddenButtons.insert(b.rawValue) }
    }

    // Clipboard
    @Published var clipboardClear: ClipboardClear { didSet { d.set(clipboardClear.rawValue, forKey: "clipboardClear") } }
    @Published var clipboardClearOnLock: Bool { didSet { d.set(clipboardClearOnLock, forKey: "clipboardClearOnLock") } }
    @Published var clipboardThisMacOnly: Bool { didSet { d.set(clipboardThisMacOnly, forKey: "clipboardThisMacOnly") } }
    @Published var clipboardHideFromHistory: Bool { didSet { d.set(clipboardHideFromHistory, forKey: "clipboardHideFromHistory") } }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "keepOpen": false, "openOnHover": false, "hoverNudge": true, "haptics": true,
            "closeOnClickOutside": true, "hotkeyEnabled": true, "showMenuBarIcon": true,
            "size": PadSize.medium.rawValue, "font": PadFont.system.rawValue, "fontSize": 14.0,
            "theme": "notch", "themeFollowsSystem": false, "lightTheme": "paper", "darkTheme": "notch", "opacity": 1.0, "showWordCount": true,
            "hideFromCapture": true, "lockEnabled": false, "lockAfter": LockAfter.fiveMinutes.rawValue,
            "rememberLayout": true, "customWidth": 0.0, "customHeight": 0.0, "detached": false,
            "offsetX": 0.0, "offsetY": 0.0, "wasOpen": false,
            "blurWhenAway": false, "autoErase": AutoErase.never.rawValue, "spellCheck": false,
            "clipboardClear": ClipboardClear.oneMinute.rawValue, "clipboardClearOnLock": true,
            "clipboardThisMacOnly": true, "clipboardHideFromHistory": true,
            "hiddenButtons": [String](),
        ])
        keepOpen = d.bool(forKey: "keepOpen")
        openOnHover = d.bool(forKey: "openOnHover")
        hoverNudge = d.bool(forKey: "hoverNudge")
        haptics = d.bool(forKey: "haptics")
        closeOnClickOutside = d.bool(forKey: "closeOnClickOutside")
        hotkeyEnabled = d.bool(forKey: "hotkeyEnabled")
        showMenuBarIcon = d.bool(forKey: "showMenuBarIcon")
        size = PadSize(rawValue: d.string(forKey: "size") ?? "") ?? .medium
        font = PadFont(rawValue: d.string(forKey: "font") ?? "") ?? .system
        fontSize = d.double(forKey: "fontSize")
        themeID = d.string(forKey: "theme") ?? "notch"
        themeFollowsSystem = d.bool(forKey: "themeFollowsSystem")
        lightThemeID = d.string(forKey: "lightTheme") ?? "paper"
        darkThemeID = d.string(forKey: "darkTheme") ?? "notch"
        opacity = d.double(forKey: "opacity")
        showWordCount = d.bool(forKey: "showWordCount")
        rememberLayout = d.bool(forKey: "rememberLayout")
        customWidth = d.double(forKey: "customWidth")
        customHeight = d.double(forKey: "customHeight")
        detached = d.bool(forKey: "detached")
        offsetX = d.double(forKey: "offsetX")
        offsetY = d.double(forKey: "offsetY")
        wasOpen = d.bool(forKey: "wasOpen")
        hideFromCapture = d.bool(forKey: "hideFromCapture")
        lockEnabled = d.bool(forKey: "lockEnabled")
        lockAfter = LockAfter(rawValue: d.integer(forKey: "lockAfter")) ?? .fiveMinutes
        blurWhenAway = d.bool(forKey: "blurWhenAway")
        autoErase = AutoErase(rawValue: d.integer(forKey: "autoErase")) ?? .never
        spellCheck = d.bool(forKey: "spellCheck")
        clipboardClear = ClipboardClear(rawValue: d.integer(forKey: "clipboardClear")) ?? .oneMinute
        clipboardClearOnLock = d.bool(forKey: "clipboardClearOnLock")
        clipboardThisMacOnly = d.bool(forKey: "clipboardThisMacOnly")
        clipboardHideFromHistory = d.bool(forKey: "clipboardHideFromHistory")
        hiddenButtons = Set(d.stringArray(forKey: "hiddenButtons") ?? [])
    }

    func resetToDefaults() {
        for key in ["keepOpen", "openOnHover", "hoverNudge", "haptics", "closeOnClickOutside", "hotkeyEnabled",
                    "showMenuBarIcon", "size", "font", "fontSize", "theme", "themeFollowsSystem", "lightTheme", "darkTheme", "opacity", "showWordCount",
                    "hideFromCapture", "lockEnabled", "lockAfter", "blurWhenAway", "autoErase", "spellCheck",
                    "clipboardClear", "clipboardClearOnLock", "clipboardThisMacOnly", "clipboardHideFromHistory", "hiddenButtons",
                    "rememberLayout", "customWidth", "customHeight", "detached", "offsetX", "offsetY"] {
            d.removeObject(forKey: key)
        }
        let fresh = Settings()
        keepOpen = fresh.keepOpen; openOnHover = fresh.openOnHover; hoverNudge = fresh.hoverNudge
        haptics = fresh.haptics; closeOnClickOutside = fresh.closeOnClickOutside
        hotkeyEnabled = fresh.hotkeyEnabled; showMenuBarIcon = fresh.showMenuBarIcon
        size = fresh.size; font = fresh.font; fontSize = fresh.fontSize; themeID = fresh.themeID
        themeFollowsSystem = fresh.themeFollowsSystem; lightThemeID = fresh.lightThemeID; darkThemeID = fresh.darkThemeID
        opacity = fresh.opacity; showWordCount = fresh.showWordCount; hideFromCapture = fresh.hideFromCapture
        lockEnabled = fresh.lockEnabled; lockAfter = fresh.lockAfter; blurWhenAway = fresh.blurWhenAway
        autoErase = fresh.autoErase; spellCheck = fresh.spellCheck
        clipboardClear = fresh.clipboardClear; clipboardClearOnLock = fresh.clipboardClearOnLock
        clipboardThisMacOnly = fresh.clipboardThisMacOnly; clipboardHideFromHistory = fresh.clipboardHideFromHistory
        hiddenButtons = fresh.hiddenButtons
        rememberLayout = fresh.rememberLayout
        resetLayout()
    }

    var hasCustomSize: Bool { customWidth > 0 && customHeight > 0 }

    /// Back to the preset size, docked in the notch.
    func resetLayout() {
        customWidth = 0; customHeight = 0
        detached = false; offsetX = 0; offsetY = 0
    }
}
