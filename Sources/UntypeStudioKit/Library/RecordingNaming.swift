// UntypeStudioKit/Library/RecordingNaming.swift — 2026-11-22.
//
// Names for a recording taken from what it is about: the subject of the
// calendar meeting it is linked to, or the title of its minutes
// (user request).
//
// ntakker names a recording `<label>-recording-YYYY-MM-DD-HH-MM`, and the
// studio's copies add their own suffix after that (`…-cut-…`, `…-clean-…`,
// `.part01`). The new title replaces the label only: it goes in front of
// `recording-<date>-<time>` and everything after it stays, so the name
// still says when the recording was made and which copy it is.
//
//   northwind-recording-2026-11-13-17-02-clean-2026-11-21-23-40-10
//   → Partner sync-recording-2026-11-13-17-02-clean-2026-11-21-23-40-10
//
// Older names carry the date without the word (`northwind-2026-06-19-15-01`);
// the date part is kept as it is. A name with no date at all gets
// `recording-<date>-<time>` from the time the recording started.

import Foundation

public enum RecordingNaming {

    /// Longest title kept, in characters (a file name holds 255 bytes,
    /// and the date part and the longest file suffix need their share).
    public static let maxTitleLength = 80

    /// The part of `name` that starts at `recording-<date>-<time>` (or at
    /// the date, when the word is missing), up to the end. `nil` when
    /// `name` holds no date and time.
    public static func timestampTail(of name: String) -> String? {
        guard let r = name.range(
            of: #"(recording-)?\d{4}-\d{2}-\d{2}-\d{2}-\d{2}"#, options: .regularExpression
        ) else { return nil }
        return String(name[r.lowerBound...])
    }

    /// `recording-YYYY-MM-DD-HH-MM` for a recording that started at `date`.
    public static func timestampTail(for date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd-HH-mm"
        return "recording-" + f.string(from: date)
    }

    /// `title` as the front of a file name: no "/" or ":", no line
    /// breaks, no leading dot, single spaces, at most `maxTitleLength`
    /// characters. Empty when nothing usable is left.
    public static func sanitized(_ title: String) -> String {
        var s = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
        s = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        s = String(s.drop { $0 == "." || $0 == " " })
        if s.count > maxTitleLength {
            s = String(s.prefix(maxTitleLength)).trimmingCharacters(in: .whitespaces)
        }
        while let last = s.last, last == "-" || last == " " || last == "." { s.removeLast() }
        return s
    }

    /// The name of a recording now called `currentName` once it is named
    /// after `title`. `nil` when `title` leaves nothing to name it with.
    public static func name(
        title: String, currentName: String, start: Date, timeZone: TimeZone = .current
    ) -> String? {
        let front = sanitized(title)
        guard !front.isEmpty else { return nil }
        return front + "-" + (timestampTail(of: currentName) ?? timestampTail(for: start, timeZone: timeZone))
    }

    /// The title of minutes written by the studio: their first
    /// `# heading`, without Markdown emphasis marks.
    public static func minutesTitle(_ markdown: String) -> String? {
        for line in markdown.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            guard t.hasPrefix("# ") else { return nil }
            let title = t.dropFirst(2)
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : title
        }
        return nil
    }
}
