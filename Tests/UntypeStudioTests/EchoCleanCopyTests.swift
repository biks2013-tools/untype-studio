import AVFoundation
import Foundation
import NtakkerCore
import Testing
@testable import UntypeStudioKit

/// Remove Echo into a Copy (2026-11-21).
@Suite("Removing the echo into a copy")
struct EchoCleanCopyTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func samples(_ url: URL) -> [Float] {
        let f = try! AVAudioFile(forReading: url)
        let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
        try! f.read(into: buf)
        return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
    }

    private func power(_ x: ArraySlice<Float>) -> Float { x.reduce(0) { $0 + $1 * $1 } / Float(max(1, x.count)) }

    /// Noise whose level rises and falls once a second (never silent),
    /// so its envelope has a shape the delay estimate can follow.
    private func swellingNoise(_ n: Int, rate: Int) -> [Float] {
        var s: UInt64 = 11
        return (0..<n).map { i in
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let level = 0.25 + 0.15 * sinf(2 * .pi * Float(i) / Float(rate))
            return (Float(s >> 40) / Float(1 << 24) * 2 - 1) * level
        }
    }

    @Test("the copy's microphone track loses the echo; the original and the system track are untouched")
    func cleanCopy() throws {
        let rate = 16_000, seconds = 20, delay = 1_280          // 80 ms
        let root = StudioFixtures.tempDir("clean")
        let folder = root.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sys = swellingNoise(rate * seconds, rate: rate)
        let mic = folder.appendingPathComponent("rec.mic.wav"), system = folder.appendingPathComponent("rec.system.wav")
        StudioFixtures.writeWAV(system, seconds: Double(seconds)) { sys[$0] }
        StudioFixtures.writeWAV(mic, seconds: Double(seconds)) { $0 >= delay ? 0.5 * sys[$0 - delay] : 0 }
        try TranscriptDocument.write([StudioFixtures.segment("hello", at: t0.addingTimeInterval(3))],
                                     to: folder.appendingPathComponent("rec.transcript.jsonl"))
        let micBefore = try Data(contentsOf: mic), systemBefore = try Data(contentsOf: system)

        let rec = RecordingLibraryScanner.scan(root: root)[0]
        #expect(rec.hasEchoReference)
        let result = try RecordingCutExporter.cleanCopy(of: rec, echoSettings: .standard, now: Date(timeIntervalSince1970: 1_800_000_500))

        #expect(result.folder.lastPathComponent.hasPrefix("session-clean-"))
        #expect(result.removedSeconds == 0)
        #expect(abs((result.echoDelay ?? 0) - 0.08) < 0.005)
        #expect(try Data(contentsOf: mic) == micBefore)
        #expect(try Data(contentsOf: system) == systemBefore)

        let copy = RecordingLibraryScanner.recordings(inFolder: result.folder)[0]
        #expect(copy.hasEchoReference)
        #expect(copy.transcripts.count == 1)
        let cleaned = samples(copy.tracks.first { $0.role == .microphone }!.url)
        let original = samples(mic)
        #expect(cleaned.count == original.count)
        #expect(samples(copy.tracks.first { $0.role == .system }!.url) == samples(system))
        let tail = (rate * 5)...
        let reduction = 10 * log10(power(original[tail]) / max(power(cleaned[tail]), 1e-12))
        #expect(reduction > 15, "echo reduced by \(reduction) dB")
    }

    @Test("a recording without separate microphone and system tracks is refused")
    func notSplit() throws {
        let root = StudioFixtures.tempDir("clean-mixed")
        let folder = root.appendingPathComponent("session")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        StudioFixtures.writeWAV(folder.appendingPathComponent("rec.wav"), seconds: 2)
        let rec = RecordingLibraryScanner.scan(root: root)[0]
        #expect(!rec.hasEchoReference)
        #expect(throws: EchoCleanerError.self) {
            try RecordingCutExporter.cleanCopy(of: rec, echoSettings: .standard)
        }
        #expect(RecordingLibraryScanner.scan(root: root).count == 1, "nothing was written")
    }
}
