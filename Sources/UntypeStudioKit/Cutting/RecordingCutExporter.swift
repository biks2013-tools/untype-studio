// UntypeStudioKit/Cutting/RecordingCutExporter.swift — plan-024 T4.
//
// Writes a cut copy of a recording. The original files are never
// touched (decided with the user, 2026-10-17): every audio track is
// re-written without the removed ranges, every transcript is re-timed,
// and the copy gets its own studio metadata with exact timing.
//
// Where the copy goes:
//   * a recording alone in its session folder `X/` → a sibling folder
//     `X-cut-<yyyy-MM-dd-HH-mm-ss>/`;
//   * a recording that shares its folder with others → a subfolder
//     `<stem>-cut-<yyyy-MM-dd-HH-mm-ss>/` of that folder.
// File names inside the copy keep the original stem, so ntakker's
// naming rules still hold.
//
// 2026-11-22: a copy can hold one channel only (`onlyRole`: its track,
// and the transcript lines of its source), and `extract` writes a new
// recording from one range of the original (`…-part-…`), whose audio
// start is moved to where the range begins.

import AVFoundation
import Foundation
import NtakkerCore

public enum AudioCutError: Error, LocalizedError {
    case unreadable(URL, String)
    case nothingLeft
    case nothingToDo
    case noTrack(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url, let why): return "Could not read \(url.lastPathComponent): \(why)"
        case .nothingLeft: return "The cut removes the whole recording."
        case .nothingToDo: return "Add a cut or a silence, or choose to remove the echo."
        case .noTrack(let what): return "This recording has no separate \(what) track."
        }
    }
}

public enum AudioCutter {
    static let chunkFrames: AVAudioFrameCount = 65_536

    /// Duration of an audio file, in seconds.
    public static func duration(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.fileFormat.sampleRate
    }

    /// Copy `source` to `destination` keeping only `plan.keptRanges`, in
    /// the source's own format, with `silence` (ranges on the original
    /// timeline) replaced by silence. `progress` gets 0…1.
    public static func cut(
        _ source: URL,
        to destination: URL,
        plan: CutPlan,
        silence: [CutRange] = [],
        progress: (Double) -> Void = { _ in }
    ) throws {
        let input: AVAudioFile
        do { input = try AVAudioFile(forReading: source) } catch {
            throw AudioCutError.unreadable(source, error.localizedDescription)
        }
        let rate = input.fileFormat.sampleRate
        let processing = input.processingFormat
        let output = try AVAudioFile(
            forWriting: destination,
            settings: input.fileFormat.settings,
            commonFormat: processing.commonFormat,
            interleaved: processing.isInterleaved
        )
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processing, frameCapacity: chunkFrames) else {
            throw AudioCutError.unreadable(source, "could not allocate a buffer")
        }
        let kept = plan.keptRanges.map { r -> (AVAudioFramePosition, AVAudioFramePosition) in
            (AVAudioFramePosition((r.start * rate).rounded()),
             min(input.length, AVAudioFramePosition((r.end * rate).rounded())))
        }
        let total = max(1, kept.reduce(0) { $0 + ($1.1 - $1.0) })
        var done: AVAudioFramePosition = 0
        for (from, to) in kept where to > from {
            input.framePosition = from
            var remaining = to - from
            while remaining > 0 {
                let want = AVAudioFrameCount(min(AVAudioFramePosition(chunkFrames), remaining))
                let at = input.framePosition
                try input.read(into: buffer, frameCount: want)
                if buffer.frameLength == 0 { break }
                if !silence.isEmpty, let data = buffer.floatChannelData {
                    for c in 0..<Int(processing.channelCount) {
                        SilenceGain.apply(silence, to: data[c], frames: Int(buffer.frameLength), startFrame: at, rate: rate)
                    }
                }
                try output.write(from: buffer)
                remaining -= AVAudioFramePosition(buffer.frameLength)
                done += AVAudioFramePosition(buffer.frameLength)
                progress(Double(done) / Double(total))
            }
        }
    }
}

public struct CutExportResult: Sendable {
    public let folder: URL
    public let recordingStem: String
    public let removedSeconds: Double
    public let droppedLines: Int
    /// The echo delay used, when the echo was removed from the mic.
    public let echoDelay: Double?
    /// Seconds replaced with silence, per channel.
    public let silencedSeconds: [AudioTrackRole: Double]
    /// The one channel the copy holds (`nil`: every track).
    public var onlyRole: AudioTrackRole?
    /// Whether the copy is one range of the original (`extract`).
    public var isExtract = false
}

public enum RecordingCutExporter {

