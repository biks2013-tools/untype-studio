// UntypeStudioKit/Ask/MinutesJobs.swift — 2026-11-26.
//
// Minutes being written, one job per recording (user request): a job
// keeps running when the user opens another recording, and several
// recordings can have their minutes written at the same time.
//
// A job owns everything it needs from the moment it starts — the token
// stream of its own request and the file it writes — and never looks at
// the open recording again, so jobs cannot mix. The text so far is kept
// here, keyed by the recording's id, and the Minutes panel of whichever
// recording is open shows its own job's text.
//
// Outcome:
//   • finished — the minutes are written to the file, the job is removed;
//   • stopped  — nothing is written, the job is removed;
//   • failed   — nothing is written, the job stays with its error until
//                it is dismissed or the minutes are started again.
// The file is written only on success, so minutes that existed before
// survive a stop or a failure.

import Foundation
import Observation

@MainActor @Observable
public final class MinutesJob: Identifiable {
    public let id: String
    /// The recording the minutes are of (several jobs can share it: one
    /// per `MinutesScope`).
    public let recordingID: String
    public let recordingName: String
    public let folder: URL
    public let minutesURL: URL
    /// The minutes received so far.
    public fileprivate(set) var text = ""
    public fileprivate(set) var isRunning = true
    /// Why the job failed (the job is then no longer running).
    public fileprivate(set) var error: String?
    @ObservationIgnored fileprivate var task: Task<Void, Never>?

    init(id: String, recordingID: String, recordingName: String, folder: URL, minutesURL: URL) {
        self.id = id
        self.recordingID = recordingID
        self.recordingName = recordingName
        self.folder = folder
        self.minutesURL = minutesURL
    }
}

@MainActor @Observable
public final class MinutesJobs {
    /// Jobs by recording id: the running ones and the failed ones.
    public private(set) var jobs: [String: MinutesJob] = [:]
    /// A job ended. `saved` is true when it wrote the minutes file.
    @ObservationIgnored public var onFinished: ((_ job: MinutesJob, _ saved: Bool) -> Void)?

    public init() {}

    public func job(for id: String) -> MinutesJob? { jobs[id] }
    public func isRunning(_ id: String) -> Bool { jobs[id]?.isRunning == true }
    public var running: [MinutesJob] { jobs.values.filter(\.isRunning) }
    /// Every job (running or failed) of one recording.
    public func jobs(ofRecording recordingID: String) -> [MinutesJob] {
        jobs.values.filter { $0.recordingID == recordingID }
    }
    public func isRunning(recording recordingID: String) -> Bool {
        jobs(ofRecording: recordingID).contains(where: \.isRunning)
    }

    /// The running job that writes into `folder`, when there is one
    /// (its recording must not be renamed or trashed meanwhile).
    public func runningJob(inFolder folder: URL) -> MinutesJob? {
        let f = folder.standardizedFileURL
        return running.first { $0.folder.standardizedFileURL == f }
    }

    /// Start writing the minutes of recording `id` from `tokens`.
    /// Returns false, and starts nothing, when its minutes are already
    /// being written.
    @discardableResult
    public func start(
        id: String,
        recordingID: String? = nil,
        recordingName: String,
        minutesURL: URL,
        tokens: AsyncThrowingStream<String, Error>,
        provider: String,
        model: String,
        describe: @escaping @MainActor (Error) -> String = { $0.localizedDescription },
        now: @escaping @MainActor () -> Date = { Date() }
    ) -> Bool {
        guard !isRunning(id) else { return false }
        let job = MinutesJob(id: id, recordingID: recordingID ?? id, recordingName: recordingName,
                             folder: minutesURL.deletingLastPathComponent(), minutesURL: minutesURL)
        jobs[id] = job
        job.task = Task { [weak self] in
            var saved = false
            do {
                for try await token in tokens { job.text += token }
                try Task.checkCancellation()
                try StudioNotes.writeMinutes(job.text, provider: provider, model: model, generatedAt: now(), to: minutesURL)
                saved = true
            } catch {
                // A stopped request ends with its own error; either way
                // the user asked for it.
                if !Task.isCancelled { job.error = "Minutes failed: \(describe(error))" }
            }
            job.isRunning = false
            guard let self else { return }
            // Only this job's own entry: a newer job may have replaced it.
            if job.error == nil, self.jobs[id] === job { self.jobs[id] = nil }
            self.onFinished?(job, saved)
        }
        return true
    }

    /// Stop the running job of `id`; nothing is written.
    public func stop(_ id: String) {
        jobs[id]?.task?.cancel()
    }

    /// Forget the failed job of `id`.
    public func dismissError(_ id: String) {
        if let job = jobs[id], !job.isRunning { jobs[id] = nil }
    }

    /// Wait for the job of `id` to end (tests).
    public func wait(_ id: String) async {
        await jobs[id]?.task?.value
    }
}
