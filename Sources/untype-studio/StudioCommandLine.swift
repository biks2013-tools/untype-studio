// untype-studio/StudioCommandLine.swift — 2026-10-18.
//
// The studio's entry point. With no arguments it opens the app; with a
// command it runs that command in the terminal and exits:
//
//   untype-studio <folder>            (also: untype-studio open <folder>)
//   untype-studio match-meetings [--from YYYY-MM-DD] [--to YYYY-MM-DD]
//                                 [--name <text>] [--library <folder>]
//   untype-studio join --name <text> [--library <folder>] [--dry-run]
//   untype-studio clean-echo --name <text> [--library <folder>] [--all]
//                             [--suppression off|low|high] [--dry-run]
//
// `<folder>` (2026-11-22) opens the app on the recording in that folder
// alone, without the library: the folder is scanned directly, its
// recording opens at once, and the sidebar lists only it and the copies
// written next to it (`LibraryStore.focusFolders`). The folder does not
// have to be inside the recordings folder of the settings, which is not
// read or changed. Meant for cleaning up the audio, writing the minutes
// or linking the meeting of one recording.
//
// `match-meetings` runs the calendar command (NTAKKER_CALENDAR_COMMAND in
// ~/.tool-agents/ntakker/.env) and prints, as JSON, the meeting each
// recording of the library most likely is. Options narrow the recordings:
// by start day (both included), by a case-insensitive part of the name,
// and the library folder (default: NTAKKER_RECORDINGS_DIR).
//
// `join` joins the recordings whose name contains <text> into one, in the
// order they were recorded (see RecordingJoiner), and prints the result
// as JSON; `--dry-run` prints the plan without writing anything.
//
// `clean-echo` (2026-11-21) writes a copy of the recording whose name
// contains <text> with the echo of the system track removed from its
// microphone track (RecordingCutExporter.cleanCopy; the original is not
// changed) and prints the result as JSON. Several matches are refused
// unless `--all` is given. The echo filter settings come from the shared
// settings file; `--suppression` replaces the suppression level.
//
// Exit codes: 0 success, 64 usage, 78 missing configuration, 1 failure.

import AppKit
import Foundation
import NtakkerCore
import UntypeStudioKit

@main
enum StudioMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        // Finder and `open` may pass -psn_… / -NSDocumentRevisionsDebugMode;
        // only a bare first word is a command.
        guard let first = args.first, !first.hasPrefix("-") else {
            UntypeStudioApp.main()
            return
        }
        // A folder (or `open <folder>`): the app, on that recording.
        if first == "open" || !commands.contains(first) && isDirectory(first) {
            let path = first == "open" ? args.dropFirst().first : first
            guard let path, args.count == (first == "open" ? 2 : 1) else {
                StudioCommandLine.fail("open takes one folder\n\n\(StudioCommandLine.usage)")
                exit(64)
            }
            guard isDirectory(path) else {
                StudioCommandLine.fail("\(path) is not a folder")
                exit(64)
            }
            let folder = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            guard folder.pathComponents.count > 1 else {
                StudioCommandLine.fail("\(path) can't be opened as a recording's folder")
                exit(64)
            }
            guard !RecordingLibraryScanner.scan(root: folder).isEmpty else {
                StudioCommandLine.fail("no recording found in \(folder.path)")
                exit(1)
            }
            LibraryStore.launchFolder = folder
            // AppKit would take the path for a document to open, and the
            // app would then start without its window.
            UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])
            UntypeStudioApp.main()
            return
        }
        let code: Int32
        switch first {
        case "match-meetings":
            code = runBlocking { await MatchMeetingsCommand.run(Array(args.dropFirst())) }
        case "join":
            code = runBlocking { await JoinCommand.run(Array(args.dropFirst())) }
        case "clean-echo":
            code = runBlocking { await CleanEchoCommand.run(Array(args.dropFirst())) }
        case "help", "--help", "-h":
            print(StudioCommandLine.usage)
            code = 0
        case _ where first.contains("/") || first.hasPrefix("~") || first.hasPrefix("."):
            StudioCommandLine.fail("\(first) is not a folder")
            code = 64
        default:
            StudioCommandLine.fail("unknown command \(first)\n\n\(StudioCommandLine.usage)")
            code = 64
        }
        exit(code)
    }

    private static let commands: Set<String> = ["match-meetings", "join", "clean-echo", "help", "--help", "-h"]

    private static func isDirectory(_ path: String) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
    }

    private static func runBlocking(_ body: @escaping @Sendable () async -> Int32) -> Int32 {
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await body()
            done.signal()
        }
        done.wait()
        return box.value
    }
}