    /// Export a cut copy.
    ///
    /// - Parameters:
    ///   - entriesByTranscript: the placed lines of each transcript, as
    ///     the user sees them (current sync nudge applied).
    ///   - audioStart: the recording's audio start.
    ///   - metadata: the recording's studio metadata (speaker names are
    ///     carried over).
    ///   - removeEcho: also clean the microphone track of the system
    ///     track's echo (`EchoCleaner`) — split recordings only. The
    ///     cleaning runs on the original timeline, before the cut.
    ///   - silence: ranges of the mic / system track (original timeline)
    ///     to replace with silence in the copy (2026-10-21).
    ///   - onlyRole: write this channel only — its track, and of every
    ///     transcript the lines of its source; a transcript left with no
    ///     lines is not written (2026-11-22).
    ///   - isExtract: the plan keeps one range (see `extract`): the
    ///     folder is named `…-part-…` instead of `…-cut-…`.
    ///   - copyAudioStart: the copy's audio start, when it is not the
    ///     original's (an extract starts where its range begins).
    public static func export(
        recording: Recording,
        plan: CutPlan,
        entriesByTranscript: [TranscriptFile: [TranscriptEntry]],
        audioStart: Date,
        metadata: StudioMetadata,
        removeEcho: Bool = false,
        echoSettings: EchoFilterSettings = .standard,
        silence: ChannelSilence = ChannelSilence(),
        onlyRole: AudioTrackRole? = nil,
        isExtract: Bool = false,
        copyAudioStart: Date? = nil,
        now: Date = Date(),
        progress: @escaping (Double) -> Void = { _ in }
    ) throws -> CutExportResult {
        guard !plan.ranges.isEmpty || removeEcho || !silence.isEmpty || onlyRole != nil else { throw AudioCutError.nothingToDo }
        guard plan.resultDuration > 0.05 else { throw AudioCutError.nothingLeft }
        let outStart = copyAudioStart ?? audioStart
        let micTrack = recording.tracks.first { $0.role == .microphone }
        let sysTrack = recording.tracks.first { $0.role == .system }
        if removeEcho, micTrack == nil || sysTrack == nil { throw EchoCleanerError.notSplit }
        if let onlyRole, !recording.tracks.contains(where: { $0.role == onlyRole }) {
            throw AudioCutError.noTrack(onlyRole.fileToken)
        }
        // Cleaning the mic is pointless in a copy that holds the system track only.
        let removeEcho = removeEcho && onlyRole != .system
        let tracks = recording.tracks.filter { onlyRole == nil || $0.role == onlyRole }
        let fm = FileManager.default
        let roleToken: String? = onlyRole.map { $0 == .microphone ? "mic" : $0.fileToken }
        let suffix = [plan.ranges.isEmpty ? nil : (isExtract ? "part" : "cut"), roleToken,
                      removeEcho ? "clean" : nil, silence.isEmpty ? nil : "silenced"]
            .compactMap { $0 }.joined(separator: "-")
        let dest = destinationFolder(for: recording, suffix: suffix, now: now)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        do {
            // Cleaning is the slow part: it gets most of the progress bar.
            let cleanShare = removeEcho ? 0.7 : 0
            var echoDelay: Double?
            var cleanedMic: URL?
            if removeEcho, let micTrack, let sysTrack {
                let tmp = dest.appendingPathComponent(".cleaning-\(micTrack.url.lastPathComponent)")
                echoDelay = try EchoCleaner.clean(
                    micURL: micTrack.url, systemURL: sysTrack.url, to: tmp,
                    settings: echoSettings, delayOverride: metadata.echoDelayMs.map { $0 / 1000 }
                ) { p in
                    progress(p * cleanShare)
                }
                cleanedMic = tmp
            }
            let trackCount = Double(max(1, tracks.count))
            for (i, track) in tracks.enumerated() {
                let out = dest.appendingPathComponent(track.url.lastPathComponent)
                let source = track.role == .microphone ? (cleanedMic ?? track.url) : track.url
                try AudioCutter.cut(source, to: out, plan: plan, silence: silence.ranges(for: track.role)) { p in
                    progress(cleanShare + (Double(i) + p) / trackCount * (0.95 - cleanShare))
                }
                try? fm.setAttributes([.creationDate: outStart], ofItemAtPath: out.path)
            }
            if let cleanedMic { try? fm.removeItem(at: cleanedMic) }

            var dropped = 0
            var exact: [String] = []
            for transcript in recording.transcripts {
                var entries = entriesByTranscript[transcript] ?? []
                if let onlyRole {
                    let had = !entries.isEmpty
                    entries = entries.filter { $0.segment.source == onlyRole.sourceTag }
                    // The other channel's transcript: nothing of it belongs in the copy.
                    if had, entries.isEmpty { continue }
                    if transcript.label == Self.otherChannel(of: onlyRole)?.fileToken { continue }
                }
                let segments = TranscriptRetimer.retime(entries, plan: plan, audioStart: outStart)
                dropped += entries.count - segments.count
                let out = dest.appendingPathComponent(transcript.url.lastPathComponent)
                try TranscriptDocument.write(segments, to: out)
                exact.append(out.lastPathComponent)
            }

            let meta = StudioMetadata(
                audioStart: outStart,
                speakerNames: metadata.speakerNames,
                syncOffsetSec: 0,
                exactTimingTranscripts: exact
            )
            try meta.save(to: dest.appendingPathComponent("\(recording.stem).studio.json"))
            progress(1)
            return CutExportResult(
                folder: dest, recordingStem: recording.stem,
                removedSeconds: plan.removedDuration, droppedLines: dropped,
                echoDelay: echoDelay,
                silencedSeconds: silence.ranges.compactMapValues { r in
                    r.isEmpty ? nil : r.reduce(0) { $0 + $1.duration }
                },
                onlyRole: onlyRole, isExtract: isExtract
            )
        } catch {
            try? fm.removeItem(at: dest)
            throw error
        }
    }

