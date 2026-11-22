import AVFoundation
import Foundation
import NtakkerCore
import Testing
@testable import UntypeStudioKit

/// One channel or one range into a new recording, and the two actions
/// that change a recording itself (2026-11-22).
@Suite("Channels and ranges: new recordings, removing a track, writing silence")
struct ChannelCopyTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func samples(_ url: URL) -> (rate: Double, values: [Float]) {
        let f = try! AVAudioFile(forReading: url)
        let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
        try! f.read(into: buf)
        return (f.processingFormat.sampleRate, Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength))))
    }

    /// A 10 s split recording in `root/session`: mic at 0.25, system at
    /// -0.5, a main transcript with a line of each side and a transcript
    /// per channel.
    private func fixture(_ name: String) throws -> (root: URL, folder: URL, recording: Recording, entries: [TranscriptFile: [TranscriptEntry]]) {
        let root = StudioFixtures.tempDir(name)
        let folder = root.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        StudioFixtures.writeWAV(folder.appendingPathComponent("rec.mic.wav"), seconds: 10) { _ in 0.25 }
        StudioFixtures.writeWAV(folder.appendingPathComponent("rec.system.wav"), seconds: 10) { _ in -0.5 }
        let mine = [StudioFixtures.segment("mine early", at: t0.addingTimeInterval(1), source: .microphone),
                    StudioFixtures.segment("mine late", at: t0.addingTimeInterval(6), source: .microphone)]
        let theirs = [StudioFixtures.segment("theirs", at: t0.addingTimeInterval(5), source: .system)]
        try TranscriptDocument.write(mine + theirs, to: folder.appendingPathComponent("rec.transcript.jsonl"))
        try TranscriptDocument.write(mine, to: folder.appendingPathComponent("rec.microphone.transcript.jsonl"))
        try TranscriptDocument.write(theirs, to: folder.appendingPathComponent("rec.system.transcript.jsonl"))
        let rec = RecordingLibraryScanner.scan(root: root)[0]
        var entries: [TranscriptFile: [TranscriptEntry]] = [:]
        for t in rec.transcripts {
            entries[t] = TranscriptDocument.load(t).entries(audioStart: t0, exact: true, syncOffsetSec: 0)
        }
        return (root, folder, rec, entries)
    }

    private func texts(_ url: URL) -> [String] {
        TranscriptDocument.load(TranscriptFile(url: url, label: "")).segments.map(\.text)
    }

    @Test("a new recording with only the mic: its track, its lines, the original untouched")
    func onlyOneChannel() throws {
        let f = try fixture("only-mic")
        let before = try FileManager.default.contentsOfDirectory(atPath: f.folder.path).sorted()
        let result = try RecordingCutExporter.extract(
            recording: f.recording, range: nil, onlyRole: .microphone, duration: 10,
            entriesByTranscript: f.entries, audioStart: t0, metadata: StudioMetadata(), now: t0
        )
        #expect(result.folder.lastPathComponent.hasPrefix("session-mic-"))
        #expect(result.onlyRole == .microphone && !result.isExtract)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.folder.path).sorted() == before)

        let copy = RecordingLibraryScanner.recordings(inFolder: result.folder)[0]
        #expect(copy.tracks.map(\.role) == [.microphone])
        #expect(samples(copy.tracks[0].url).values.count == 160_000)
        #expect(copy.transcripts.map(\.label).sorted() == ["", "microphone"], "the system transcript is left out")
        #expect(texts(result.folder.appendingPathComponent("rec.transcript.jsonl")) == ["mine early", "mine late"])
    }

    @Test("a new recording from a range of the system track only, starting where the range begins")
    func rangeOfOneChannel() throws {
        let f = try fixture("part-system")
        let result = try RecordingCutExporter.extract(
            recording: f.recording, range: CutRange(start: 4, end: 7), onlyRole: .system, duration: 10,
            entriesByTranscript: f.entries, audioStart: t0, metadata: StudioMetadata(), now: t0
        )
        #expect(result.folder.lastPathComponent.hasPrefix("session-part-system-"))
        #expect(result.isExtract)
        let copy = RecordingLibraryScanner.recordings(inFolder: result.folder)[0]
        #expect(copy.tracks.map(\.role) == [.system])
        let (rate, s) = samples(copy.tracks[0].url)
        #expect(s.count == Int(3 * rate))
        #expect(s.allSatisfy { abs($0 + 0.5) < 0.01 })
        let meta = try StudioMetadata.load(from: copy.metadataURL)
        #expect(meta.audioStart == t0.addingTimeInterval(4))
        let lines = TranscriptDocument.load(copy.transcripts.first { $0.label == "" }!).segments
        #expect(lines.map(\.text) == ["theirs"])
        #expect(lines[0].timestamp == t0.addingTimeInterval(5), "the line keeps its wall-clock time")
    }

    @Test("a new recording from a range of both tracks")
    func rangeOfBoth() throws {
        let f = try fixture("part-both")
        let result = try RecordingCutExporter.extract(
            recording: f.recording, range: CutRange(start: 4.5, end: 8), onlyRole: nil, duration: 10,
            entriesByTranscript: f.entries, audioStart: t0, metadata: StudioMetadata(), now: t0
        )
        #expect(result.folder.lastPathComponent.hasPrefix("session-part-"))
        let copy = RecordingLibraryScanner.recordings(inFolder: result.folder)[0]
        #expect(copy.tracks.map(\.role) == [.microphone, .system])
        for t in copy.tracks { #expect(samples(t.url).values.count == 56_000) }
        #expect(texts(result.folder.appendingPathComponent("rec.transcript.jsonl")).sorted() == ["mine late", "theirs"])
        #expect(throws: AudioCutError.self) {
            try RecordingCutExporter.extract(
                recording: f.recording, range: nil, onlyRole: nil, duration: 10,
                entriesByTranscript: f.entries, audioStart: t0, metadata: StudioMetadata(), now: t0
            )
        }
    }

    @Test("removing a track moves its audio and its transcript to the Trash; the last track is refused")
    func removeTrack() throws {
        let f = try fixture("remove-track")
        let later = Date().addingTimeInterval(60)
        let trashed = try RecordingFileOps.removeTrack(.microphone, from: f.recording, libraryRoot: f.root, now: later)
        defer { for t in trashed { try? FileManager.default.removeItem(at: t) } }
        #expect(trashed.count == 2)
        let names = try FileManager.default.contentsOfDirectory(atPath: f.folder.path).sorted()
        #expect(names == ["rec.system.transcript.jsonl", "rec.system.wav", "rec.transcript.jsonl"])
        let rec = RecordingLibraryScanner.scan(root: f.root)[0]
        #expect(rec.id == f.recording.id)
        #expect(rec.tracks.map(\.role) == [.system])
        #expect(throws: RecordingFileOpsError.onlyTrack("system")) {
            try RecordingFileOps.removeTrack(.system, from: rec, libraryRoot: f.root, now: later)
        }
        #expect(throws: RecordingFileOpsError.noTrack("microphone")) {
            try RecordingFileOps.removeTrack(.microphone, from: rec, libraryRoot: f.root, now: later)
        }
    }

    @Test("writing silence rewrites the track in place; the file as it was goes to the Trash")
    func writeSilence() throws {
        let f = try fixture("write-silence")
        let mic = f.folder.appendingPathComponent("rec.mic.wav"), system = f.folder.appendingPathComponent("rec.system.wav")
        let systemBefore = try Data(contentsOf: system)
        let created = RecordingLibraryScanner.creationDate(mic)
        let later = Date().addingTimeInterval(60)

        #expect(throws: RecordingFileOpsError.nothingSilenced) {
            try RecordingFileOps.writeSilence(ChannelSilence(), into: f.recording, libraryRoot: f.root, now: later)
        }
        var silence = ChannelSilence()
        silence.add(CutRange(start: 2, end: 4), to: .microphone, duration: 10)
        let trashed = try RecordingFileOps.writeSilence(silence, into: f.recording, libraryRoot: f.root, now: later)
        defer { for t in trashed { try? FileManager.default.removeItem(at: t) } }
        #expect(trashed.count == 1)
        #expect(samples(trashed[0]).values.allSatisfy { abs($0 - 0.25) < 0.01 }, "the Trash holds the track as it was")

        let (rate, m) = samples(mic)
        #expect(m.count == Int(10 * rate), "same length")
        #expect(abs(m[Int(1 * rate)] - 0.25) < 0.01)
        #expect(m[Int(2.1 * rate)..<Int(3.9 * rate)].allSatisfy { abs($0) < 0.0001 })
        #expect(abs(m[Int(5 * rate)] - 0.25) < 0.01)
        #expect(try Data(contentsOf: system) == systemBefore, "the other track is untouched")
        #expect(RecordingLibraryScanner.creationDate(mic) == created)
        let names = try FileManager.default.contentsOfDirectory(atPath: f.folder.path)
        #expect(!names.contains { $0.hasPrefix(".silencing-") })
        #expect(RecordingLibraryScanner.scan(root: f.root).count == 1)
    }
}
