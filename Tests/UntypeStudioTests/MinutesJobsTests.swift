import Foundation
import Testing
@testable import UntypeStudioKit

/// Minutes written by per-recording jobs that outlive the open recording
/// and run side by side (2026-11-26).
@Suite("Minutes jobs")
@MainActor
struct MinutesJobsTests {

    private typealias Feed = AsyncThrowingStream<String, Error>.Continuation

    private func stream() -> (AsyncThrowingStream<String, Error>, Feed) {
        var feed: Feed!
        let s = AsyncThrowingStream<String, Error> { feed = $0 }
        return (s, feed)
    }

    private func start(_ jobs: MinutesJobs, _ id: String, in dir: URL) -> (Feed, URL, Task<Void, Never>) {
        let (tokens, feed) = stream()
        let url = dir.appendingPathComponent("\(id).minutes.md")
        #expect(jobs.start(id: id, recordingName: id, minutesURL: url, tokens: tokens, provider: "p", model: "m"))
        // Wait on the job itself: a finished job leaves the registry.
        let job = jobs.job(for: id)!
        let done = Task { @MainActor in while job.isRunning { await Task.yield() } }
        return (feed, url, done)
    }

    private func settle() async { for _ in 0..<20 { await Task.yield() } }

    private func body(_ url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: "\n\n---\n").first
    }

    @Test("two jobs fed in turns each write only their own minutes")
    func parallelJobsDoNotMix() async {
        let dir = StudioFixtures.tempDir("minutes-parallel")
        let jobs = MinutesJobs()
        var finished: [String] = []
        jobs.onFinished = { job, saved in if saved { finished.append(job.id) } }
        let (a, aURL, aDone) = start(jobs, "a", in: dir)
        let (b, bURL, bDone) = start(jobs, "b", in: dir)
        for i in 1...5 {
            a.yield("A\(i) ")
            b.yield("B\(i) ")
        }
        await settle()
        #expect(jobs.job(for: "a")?.text == "A1 A2 A3 A4 A5 ")
        #expect(jobs.job(for: "b")?.text == "B1 B2 B3 B4 B5 ")
        #expect(jobs.running.count == 2)
        b.finish()
        await bDone.value
        #expect(jobs.isRunning("a"))
        a.yield("A6")
        a.finish()
        await aDone.value
        #expect(body(aURL) == "A1 A2 A3 A4 A5 A6")
        #expect(body(bURL) == "B1 B2 B3 B4 B5")
        #expect(jobs.jobs.isEmpty)
        #expect(finished == ["b", "a"])
    }

    @Test("a second start for the same recording is refused while the first runs")
    func oneJobPerRecording() async {
        let dir = StudioFixtures.tempDir("minutes-second")
        let jobs = MinutesJobs()
        let (a, url, done) = start(jobs, "a", in: dir)
        let (other, _) = stream()
        #expect(!jobs.start(id: "a", recordingName: "a", minutesURL: url, tokens: other, provider: "p", model: "m"))
        a.yield("first")
        a.finish()
        await done.value
        #expect(body(url) == "first")
    }

    @Test("stopping one job writes nothing for it and lets the other finish")
    func stopOne() async throws {
        let dir = StudioFixtures.tempDir("minutes-stop")
        let jobs = MinutesJobs()
        let (a, aURL, aDone) = start(jobs, "a", in: dir)
        let (b, bURL, bDone) = start(jobs, "b", in: dir)
        try "old minutes".write(to: aURL, atomically: true, encoding: .utf8)
        a.yield("half")
        b.yield("whole")
        await settle()
        jobs.stop("a")
        await aDone.value
        #expect(jobs.job(for: "a") == nil)
        #expect(try String(contentsOf: aURL, encoding: .utf8) == "old minutes")
        b.finish()
        await bDone.value
        #expect(body(bURL) == "whole")
    }

    @Test("a failure keeps the earlier minutes and the job's error")
    func failureKeepsOldFile() async throws {
        struct Boom: Error {}
        let dir = StudioFixtures.tempDir("minutes-fail")
        let jobs = MinutesJobs()
        let (a, url, done) = start(jobs, "a", in: dir)
        try "old minutes".write(to: url, atomically: true, encoding: .utf8)
        a.yield("partial")
        a.finish(throwing: Boom())
        await done.value
        #expect(try String(contentsOf: url, encoding: .utf8) == "old minutes")
        #expect(jobs.job(for: "a")?.error?.hasPrefix("Minutes failed") == true)
        #expect(!jobs.isRunning("a"))
        #expect(jobs.runningJob(inFolder: dir) == nil)
        jobs.dismissError("a")
        #expect(jobs.job(for: "a") == nil)
    }

    @Test("the folder of a running job is reported busy")
    func busyFolder() async {
        let dir = StudioFixtures.tempDir("minutes-busy")
        let jobs = MinutesJobs()
        let (a, _, done) = start(jobs, "a", in: dir)
        #expect(jobs.runningJob(inFolder: dir)?.id == "a")
        #expect(jobs.runningJob(inFolder: dir.deletingLastPathComponent()) == nil)
        a.finish()
        await done.value
        #expect(jobs.runningJob(inFolder: dir) == nil)
    }
}