    /// A copy of `recording` with the echo of the system track removed
    /// from the microphone track and nothing else changed (2026-11-21):
    /// the recording is read from disk and exported with no cuts. The
    /// transcripts are copied as they are — the microphone transcript
    /// still holds what was heard through the echo until the copy is
    /// re-transcribed.
    public static func cleanCopy(
        of recording: Recording,
        echoSettings: EchoFilterSettings,
        now: Date = Date(),
        progress: @escaping (Double) -> Void = { _ in }
    ) throws -> CutExportResult {
        guard recording.hasEchoReference else { throw EchoCleanerError.notSplit }
        let part = try JoinPart.load(recording)
        return try export(
            recording: recording, plan: CutPlan(ranges: [], duration: part.duration),
            entriesByTranscript: part.entriesByTranscript, audioStart: part.audioStart,
            metadata: part.metadata, removeEcho: true, echoSettings: echoSettings,
            now: now, progress: progress
        )
    }

    static func otherChannel(of role: AudioTrackRole) -> AudioTrackRole? {
        switch role {
        case .microphone: return .system
        case .system: return .microphone
        case .mixed: return nil
        }
    }

    /// A new recording from `range` of `recording` (the whole of it when
    /// `nil`), with every track or `onlyRole`'s only (2026-11-22). The
    /// new recording's audio start is where the range begins, so its
    /// lines keep their wall-clock times. Silenced ranges that fall in
    /// the range are written silent. The original is not changed.
    public static func extract(
        recording: Recording,
        range: CutRange?,
        onlyRole: AudioTrackRole?,
        duration: Double,
        entriesByTranscript: [TranscriptFile: [TranscriptEntry]],
        audioStart: Date,
        metadata: StudioMetadata,
        silence: ChannelSilence = ChannelSilence(),
        now: Date = Date(),
        progress: @escaping (Double) -> Void = { _ in }
    ) throws -> CutExportResult {
        guard range != nil || onlyRole != nil else { throw AudioCutError.nothingToDo }
        var cuts: [CutRange] = []
        var start: Date?
        if let range {
            cuts = [CutRange(start: 0, end: range.start), CutRange(start: range.end, end: duration)]
            start = audioStart.addingTimeInterval(max(0, range.start))
        }
        return try export(
            recording: recording, plan: CutPlan(ranges: cuts, duration: duration),
            entriesByTranscript: entriesByTranscript, audioStart: audioStart, metadata: metadata,
            silence: silence, onlyRole: onlyRole, isExtract: range != nil, copyAudioStart: start,
            now: now, progress: progress
        )
    }

    static func destinationFolder(for recording: Recording, suffix: String = "cut", now: Date) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let stamp = f.string(from: now)
        let alone = RecordingLibraryScanner.recordings(inFolder: recording.folder).count <= 1
        let base: URL
        let name: String
        if alone {
            base = recording.folder.deletingLastPathComponent()
            name = "\(recording.folder.lastPathComponent)-\(suffix)-\(stamp)"
        } else {
            base = recording.folder
            name = "\(recording.stem)-\(suffix)-\(stamp)"
        }
        var candidate = base.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = base.appendingPathComponent("\(name)-\(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }
}

extension Recording {
    /// Separate microphone and system tracks: the echo of the system
    /// track can be removed from the microphone track.
    public var hasEchoReference: Bool {
        tracks.contains { $0.role == .microphone } && tracks.contains { $0.role == .system }
    }
}
