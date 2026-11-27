import Foundation
import Combine

// Terminal mode: an optional command line in the pad.
//
// NotchPad itself stays locked down (App Sandbox, no network). macOS has one sanctioned way for a
// locked-down app to run something outside its sandbox: a script that YOU have put in the app's
// "Application Scripts" folder. NotchPad can read that folder but can't write to it, so it can't
// switch this on by itself. The script is the add-on, `notchpad-run`; this file hands it one
// command at a time and reads back what it prints.

enum AddOnStatus: Equatable { case notInstalled, needsUpdate, ready }

/// Whether the user has installed the runner script, and the commands to install or remove it.
final class TerminalAddOn: ObservableObject {
    static let shared = TerminalAddOn()
    @Published private(set) var status: AddOnStatus = .notInstalled

    static let scriptName = "notchpad-run"

    init() { status = TerminalAddOn.check() }

    /// Your real home folder (inside the sandbox, "home" otherwise means NotchPad's own container).
    static let realHome: String = {
        if let record = getpwuid(getuid()), let dir = record.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }()

    /// The copy of the add-on that came inside this version of NotchPad.
    static var bundledFolder: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("TerminalAddOn", isDirectory: true)
    }

    /// The one folder macOS will run scripts from for this app. Only you can put things in it.
    static var scriptsFolder: URL {
        if let url = try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: false) {
            return url
        }
        let id = Bundle.main.bundleIdentifier ?? "com.newzeebuild.notchpad"
        return URL(fileURLWithPath: realHome, isDirectory: true)
            .appendingPathComponent("Library/Application Scripts/\(id)", isDirectory: true)
    }

    static var scriptURL: URL { scriptsFolder.appendingPathComponent(scriptName) }

    /// Looks again in the Application Scripts folder. Cheap. Call when a view appears and from "Check again".
    func refresh() {
        let now = TerminalAddOn.check()
        if now != status { status = now }
    }

    /// Ready only when the installed script is exactly the one this version of NotchPad came with.
    private static func check() -> AddOnStatus {
        let installed = scriptURL
        guard let have = try? Data(contentsOf: installed) else { return .notInstalled }
        guard let folder = bundledFolder,
              let want = try? Data(contentsOf: folder.appendingPathComponent(scriptName)) else { return .needsUpdate }
        guard have == want else { return .needsUpdate }
        let attributes = try? FileManager.default.attributesOfItem(atPath: installed.path)
        let mode = (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0
        return mode & 0o100 != 0 ? .ready : .needsUpdate
    }

    /// One line to paste into Terminal: installs or updates the add-on from the copy inside this app.
    var installCommand: String {
        let fallback = "/Applications/NotchPad.app/Contents/Resources/TerminalAddOn/install.sh"
        let path = TerminalAddOn.bundledFolder?.appendingPathComponent("install.sh").path ?? fallback
        return "/bin/sh " + TerminalAddOn.shellQuoted(path)
    }

    /// One line to paste into Terminal: removes the add-on.
    var removeCommand: String { installCommand + " --remove" }

    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// One command and what it printed.
struct TerminalEntry: Identifiable, Equatable {
    let id: Int
    let command: String
    /// Where it ran, shortened for display, e.g. "~/Projects".
    let directory: String
    /// Cleaned text so far: no escape codes, "\n" line ends. May be empty.
    var output: String
    /// nil while it is still running. Below zero means NotchPad couldn't run it at all (see `note`).
    var exitStatus: Int?
    /// Ended with the Stop button.
    var stopped: Bool
    /// A line from NotchPad itself, e.g. "Earlier output was dropped (too long)."
    var note: String?
    var isRunning: Bool { exitStatus == nil }
}

/// Turns the raw bytes a command prints into plain text for the pad: decodes UTF-8, drops colour and
/// cursor codes, and treats carriage returns and backspaces the way a terminal would show them.
struct TerminalOutputCleaner {
    /// The most text kept for one command; the oldest goes first.
    static let limit = 200_000

    private(set) var scalars: [Unicode.Scalar] = []
    private(set) var droppedEarlier = false
    private var waiting: [UInt8] = []          // the start of a character whose remaining bytes haven't arrived yet
    private var lineStart = 0                  // where the current line begins in `scalars`
    private var sawReturn = false
    private enum Escape { case none, started, csi, text, textEscape, charset }
    private var escape = Escape.none

    var text: String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    mutating func add(_ data: Data) {
        waiting.append(contentsOf: data)
        let ready = TerminalOutputCleaner.completePrefix(of: waiting)
        guard ready > 0 else { return }
        let chunk = String(decoding: waiting[0..<ready], as: UTF8.self)
        waiting.removeFirst(ready)
        for scalar in chunk.unicodeScalars { feed(scalar) }
        trim()
    }

    /// How many leading bytes can be decoded now: all of them, unless a multi-byte character is cut off at the end.
    private static func completePrefix(of bytes: [UInt8]) -> Int {
        let count = bytes.count
        var index = count - 1
        var steps = 0
        while index >= 0 && steps < 4 {
            let byte = bytes[index]
            if byte & 0b1100_0000 == 0b1000_0000 {          // a continuation byte: its first byte is further back
                index -= 1
                steps += 1
                continue
            }
            if byte & 0b1000_0000 == 0 { return count }     // plain ASCII: nothing is cut off
            let needed = byte >= 0xF0 ? 4 : (byte >= 0xE0 ? 3 : 2)
            return count - index >= needed ? count : index
        }
        return count
    }

    private mutating func feed(_ scalar: Unicode.Scalar) {
        let v = scalar.value
        if escape != .none {
            // A new line always ends a code, so a broken one can't swallow the rest of the output.
            if v == 0x0A { escape = .none } else { skipEscape(v); return }
        }
        if v == 0x1B { escape = .started; return }
        switch v {
        case 0x0A:
            sawReturn = false                               // return then new line is just a new line
            scalars.append(scalar)
            lineStart = scalars.count
        case 0x0D:
            sawReturn = true
        case 0x08:
            overwriteAfterReturn()
            if scalars.count > lineStart { scalars.removeLast() }
        case 0x00...0x1F, 0x7F...0x9F:
            if v == 0x09 { overwriteAfterReturn(); scalars.append(scalar) }   // tabs are kept; other control characters show nothing
        default:
            overwriteAfterReturn()
            scalars.append(scalar)
        }
    }

    /// A return on its own (progress bars): the next thing printed overwrites the current line.
    private mutating func overwriteAfterReturn() {
        guard sawReturn else { return }
        sawReturn = false
        scalars.removeSubrange(lineStart...)
    }

    /// The command has ended: show any bytes still waiting for the rest of a character.
    mutating func finish() {
        guard !waiting.isEmpty else { return }
        let chunk = String(decoding: waiting, as: UTF8.self)
        waiting.removeAll()
        for scalar in chunk.unicodeScalars { feed(scalar) }
        trim()
    }

    /// Walks through one escape code (colours, cursor moves, window titles) without keeping any of it.
    private mutating func skipEscape(_ v: UInt32) {
        switch escape {
        case .started:
            if v == 0x5B { escape = .csi }                                   // ESC [ ... : colours, cursor
            else if v == 0x5D || v == 0x50 || v == 0x58 || v == 0x5E || v == 0x5F { escape = .text }   // ESC ] ... : titles and the like
            else if v >= 0x20 && v <= 0x2F { escape = .charset }             // ESC ( B and friends
            else { escape = .none }                                          // a two-character code
        case .csi:
            if v >= 0x40 && v <= 0x7E { escape = .none }
        case .text:
            if v == 0x07 { escape = .none } else if v == 0x1B { escape = .textEscape }
        case .textEscape:
            escape = v == 0x5C ? .none : .text
        case .charset:
            if !(v >= 0x20 && v <= 0x2F) { escape = .none }
        case .none:
            break
        }
    }

    private mutating func trim() {
        let limit = TerminalOutputCleaner.limit
        guard scalars.count > limit else { return }
        // Drop a good chunk in one go so this stays rare, and cut at a line end where one is close.
        var cut = scalars.count - (limit / 4) * 3
        if let lineEnd = scalars[cut...].firstIndex(where: { $0.value == 0x0A }), lineEnd - cut < 4_000 {
            cut = lineEnd + 1
        }
        scalars.removeFirst(cut)
        lineStart = max(lineStart - cut, 0)
        droppedEarlier = true
    }
}

/// One run of the add-on script. macOS runs it outside NotchPad's sandbox (that is what NSUserUnixTask
/// is for); NotchPad passes it the command and reads back what it prints, nothing more.
final class TerminalCommandRun {
    private let task: NSUserUnixTask
    private let input = Pipe()       // held open while the command should run; closing it tells the add-on to stop
    private let output = Pipe()      // everything the command prints
    private let control = Pipe()     // the add-on's own report: exit status and the directory it ended in
    private let queue = DispatchQueue(label: "com.newzeebuild.notchpad.terminal")
    private var outputSource: DispatchSourceRead?
    private var controlSource: DispatchSourceRead?
    private var report = Data()
    private var inputClosed = false
    /// The add-on's report is a few short lines; anything beyond this is ignored.
    private static let reportLimit = 16_384
    /// The most collected after the command ends (something it left running may print for ever).
    private static let lastReadLimit = 4_194_304

    init(script: URL) throws {
        task = try NSUserUnixTask(url: script)
    }

    /// Starts the script. `onOutput` and then `onEnd` are called on a private queue, in order.
    func start(arguments: [String],
               onOutput: @escaping (Data) -> Void,
               onEnd: @escaping (_ report: Data, _ error: Error?) -> Void) {
        task.standardInput = input.fileHandleForReading
        task.standardOutput = output.fileHandleForWriting
        task.standardError = control.fileHandleForWriting

        let outputFD = output.fileHandleForReading.fileDescriptor
        let controlFD = control.fileHandleForReading.fileDescriptor
        for fd in [outputFD, controlFD] {
            let flags = fcntl(fd, F_GETFL)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
        outputSource = makeSource(outputFD, keeping: output) { data in onOutput(data) }
        controlSource = makeSource(controlFD, keeping: control) { [weak self] data in self?.addToReport(data) }

        task.execute(withArguments: arguments) { [self] error in
            queue.async { [self] in
                // The script has ended: collect whatever is still in the pipes, then let go of them.
                // (Not "read until the pipe closes": something the command left running may still hold it.)
                TerminalCommandRun.drain(outputFD, limit: TerminalCommandRun.lastReadLimit) { data in onOutput(data) }
                TerminalCommandRun.drain(controlFD, limit: TerminalCommandRun.reportLimit) { data in addToReport(data) }
                outputSource?.cancel()
                controlSource?.cancel()
                outputSource = nil
                controlSource = nil
                closeInput()
                try? output.fileHandleForWriting.close()
                try? control.fileHandleForWriting.close()
                onEnd(report, error)
            }
        }
    }

    /// Asks the add-on to stop the command (it sees its input close, then ends the whole process tree).
    func stop() {
        queue.async { [self] in closeInput() }
    }

    private func addToReport(_ data: Data) {
        let room = TerminalCommandRun.reportLimit - report.count
        if room > 0 { report.append(data.prefix(room)) }
    }

    private func closeInput() {
        guard !inputClosed else { return }
        inputClosed = true
        try? input.fileHandleForWriting.close()
    }

    private func makeSource(_ fd: Int32, keeping pipe: Pipe, _ handle: @escaping (Data) -> Void) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            // At most this much per round. If a command floods (think `yes`), pause briefly so the pipe
            // fills and the command is slowed down, rather than NotchPad racing to keep up.
            let limit = 262_144
            let got = TerminalCommandRun.drain(fd, limit: limit, handle)
            if got >= limit { usleep(20_000) }
        }
        // The pipe must outlive the source, so hold it until the source has fully shut down.
        source.setCancelHandler { withExtendedLifetime(pipe) {} }
        source.resume()
        return source
    }

    /// Reads whatever is waiting on `fd` without blocking. Returns how many bytes it read.
    @discardableResult
    private static func drain(_ fd: Int32, limit: Int, _ handle: (Data) -> Void) -> Int {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var total = 0
        while total < limit {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                handle(Data(buffer[0..<n]))
                total += n
            } else if n < 0 && errno == EINTR {
                continue
            } else {
                break                                        // nothing waiting, or the pipe has closed
            }
        }
        return total
    }
}