private final class ResultBox: @unchecked Sendable { var value: Int32 = 1 }

enum StudioCommandLine {
    static let usage = """
    usage: untype-studio [folder | command]

      (no command)        open the app on the library
      FOLDER              open the app on the recording in FOLDER alone (also: open FOLDER)
      match-meetings      print, as JSON, the meeting each recording most likely is
          --from DAY        only recordings that started on or after DAY (YYYY-MM-DD)
          --to DAY          only recordings that started on or before DAY
          --name TEXT       only recordings whose name contains TEXT (any case)
          --library DIR     the library folder (default: NTAKKER_RECORDINGS_DIR)
      join                join recordings into one, in the order they were recorded
          --name TEXT       the recordings whose name contains TEXT (any case); at least two
          --library DIR     the library folder (default: NTAKKER_RECORDINGS_DIR)
          --dry-run         print the plan, write nothing
      clean-echo          write a copy with the system audio removed from the microphone track
          --name TEXT       the recording whose name contains TEXT (any case)
          --all             clean every match (without it, several matches are refused)
          --suppression L   off, low or high (default: the echo filter setting; high when unset)
          --library DIR     the library folder (default: NTAKKER_RECORDINGS_DIR)
          --dry-run         print what would be cleaned, write nothing

    The calendar comes from NTAKKER_CALENDAR_COMMAND in ~/.tool-agents/ntakker/.env:
    a command line printing calendar JSON, with {from} and {to} replaced by days, e.g.
      /full/path/m365mail calendar export --from {from} --to {to} --no-description
    """

    static func fail(_ message: String) {
        FileHandle.standardError.write(Data("untype-studio: \(message)\n".utf8))
    }
}

enum MatchMeetingsCommand {
    struct Options {
        var from: Date?
        var to: Date?
        var name: String?
        var library: URL?
    }

    static func run(_ args: [String]) async -> Int32 {
        let options: Options
        do { options = try parse(args) } catch {
            StudioCommandLine.fail("\(error.localizedDescription)\n\n\(StudioCommandLine.usage)")
            return 64
        }
        do {
            _ = try EnvFileStore.loadIntoProcess(toolName: SharedSettings.toolName)
        } catch {
            StudioCommandLine.fail("could not read \(SharedSettings.fileURL.path): \(error.localizedDescription)")
            return 78
        }
        let env = ProcessInfo.processInfo.environment
        let command: CalendarCommand
        do { command = try CalendarCommand.configured(in: env) } catch {
            StudioCommandLine.fail(error.localizedDescription)
            return 78
        }
        guard let root = options.library ?? env[SharedSettings.Keys.recordingsDir].map({
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        }) else {
            StudioCommandLine.fail("no library folder: set \(SharedSettings.Keys.recordingsDir) in \(SharedSettings.fileURL.path) or pass --library")
            return 78
        }

        let calendar = Calendar.current
        let recordings = RecordingLibraryScanner.scan(root: root).filter { r in
            let day = calendar.startOfDay(for: RecordingTiming.start(of: r))
            if let from = options.from, day < from { return false }
            if let to = options.to, day > to { return false }
            if let name = options.name, !r.displayName.localizedCaseInsensitiveContains(name),
               !r.stem.localizedCaseInsensitiveContains(name) { return false }
            return true
        }
        do {
            let matched = try await MeetingLookup.match(recordings, command: command, calendar: calendar)
            print(String(decoding: try report(matched, library: root), as: UTF8.self))
            return 0
        } catch {
            StudioCommandLine.fail(error.localizedDescription)
            return 1
        }
    }

    static func parse(_ args: [String]) throws -> Options {
        var o = Options()
        var i = 0
        func value() throws -> String {
            guard i + 1 < args.count else { throw UsageError("\(args[i]) needs a value") }
            i += 1
            return args[i]
        }
        func day(_ s: String) throws -> Date {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd"
            guard let d = f.date(from: s) else { throw UsageError("not a day (YYYY-MM-DD): \(s)") }
            return d
        }
        while i < args.count {
            switch args[i] {
            case "--from": o.from = try day(try value())
            case "--to": o.to = try day(try value())
            case "--name": o.name = try value()
            case "--library":
                o.library = URL(fileURLWithPath: (try value() as NSString).expandingTildeInPath, isDirectory: true)
            default: throw UsageError("unknown option \(args[i])")
            }
            i += 1
        }
        return o
    }

    struct UsageError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    // MARK: - Output

