import AppKit
// Checks ClipboardGuard on a real Mac clipboard. Built with Sources/Clipboard.swift and Sources/Settings.swift.
func fail(_ m: String) -> Never { print("FAIL: \(m)"); exit(1) }
let pb = NSPasteboard.general
let g = ClipboardGuard.shared
let s = Settings.shared
s.clipboardClear = .thirtySeconds
s.clipboardHideFromHistory = true

// 1. Copy puts the text and the "don't save me" markers on the clipboard.
g.copy("secret note")
guard pb.string(forType: .string) == "secret note" else { fail("copy did not land") }
let types = pb.types?.map(\.rawValue) ?? []
guard types.contains("org.nspasteboard.ConcealedType") else { fail("concealed marker missing: \(types)") }
print("OK: copy + concealed marker")

// 2. Something copied from another app afterwards is never wiped.
pb.clearContents(); pb.setString("from another app", forType: .string)
g.clearIfOurs()
guard pb.string(forType: .string) == "from another app" else { fail("wiped another app's copy") }
print("OK: other app's copy left alone")

// 3. Timed clear wipes NotchPad's copy.
g.copy("secret note 2")
let start = Date()
RunLoop.main.run(until: Date().addingTimeInterval(32))
guard pb.string(forType: .string) == nil else { fail("not cleared after \(Int(Date().timeIntervalSince(start)))s") }
print("OK: cleared after 30 seconds")

// 4. Clear now wipes anything.
pb.clearContents(); pb.setString("anything", forType: .string)
g.clearNow()
guard pb.string(forType: .string) == nil else { fail("clear now did not clear") }
print("OK: clear now")
print("ALL CLIPBOARD TESTS PASSED")