/// The command line's state. In memory only: nothing here is ever written to disk.
final class TerminalSession: ObservableObject {
    static let shared = TerminalSession()

    @Published private(set) var entries: [TerminalEntry] = []      // oldest first
    @Published private(set) var isRunning = false
    @Published private(set) var directory = "~"                    // current directory, for the prompt
    private(set) var history: [String] = []                        // commands typed, oldest first

    private static let maxEntries = 200
    private var path = ""                      // current directory in full; empty means the home folder
    private var nextID = 1
    private var current: TerminalCommandRun?
    private var currentID: Int?

    // Shared with the queue that reads the command's output.
    private let lock = NSLock()
    private var cleaner = TerminalOutputCleaner()
    private var flushWaiting = false

    // Build checks only.
    private var checkQueue: [String] = []
    private var checkStopAfter: Double?
    private var checking = false

    /// Runs one command. Ignores blank input and anything typed while a command is running.
    func run(_ typed: String) {
        // Sent on exactly as typed (a trailing space can matter); trimmed only to spot blanks and the built-in words.
        let command = typed.trimmingCharacters(in: .newlines)
        let word = command.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !isRunning, !LockManager.shared.isLocked else { return }
        if history.last != command { history.append(command) }
        if history.count > 200 { history.removeFirst(history.count - 200) }
        if word == "clear" { clear(); return }
        if word == "exit" { Settings.shared.terminalMode = false; return }

        var entry = TerminalEntry(id: nextID, command: command, directory: directory, output: "",
                                  exitStatus: nil, stopped: false, note: nil)
        nextID += 1

        let addOn = TerminalAddOn.shared
        addOn.refresh()
        guard addOn.status == .ready else {
            entry.exitStatus = -1
            entry.note = addOn.status == .notInstalled
                ? "The terminal add-on isn't installed. See Settings › Terminal mode."
                : "The terminal add-on needs updating. See Settings › Terminal mode."
            append(entry)
            debugLog("NOTCHPAD_TERM_REFUSED \(addOn.status)")
            return
        }
        let run: TerminalCommandRun
        do {
            run = try TerminalCommandRun(script: TerminalAddOn.scriptURL)
        } catch {
            entry.exitStatus = -1
            entry.note = "Couldn't start the add-on: \(error.localizedDescription)"
            append(entry)
            debugLog("NOTCHPAD_TERM_REFUSED \(error)")
            return
        }

        append(entry)
        let id = entry.id
        current = run
        currentID = id
        isRunning = true
        debugLog("NOTCHPAD_TERM_RUN \(command)")
        let mode = Settings.shared.terminalFullShell ? "full" : "login"
        run.start(arguments: ["1", mode, path, command],
                  onOutput: { [weak self] data in self?.received(data, for: id) },
                  onEnd: { [weak self] report, error in
                      DispatchQueue.main.async { self?.finish(id, report: report, error: error) }
                  })
    }

