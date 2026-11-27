import AVFoundation
import Foundation
import NtakkerCore
import Testing
@testable import UntypeStudioKit

/// Removing the cuts from the recording itself, without a copy (2026-11-26).
@Suite("Cuts written into the recording itself")
struct CutInPlaceTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    /// Well after the files were written, so they don't look in use.
    private let later = Date().addingTimeInterval(3_600)

    private func frames(_ url: URL) -> Int {
        Int((try! AVAudioFile(forReading: url)).length)
    }

    private func fixture(_ name: String) throws -> (root: URL, folder: URL, recording: Recording, entries: [TranscriptFile: [TranscriptEntry]]) {
        let root = StudioFixtures.tempDir(name)
        let folder = root.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        StudioFixtures.writeWAV(folder.appendingPathComponent("rec.mic.wav"), seconds: 10) { _ in 0.25 }
        StudioFixtures.writeWAV(folder.appendingPathComponent("rec.system.wav"), seconds: 10) { _ in -0.5 }
        let mine = [StudioFixtures.segment("mine early", at: t0.addingTimeInterval(1), source: .microphone),
                    StudioFixtures.segment("mine late", at: t0.addingTimeInterval(6), source: .microphone)]
        let theirs = [StudioFixtures.segment("theirs", at: t0.addingTimeInterval(3), source: .system)]
        try TranscriptDocument.write(mine, to: folder.appendingPathComponent("rec.microphone.transcript.jsonl"))
        try TranscriptDocument.write(theirs, to: folder.appendingPathComponent("rec.system.transcript.jsonl"))
        StudioFixtures.touch(folder.appendingPathComponent("rec.minutes.md"), "# Title\n")
        let rec = RecordingLibraryScanner.scan(root: root)[0]
        var entries: [TranscriptFile: [TranscriptEntry]] = [:]
        for t in rec.transcripts {
            entries[t] = TranscriptDocument.load(t).entries(audioStart: t0, exact: true, syncOffsetSec: 0)
        }
        return (root, folder, rec, entries)
    }

    @Test("the tracks get shorter, the lines move, the meeting stays, no folder is added")
    func cutsInPlace() throws {
        let f = try fixture("cut-in-place")
        var meta = StudioMetadata(speakerNames: ["1": "Anna"], echoDelayMs: 40)
        meta.meeting = LinkedMeeting(id: "m1", subject: "Weekly", start: t0, end: t0.addingTimeInterval(600))
        try meta.save(to: f.recording.metadataURL)
        let before = try FileManager.default.contentsOfDirectory(atPath: f.folder.path).sorted()
        // A backup kept by an earlier text edit: it has the old times.
        StudioFixtures.touch(f.folder.appendingPathComponent("rec.microphone.transcript.jsonl.orig"), "{}\n")

        // Remove 2 s – 5 s: "theirs" (at 3 s) goes, "mine late" moves from 6 s to 3 s.
        let result = try RecordingCutExporter.applyInPlace(
            recording: f.recording, plan: CutPlan(ranges: [CutRange(start: 2, end: 5)], duration: 10),
            entriesByTranscript: f.entries, audioStart: t0, metadata: meta, libraryRoot: f.root, now: later
        )
        #expect(abs(result.removedSeconds - 3) < 0.01)
        #expect(result.droppedLines == 1)
        #expect(result.trashed.count == 6, "two tracks, two transcripts, studio.json, the transcript backup")
        defer { for t in result.trashed { try? FileManager.default.removeItem(at: t) } }

        #expect(try FileManager.default.contentsOfDirectory(atPath: f.folder.path).sorted() == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.path) == ["session"])
        #expect(frames(f.folder.appendingPathComponent("rec.mic.wav")) == 112_000)
        #expect(frames(f.folder.appendingPathComponent("rec.system.wav")) == 112_000)

        let rec = RecordingLibraryScanner.scan(root: f.root)[0]
        #expect(rec.id == f.recording.id)
        let saved = try StudioMetadata.load(from: rec.metadataURL)
        #expect(saved.meeting?.subject == "Weekly")
        #expect(saved.speakerNames == ["1": "Anna"])
        #expect(saved.echoDelayMs == 40)
        #expect(saved.audioStart == t0 && saved.syncOffsetSec == 0)
        #expect(Set(saved.exactTimingTranscripts) == ["rec.microphone.transcript.jsonl", "rec.system.transcript.jsonl"])

        let mic = rec.transcripts.first { $0.label == "microphone" }!
        let lines = TranscriptDocument.load(mic).entries(audioStart: t0, exact: true, syncOffsetSec: 0)
        #expect(lines.map(\.segment.text) == ["mine early", "mine late"])
        #expect(abs(lines[0].start - 1) < 0.01 && abs(lines[1].start - 3) < 0.01)
        let sys = rec.transcripts.first { $0.label == "system" }!
        #expect(TranscriptDocument.load(sys).segments.isEmpty)
        #expect(try String(contentsOf: rec.minutesURL, encoding: .utf8) == "# Title\n", "the minutes are left alone")
    }

    @Test("nothing changes when there is no cut, the cut removes everything, or lines are missing")
    func refusals() throws {
        let f = try fixture("cut-in-place-refused")
        let before = try FileManager.default.contentsOfDirectory(atPath: f.folder.path).sorted()
        func apply(_ ranges: [CutRange], _ entries: [TranscriptFile: [TranscriptEntry]]) throws {
            try RecordingCutExporter.applyInPlace(
                recording: f.recording, plan: CutPlan(ranges: ranges, duration: 10),
                entriesByTranscript: entries, audioStart: t0, metadata: StudioMetadata(), libraryRoot: f.root, now: later
            )
        }
        #expect(throws: (any Error).self) { try apply([], f.entries) }
        #expect(throws: (any Error).self) { try apply([CutRange(start: 0, end: 10)], f.entries) }
        #expect(throws: (any Error).self) { try apply([CutRange(start: 2, end: 5)], [:]) }
        // Still being recorded (files written just now).
        #expect(throws: (any Error).self) {
            try RecordingCutExporter.applyInPlace(
                recording: f.recording, plan: CutPlan(ranges: [CutRange(start: 2, end: 5)], duration: 10),
                entriesByTranscript: f.entries, audioStart: t0, metadata: StudioMetadata(), libraryRoot: f.root, now: Date()
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.folder.path).sorted() == before)
        #expect(frames(f.folder.appendingPathComponent("rec.mic.wav")) == 160_000)
    }
}
