import Foundation
import CryptoKit
import Security

/// Holds the scratchpad text. Saved to disk encrypted (AES-256-GCM) with a key kept in the
/// login Keychain, readable only on this Mac. Nothing is ever sent over the network.
final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    @Published var text: String = "" {
        didSet {
            guard !isLoading, text != oldValue else { return }
            lastEdited = Date()
            scheduleSave()
        }
    }
    private(set) var lastEdited = Date()
    private var isLoading = false
    private var saveWork: DispatchWorkItem?
    private let key: SymmetricKey

    private struct Payload: Codable { var text: String; var edited: Date }

    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("NotchPad", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir
    }
    private static var fileURL: URL { folder.appendingPathComponent("note.sealed") }

    init() {
        key = NoteStore.loadOrCreateKey()
        load()
    }

    // MARK: Load / save

    private func load() {
        guard let data = try? Data(contentsOf: NoteStore.fileURL),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key),
              let payload = try? JSONDecoder().decode(Payload.self, from: plain) else { return }
        isLoading = true
        text = payload.text
        lastEdited = payload.edited
        isLoading = false
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        let url = NoteStore.fileURL
        if text.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            let plain = try JSONEncoder().encode(Payload(text: text, edited: lastEdited))
            let sealed = try AES.GCM.seal(plain, using: key)
            guard let combined = sealed.combined else { return }
            try combined.write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Deliberately silent: nothing is written to the system log, so other apps can't learn NotchPad is running.
        }
    }

    /// Wipes the note from memory and disk.
    func eraseAll() {
        saveWork?.cancel()
        isLoading = true
        text = ""
        isLoading = false
        try? FileManager.default.removeItem(at: NoteStore.fileURL)
    }

    func autoEraseIfNeeded(_ rule: AutoErase) {
        guard rule != .never, !text.isEmpty else { return }
        if Date().timeIntervalSince(lastEdited) >= TimeInterval(rule.rawValue) { eraseAll() }
    }

    // MARK: Keychain

    private static let service = "com.newzeebuild.notchpad"
    private static let account = "note-encryption-key"

    private static func loadOrCreateKey() -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "NotchPad note key",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: keyData,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess { return newKey }
        if status == errSecDuplicateItem,
           SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        // Fallback: keep the key in a private file next to the note (still never leaves this Mac).
        let keyURL = folder.appendingPathComponent("key.bin")
        if let data = try? Data(contentsOf: keyURL), data.count == 32 { return SymmetricKey(data: data) }
        try? keyData.write(to: keyURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        return newKey
    }
}