    /// Stops the running command, if any.
    func stop() {
        guard let run = current, let id = currentID else { return }
        if let i = entries.firstIndex(where: { $0.id == id }), !entries[i].stopped { entries[i].stopped = true }
        run.stop()
    }

    /// Forgets finished entries (a running one stays).
    func clear() {
        entries.removeAll { !$0.isRunning }
    }

    /// Everything as plain text, for copying or adding to the note.
    var transcript: String {
        entries.map { TerminalSession.text(of: $0) }.joined(separator: "\n")
    }

    /// One command and its output as plain text.
    static func text(of entry: TerminalEntry) -> String {
        var lines = "$ " + entry.command
        let output = entry.output.hasSuffix("\n") ? String(entry.output.dropLast()) : entry.output
        if !output.isEmpty { lines += "\n" + output }
        return lines
    }

    private func append(_ entry: TerminalEntry) {
        entries.append(entry)
        let extra = entries.count - TerminalSession.maxEntries
        if extra > 0 { entries.removeFirst(extra) }
    }

    /// Called on the reading queue with more output. Updates the pad at most about 15 times a second.
    private func received(_ data: Data, for id: Int) {
        lock.lock()
        cleaner.add(data)
        let schedule = !flushWaiting
        flushWaiting = true
        lock.unlock()
        if schedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.066) { [weak self] in self?.flush(id) }
        }
    }

    private func flush(_ id: Int) {
        guard id == currentID else { return }      // a late update for a command that has already ended
        lock.lock()
        flushWaiting = false
        let text = cleaner.text
        let dropped = cleaner.droppedEarlier
        lock.unlock()
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries[i]
        entry.output = text
        if dropped { entry.note = "Earlier output was dropped (too long)." }
        if entry != entries[i] { entries[i] = entry }
    }

    private func finish(_ id: Int, report: Data, error: Error?) {
        guard id == currentID else { return }
        lock.lock()
        cleaner.finish()
        let text = cleaner.text
        let dropped = cleaner.droppedEarlier
        cleaner = TerminalOutputCleaner()
        flushWaiting = false
        lock.unlock()
        current = nil
        currentID = nil
        isRunning = false

        // The report is lines of key=value. Split on the line-feed byte itself, so nothing odd in a
        // folder's name can run two lines together. The add-on writes the status last: the last one counts.
        var status: Int?
        var endedIn: String?
        var problem: String?
        for bytes in report.split(separator: 0x0A) {
            let line = String(decoding: bytes, as: UTF8.self)
            if line.hasPrefix("status=") {
                if let n = Int(line.dropFirst(7)), (0...255).contains(n) { status = n }
            } else if line.hasPrefix("cwd=") {
                endedIn = String(line.dropFirst(4))
            } else if line.hasPrefix("error=") {
                problem = String(line.dropFirst(6))
            }
        }
        if let endedIn = endedIn, endedIn.hasPrefix("/") {
            path = endedIn
            directory = TerminalSession.shortened(endedIn)
        }
        var stopped = false
        if let i = entries.firstIndex(where: { $0.id == id }) {
            var entry = entries[i]
            entry.output = text
            entry.exitStatus = status ?? -1
            if dropped { entry.note = "Earlier output was dropped (too long)." }
            if status == nil {
                entry.note = "The add-on couldn't run this: "
                    + (problem ?? error?.localizedDescription ?? "it ended without a result") + "."
            }
            stopped = entry.stopped
            entries[i] = entry
        }
        if notchPadDebug {
            for line in text.split(separator: "\n") { debugLog("NOTCHPAD_TERM_LINE \(line)") }
            if status == nil { debugLog("NOTCHPAD_TERM_PROBLEM report=\(String(decoding: report, as: UTF8.self)) error=\(String(describing: error))") }
            let ended = path.isEmpty ? TerminalAddOn.realHome : path
            debugLog("NOTCHPAD_TERM_DONE status=\(status ?? -1) stopped=\(stopped) cwd=\(ended)")
        }
        if checking { nextBuildCheck() }
    }

    /// "/Users/you/Projects" becomes "~/Projects".
    private static func shortened(_ path: String) -> String {
        let home = TerminalAddOn.realHome
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    // MARK: Build checks

    /// Build checks only (NOTCHPAD_DEBUG_TERMINAL): runs the commands one after another through the real path.
    func runBuildCheck(_ commands: [String], stopAfter: Double?) {
        TerminalAddOn.shared.refresh()
        debugLog("NOTCHPAD_TERM_ADDON=\(TerminalAddOn.shared.status)")
        checkQueue = commands
        checkStopAfter = stopAfter
        checking = true
        nextBuildCheck()
    }

    private func nextBuildCheck() {
        guard checking else { return }
        guard !checkQueue.isEmpty else {
            checking = false
            debugLog("NOTCHPAD_TERM_FINISHED")
            return
        }
        let command = checkQueue.removeFirst()
        run(command)
        guard isRunning, let id = currentID else {
            // It was refused, or it was one of the built-in words: on to the next.
            DispatchQueue.main.async { [weak self] in self?.nextBuildCheck() }
            return
        }
        if let seconds = checkStopAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                if self?.currentID == id { self?.stop() }
            }
        }
    }
}
