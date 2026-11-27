import Foundation
import Testing
import NtakkerCore
@testable import UntypeStudioKit

/// Minutes of one side of a recording (2026-11-26).
@Suite("Minutes of one channel")
struct MinutesScopeTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ text: String, _ source: SourceTag, at s: Double) -> TranscriptEntry {
        TranscriptEntry(segment: StudioFixtures.segment(text, at: t0.addingTimeInterval(s), source: source),
                        start: s, end: s + 2, transcriptURL: URL(fileURLWithPath: "/tmp/x.transcript.jsonl"))
    }

    @Test("a scope keeps only its channel's lines")
    func filtersLines() {
        let all = [entry("hello from the call", .system, at: 0), entry("coffee?", .microphone, at: 5),
                   entry("next slide", .system, at: 10)]
        #expect(MinutesScope.whole.entries(of: all).count == 3)
        #expect(MinutesScope.microphone.entries(of: all).map(\.segment.text) == ["coffee?"])
        #expect(MinutesScope.system.entries(of: all).map(\.segment.text) == ["hello from the call", "next slide"])
    }

    @Test("each scope has its own file and its own job, and the library sees the files")
    func filesAndJobs() {
        let root = StudioFixtures.tempDir("minutes-scope")
        for n in ["m.mic.m4a", "m.system.m4a", "m.minutes.md", "m.mic.minutes.md", "m.system.minutes.md"] {
            StudioFixtures.touch(root.appendingPathComponent(n))
        }
        let rec = RecordingLibraryScanner.scan(root: root).first { $0.stem == "m" }!
        #expect(MinutesScope.allCases.map { $0.url(for: rec).lastPathComponent }
            == ["m.minutes.md", "m.mic.minutes.md", "m.system.minutes.md"])
        #expect(MinutesScope.whole.url(for: rec) == rec.minutesURL)
        #expect(Set(MinutesScope.allCases.map { $0.jobID(recordingID: rec.id) }).count == 3)
        #expect(MinutesScope.whole.jobID(recordingID: rec.id) == rec.id)
        let names = Set(rec.attachments.map(\.lastPathComponent))
        #expect(names.isSuperset(of: ["m.minutes.md", "m.mic.minutes.md", "m.system.minutes.md"]))
        // The channel minutes are the recording's files (rename, Trash), not another recording.
        #expect(RecordingLibraryScanner.scan(root: root).count == 1)
        #expect(RecordingFileOps.files(of: rec).map(\.lastPathComponent).contains("m.mic.minutes.md"))
    }

    @Test("the request says which side the transcript is")
    func promptNote() {
        func text(_ scope: MinutesScope) -> String {
            StudioAsk.minutesUserText(transcript: "[00:05] Microphone: coffee?", recordingName: "m",
                                      recordedAt: t0, duration: 60, language: nil, scope: scope)
        }
        #expect(text(.microphone).contains("only what the microphone recorded"))
        #expect(text(.system).contains("only the system audio"))
        #expect(!text(.whole).contains("only what the microphone") && !text(.whole).contains("only the system audio"))
        #expect(text(.microphone).contains("Write the minutes of this meeting with these sections"))
    }

    @Test("jobs of one recording's scopes are told apart and found by recording")
    @MainActor
    func jobsPerScope() async {
        let dir = StudioFixtures.tempDir("minutes-scope-jobs")
        let jobs = MinutesJobs()
        var feeds: [MinutesScope: AsyncThrowingStream<String, Error>.Continuation] = [:]
        for scope in [MinutesScope.microphone, .system] {
            let s = AsyncThrowingStream<String, Error> { feeds[scope] = $0 }
            #expect(jobs.start(id: scope.jobID(recordingID: "rec"), recordingID: "rec", recordingName: "rec",
                               minutesURL: dir.appendingPathComponent("rec.\(scope.fileSuffix)"),
                               tokens: s, provider: "p", model: "m"))
        }
        #expect(jobs.jobs(ofRecording: "rec").count == 2)
        #expect(jobs.isRunning(recording: "rec"))
        #expect(!jobs.isRunning("rec"))
        feeds[.microphone]!.yield("room talk")
        feeds[.system]!.yield("call talk")
        feeds[.microphone]!.finish()
        feeds[.system]!.finish()
        while jobs.isRunning(recording: "rec") { await Task.yield() }
        func body(_ n: String) -> String? {
            (try? String(contentsOf: dir.appendingPathComponent(n), encoding: .utf8))?.components(separatedBy: "\n\n---\n").first
        }
        #expect(body("rec.mic.minutes.md") == "room talk")
        #expect(body("rec.system.minutes.md") == "call talk")
    }
}
