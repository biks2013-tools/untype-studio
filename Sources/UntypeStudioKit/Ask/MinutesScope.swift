// UntypeStudioKit/Ask/MinutesScope.swift — 2026-11-26.
//
// Which side of a recording minutes are written from (user request): the
// whole conversation, only what the microphone recorded, or only the
// system audio. The two sides can be different conversations — a call on
// the computer while the user talks to someone in the room — and minutes
// of each side alone show whether they are.
//
// Each scope has its own file next to the recording, so the three can
// exist together: `<stem>.minutes.md`, `<stem>.mic.minutes.md`,
// `<stem>.system.minutes.md`.

import Foundation
import NtakkerCore

public enum MinutesScope: String, CaseIterable, Sendable, Identifiable {
    case whole, microphone, system

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .whole: return "Both"
        case .microphone: return "Mic"
        case .system: return "System"
        }
    }

    /// The transcript lines of this scope (`nil`: every line).
    public var source: SourceTag? {
        switch self {
        case .whole: return nil
        case .microphone: return .microphone
        case .system: return .system
        }
    }

    /// File name after `<stem>.`.
    public var fileSuffix: String {
        switch self {
        case .whole: return "minutes.md"
        case .microphone: return "mic.minutes.md"
        case .system: return "system.minutes.md"
        }
    }

    public func url(for recording: Recording) -> URL {
        recording.folder.appendingPathComponent("\(recording.stem).\(fileSuffix)")
    }

    /// The id of this scope's job for a recording (jobs are per file).
    public func jobID(recordingID: String) -> String {
        self == .whole ? recordingID : "\(recordingID)\u{1F}\(rawValue)"
    }

    /// The lines of `entries` that belong to this scope.
    public func entries(of entries: [TranscriptEntry]) -> [TranscriptEntry] {
        guard let source else { return entries }
        return entries.filter { $0.segment.source == source }
    }

    /// What the model is told about a one-sided transcript.
    public var promptNote: String? {
        switch self {
        case .whole:
            return nil
        case .microphone:
            return """
            This transcript holds only what the microphone recorded: the person who made the recording and anyone \
            in the room with them. What came through the computer (the other side of a call) is left out, though \
            some of it may have leaked into the microphone. Write the minutes of this side alone, and say in the \
            summary what kind of conversation it is: one side of a call, or people talking in the room.
            """
        case .system:
            return """
            This transcript holds only the system audio: what came through the computer (the remote participants \
            of a call or meeting, or anything else that was played). What was said into the microphone is left out. \
            Write the minutes of this side alone.
            """
        }
    }
}
