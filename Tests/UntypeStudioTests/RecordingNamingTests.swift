import Foundation
import Testing
@testable import UntypeStudioKit

/// Naming a recording after its meeting or its minutes (2026-11-22).
@Suite("Names from a meeting or the minutes")
struct RecordingNamingTests {

    private let athens = TimeZone(identifier: "Europe/Athens")!
    private var start: Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute) = (2026, 11, 13, 17, 2)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = athens
        return cal.date(from: c)!
    }

    private func name(_ title: String, _ current: String) -> String? {
        RecordingNaming.name(title: title, currentName: current, start: start, timeZone: athens)
    }

    @Test("the title goes in front of recording-date-time")
    func replacesLabel() {
        #expect(name("Partner sync", "sync-with-partner-recording-2026-11-13-17-02")
            == "Partner sync-recording-2026-11-13-17-02")
    }

    @Test("what follows the date (a copy's suffix, a part) is kept")
    func keepsSuffix() {
        #expect(name("Weekly", "x-recording-2026-11-13-17-02-clean-2026-11-21-23-40-10")
            == "Weekly-recording-2026-11-13-17-02-clean-2026-11-21-23-40-10")
        #expect(name("Weekly", "x-recording-2026-11-13-17-02.part01") == "Weekly-recording-2026-11-13-17-02.part01")
    }

    @Test("an older name with the date only keeps its date")
    func dateOnly() {
        #expect(name("Northwind steerco", "northwind-2026-06-19-15-01") == "Northwind steerco-2026-06-19-15-01")
    }

    @Test("a name without a date gets recording-date-time from the start")
    func noDate() {
        #expect(name("Budget review", "my meeting") == "Budget review-recording-2026-11-13-17-02")
    }

    @Test("a name that is only recording-date-time gets the title in front")
    func bareName() {
        #expect(name("Budget", "recording-2026-11-13-17-02") == "Budget-recording-2026-11-13-17-02")
    }

    @Test("characters a file name can't hold are replaced, long titles cut")
    func sanitizes() {
        #expect(RecordingNaming.sanitized("  .FW: Q3/Q4  plan\nreview - ") == "FW - Q3-Q4 plan review")
        #expect(RecordingNaming.sanitized(String(repeating: "α", count: 200)).count == RecordingNaming.maxTitleLength)
        #expect(name(" /: ", "x-recording-2026-11-13-17-02") == nil)
    }

    @Test("the minutes' title is their first heading")
    func minutesTitle() {
        #expect(RecordingNaming.minutesTitle("\n# **Roadmap** για το Q3\n\n**Date:** …\n## Summary") == "Roadmap για το Q3")
        #expect(RecordingNaming.minutesTitle("## Summary\n# Late title") == nil)
        #expect(RecordingNaming.minutesTitle("") == nil)
    }
}