    static func report(_ matched: [RecordingMeeting], library: URL) throws -> Data {
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        iso.formatOptions = [.withInternetDateTime]
        func minutes(_ s: TimeInterval) -> Double { (s / 60 * 10).rounded() / 10 }
        func percent(_ x: Double) -> Int { Int((x * 100).rounded()) }
        func meeting(_ m: MeetingMatch, full: Bool) -> [String: Any] {
            var d: [String: Any] = [
                "subject": m.event.subject,
                "start": iso.string(from: m.event.start),
                "end": iso.string(from: m.event.end),
                "overlapMinutes": minutes(m.overlap),
                "recordingCoveragePercent": percent(m.recordingCoverage),
                "meetingCoveragePercent": percent(m.meetingCoverage),
                "startOffsetMinutes": minutes(m.startOffset),
                "fitPercent": percent(m.fit),
                "nameMatches": m.nameMatches,
            ]
            if full {
                d["id"] = m.event.id
                if let o = m.event.organizer { d["organizer"] = o.display }
                d["attendees"] = m.event.attendees.map(\.display)
                if let r = m.event.myResponse { d["myResponse"] = r }
                if let l = m.event.location { d["location"] = l }
                if let w = m.event.webLink { d["webLink"] = w }
            }
            return d
        }
        let rows: [[String: Any]] = matched.map { r in
            var row: [String: Any] = [
                "recording": r.recording.displayName,
                "stem": r.recording.stem,
                "folder": r.recording.folder.path,
                "start": iso.string(from: r.start),
                "end": iso.string(from: r.end),
                "durationMinutes": minutes(r.duration),
                "confidence": r.result.confidence?.rawValue ?? "none",
            ]
            if let best = r.result.best { row["meeting"] = meeting(best, full: true) }
            if r.result.spansSeveralMeetings {
                row["spansSeveralMeetings"] = true
                row["meetingsCovered"] = r.result.covered.map { meeting($0, full: false) }
            }
            row["alternatives"] = r.result.matches.dropFirst().map { meeting($0, full: false) }
            return row
        }
        var counts: [String: Int] = ["strong": 0, "likely": 0, "weak": 0, "none": 0, "spansSeveralMeetings": 0]
        for r in matched {
            counts[r.result.confidence?.rawValue ?? "none", default: 0] += 1
            if r.result.spansSeveralMeetings { counts["spansSeveralMeetings", default: 0] += 1 }
        }
        let doc: [String: Any] = [
            "library": library.path,
            "recordings": matched.count,
            "matched": counts,
            "results": rows,
        ]
        return try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

enum JoinCommand {
    static func run(_ args: [String]) async -> Int32 {
        var name: String?
        var library: URL?
        var dryRun = false
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--name", "--library":
                guard i + 1 < args.count else {
                    StudioCommandLine.fail("\(args[i]) needs a value\n\n\(StudioCommandLine.usage)")
                    return 64
                }
                if args[i] == "--name" { name = args[i + 1] } else {
                    library = URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath, isDirectory: true)
                }
                i += 1
            case "--dry-run": dryRun = true
            default:
                StudioCommandLine.fail("unknown option \(args[i])\n\n\(StudioCommandLine.usage)")
                return 64
            }
            i += 1
        }
        guard let name, !name.isEmpty else {
            StudioCommandLine.fail("join needs --name\n\n\(StudioCommandLine.usage)")
            return 64
        }
        if library == nil {
            do { _ = try EnvFileStore.loadIntoProcess(toolName: SharedSettings.toolName) } catch {
                StudioCommandLine.fail("could not read \(SharedSettings.fileURL.path): \(error.localizedDescription)")
                return 78
            }
            library = ProcessInfo.processInfo.environment[SharedSettings.Keys.recordingsDir].map {
                URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
            }
        }
        guard let root = library else {
            StudioCommandLine.fail("no library folder: set \(SharedSettings.Keys.recordingsDir) in \(SharedSettings.fileURL.path) or pass --library")
            return 78
        }
        let recordings = RecordingLibraryScanner.scan(root: root).filter {
            $0.displayName.localizedCaseInsensitiveContains(name) || $0.stem.localizedCaseInsensitiveContains(name)
        }
        do {
            let plan = try RecordingJoiner.plan(try recordings.map(JoinPart.load))
            var doc: [String: Any] = ["plan": describe(plan)]
            if !dryRun {
                let r = try RecordingJoiner.join(plan)
                doc["joined"] = ["folder": r.folder.path, "stem": r.stem, "parts": r.parts,
                                 "durationSeconds": (r.duration * 10).rounded() / 10, "lines": r.lines]
            }
            let data = try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            print(String(decoding: data, as: UTF8.self))
            return 0
        } catch {
            StudioCommandLine.fail(error.localizedDescription)
            return 1
        }
    }

    static func describe(_ plan: JoinPlan) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        func s(_ x: Double) -> Double { (x * 10).rounded() / 10 }
        return [
            "stem": plan.stem,
            "start": iso.string(from: plan.audioStart),
            "durationSeconds": s(plan.duration),
            "tracks": plan.roles.map(\.fileToken),
            "transcripts": plan.transcriptLabels.map { $0.isEmpty ? "main" : $0 },
            "parts": plan.items.map { item -> [String: Any] in
                var d: [String: Any] = [
                    "recording": item.part.recording.displayName,
                    "folder": item.part.recording.folder.path,
                    "start": iso.string(from: item.part.audioStart),
                    "durationSeconds": s(item.part.duration),
                    "offsetSeconds": s(item.offset),
                    "lines": item.part.entriesByTranscript.values.reduce(0) { $0 + $1.count },
                ]
                if let p = item.pauseBefore { d["pauseBeforeSeconds"] = s(p) }
                return d
            },
        ]
    }
}

enum CleanEchoCommand {
    static func run(_ args: [String]) async -> Int32 {
        var name: String?
        var library: URL?
        var suppression: EchoFilterSettings.Suppression?
        var all = false
        var dryRun = false
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--name", "--library", "--suppression":
                guard i + 1 < args.count else {
                    StudioCommandLine.fail("\(args[i]) needs a value\n\n\(StudioCommandLine.usage)")
                    return 64
                }
                let value = args[i + 1]
                switch args[i] {
                case "--name": name = value
                case "--library": library = URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
                default:
                    guard let s = EchoFilterSettings.Suppression(rawValue: value) else {
                        StudioCommandLine.fail("--suppression is off, low or high, not \(value)")
                        return 64
                    }
                    suppression = s
                }
                i += 1
            case "--all": all = true
            case "--dry-run": dryRun = true
            default:
                StudioCommandLine.fail("unknown option \(args[i])\n\n\(StudioCommandLine.usage)")
                return 64
            }
            i += 1
        }
        guard let name, !name.isEmpty else {
            StudioCommandLine.fail("clean-echo needs --name\n\n\(StudioCommandLine.usage)")
            return 64
        }
        let values: [String: String]
        do { values = try SharedSettings.readAll() } catch {
            StudioCommandLine.fail("could not read \(SharedSettings.fileURL.path): \(error.localizedDescription)")
            return 78
        }
        guard let root = library ?? values[SharedSettings.Keys.recordingsDir].map({
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        }) else {
            StudioCommandLine.fail("no library folder: set \(SharedSettings.Keys.recordingsDir) in \(SharedSettings.fileURL.path) or pass --library")
            return 78
        }
        var settings = EchoFilterSettings.from(values)
        if let suppression { settings.suppression = suppression }

        let matches = RecordingLibraryScanner.scan(root: root).filter {
            $0.displayName.localizedCaseInsensitiveContains(name) || $0.stem.localizedCaseInsensitiveContains(name)
        }
        let split = matches.filter(\.hasEchoReference)
        guard !split.isEmpty else {
            StudioCommandLine.fail(matches.isEmpty
                ? "no recording's name contains \(name)"
                : "none of the \(matches.count) recordings matching \(name) has separate microphone and system tracks")
            return 1
        }
        guard split.count == 1 || all else {
            let list = split.map { "  \($0.folder.path) (\($0.stem))" }.joined(separator: "\n")
            StudioCommandLine.fail("\(split.count) recordings match \(name); narrow the name or pass --all:\n\(list)")
            return 64
        }

        var rows: [[String: Any]] = []
        var failed = false
        for rec in split {
            var row: [String: Any] = ["recording": rec.displayName, "folder": rec.folder.path, "stem": rec.stem]
            if !dryRun {
                do {
                    FileHandle.standardError.write(Data("removing echo from \(rec.displayName)…\n".utf8))
                    let r = try RecordingCutExporter.cleanCopy(of: rec, echoSettings: settings)
                    row["copy"] = r.folder.path
                    if let d = r.echoDelay { row["echoDelayMs"] = Int((d * 1000).rounded()) }
                } catch {
                    row["error"] = error.localizedDescription
                    failed = true
                }
            }
            rows.append(row)
        }
        let doc: [String: Any] = [
            "library": root.path,
            "dryRun": dryRun,
            "settings": ["strength": settings.strength, "suppression": settings.suppression.rawValue,
                         "adaptation": settings.adaptation.rawValue],
            "skippedNotSplit": matches.filter { !$0.hasEchoReference }.map(\.displayName),
            "recordings": rows,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            print(String(decoding: data, as: UTF8.self))
        }
        return failed ? 1 : 0
    }
}
