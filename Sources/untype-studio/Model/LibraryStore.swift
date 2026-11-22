// untype-studio/Model/LibraryStore.swift — plan-024 T9.
//
// The library: which folder, the recordings in it, the transcript
// search, and which recording is open.
//
// Library folder. The studio keeps its own setting
// (`studio.libraryFolder`). On first launch it adopts ntakker's
// recording folder (`com.ntakker-cli.ui.outputFolder` in the
// `com.giorgosmarinos.ntakker` defaults); when that is not set either, the app
// asks the user to choose a folder — there is no silent default.

import AppKit
import Foundation
import NtakkerCore
import NtakkerSettingsUI
import UntypeStudioKit
import Observation

@MainActor @Observable
final class LibraryStore {
    static let folderKey = "studio.libraryFolder"
    static let ntakkerDefaultsSuite = "com.giorgosmarinos.ntakker"
    /// ntakker's bundle id before the public release; its preferences
    /// still hold the folder until ntakker has run once under the new id.
    static let legacyNtakkerDefaultsSuite = "com.local.ntakker"
    static let ntakkerFolderKey = "com.ntakker-cli.ui.outputFolder"

    private(set) var root: URL?

    /// The folder given on the command line (`untype-studio <folder>`),
    /// set by `StudioMain` before the app starts. (2026-11-22)
    nonisolated(unsafe) static var launchFolder: URL?
    /// One-folder mode: the app was started on a recording's folder. Only
    /// these folders are scanned, not a library: the given folder, and the
    /// folders next to it whose name starts with its name (the copies the
    /// studio writes: `…-clean-…`, `…-cut-…`, `…-part-…`). `root` is then
    /// the folder that holds them, so a recording's folder can be renamed
    /// and copies land where they always do. The shared recordings-folder
    /// setting is neither read nor changed.
    private(set) var focusFolders: [URL] = []
    var isFocused: Bool { !focusFolders.isEmpty }
    @ObservationIgnored private var openedLaunchRecording = false
    private(set) var recordings: [Recording] = []
    private(set) var isScanning = false
    private(set) var indexedLines = 0

    var query = "" { didSet { scheduleSearch() } }
    private(set) var hits: [SearchHit] = []
    private(set) var searching = false

    /// The recordings selected in the sidebar. One opens in the detail
    /// view; several show the join panel.
    var selection: Set<String> = [] {
        didSet {
            if selectedID != (oldValue.count == 1 ? oldValue.first : nil) { openSelected() }
            if selection != oldValue { prepareJoin() }
        }
    }
    /// The one selected recording (nil when none or several are).
    var selectedID: String? {
        get { selection.count == 1 ? selection.first : nil }
        set { selection = newValue.map { [$0] } ?? [] }
    }
    private(set) var workspace: RecordingWorkspace?
    /// The selected recordings, oldest first.
    var selectedRecordings: [Recording] {
        recordings.filter { selection.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
    }
    /// The other parts of `recording`'s session (same folder, same stem
    /// without `.partNN`), itself included, when it has any.
    func sessionParts(of recording: Recording) -> [Recording] {
        guard recording.partNumber != nil else { return [] }
        let base = RecordingJoiner.baseStem(recording.stem)
        let parts = recordings.filter {
            $0.folder.standardizedFileURL == recording.folder.standardizedFileURL
                && $0.partNumber != nil && RecordingJoiner.baseStem($0.stem) == base
        }
        return parts.count >= 2 ? parts : []
    }

    @ObservationIgnored private let index = TranscriptSearchIndex()
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSeek: (id: String, time: Double, transcript: URL?)?

    init() {
        if let folder = Self.launchFolder {
            root = folder.deletingLastPathComponent()
            focusFolders = [folder]
            return
        }
        // plan-025: the library is the shared recordings folder
        // (NTAKKER_RECORDINGS_DIR in ~/.tool-agents/ntakker/.env), the one
        // ntakker records into. Carry over a folder chosen before, once.
        let store = SharedSettingsStore.shared
        if store.string(SharedSettings.Keys.recordingsDir) == nil {
            let d = UserDefaults.standard
            let previous = [d.string(forKey: Self.folderKey)]
                + [Self.ntakkerDefaultsSuite, Self.legacyNtakkerDefaultsSuite].map {
                    UserDefaults(suiteName: $0)?.string(forKey: Self.ntakkerFolderKey)
                }
            if let folder = previous.compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                store.set(SharedSettings.Keys.recordingsDir, folder)
            }
        }
        root = store.string(SharedSettings.Keys.recordingsDir).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// The shared recordings folder changed (here, in ntakker, or by hand).
    func followSharedFolder() {
        guard !isFocused else { return }
        let path = SharedSettingsStore.shared.string(SharedSettings.Keys.recordingsDir)
        let url = path.map { URL(fileURLWithPath: $0, isDirectory: true) }
        guard url?.standardizedFileURL != root?.standardizedFileURL else { return }
        root = url
        selectedID = nil
        Task { await rescan() }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as library"
        panel.message = "Choose the folder that holds your ntakker recordings."
        if let root { panel.directoryURL = root }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        SharedSettingsStore.shared.set(SharedSettings.Keys.recordingsDir, url.path)
        // Choosing a library leaves one-folder mode.
        if isFocused { focusFolders = []; root = nil }
        followSharedFolder()
    }

    func rescan() async {
        guard let root else { return }
        isScanning = true
        if isFocused { focusFolders = Self.withCopies(focusFolders, in: root) }
        let focus = focusFolders
        let found = await Task.detached { () -> [Recording] in
            guard !focus.isEmpty else { return RecordingLibraryScanner.scan(root: root) }
            var seen = Set<String>()
            return focus.flatMap { RecordingLibraryScanner.scan(root: $0) }
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.createdAt > $1.createdAt }
        }.value
        recordings = found
        isScanning = false
        // One-folder mode: open the folder's recording straight away.
        if isFocused, !openedLaunchRecording, selection.isEmpty, let launch = Self.launchFolder,
           let first = found.first(where: { RecordingFileOps.isInside($0.folder, launch) }) {
            openedLaunchRecording = true
            selection = [first.id]
        }
        if let ws = workspace, let updated = found.first(where: { $0.id == ws.recording.id }) {
            await ws.adopt(updated)
        }
        await index.update(with: found)
        indexedLines = await index.lineCount
        if !query.isEmpty { scheduleSearch() }
    }

    /// Rescan after a workspace wrote files; show `showOnly` transcripts.
    func filesChanged(in ws: RecordingWorkspace, showOnly: [URL]?) {
        Task {
            await rescan()
            if let showOnly, let updated = recordings.first(where: { $0.id == ws.recording.id }) {
                await ws.adopt(updated, showOnly: showOnly)
            }
        }
    }

    /// `folders` that still exist, plus the folders in `root` named after
    /// one of them (`<name>-…`), in a stable order.
    static func withCopies(_ folders: [URL], in root: URL) -> [URL] {
        let fm = FileManager.default
        var out = folders.filter { fm.fileExists(atPath: $0.path) }
        // Keep the launch folder in the list even while it is being moved.
        if out.isEmpty { out = folders }
        let names = out.map(\.lastPathComponent)
        let siblings = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for s in siblings where names.contains(where: { s.lastPathComponent.hasPrefix($0 + "-") }) {
            if !out.contains(where: { $0.standardizedFileURL == s.standardizedFileURL }) { out.append(s) }
        }
        return out
    }

    // MARK: - Selection

    private func openSelected() {
        workspace?.close()
        workspace = nil
        guard let id = selectedID, let rec = recordings.first(where: { $0.id == id }) else { return }
        let ws = RecordingWorkspace(recording: rec)
        ws.onFilesChanged = { [weak self, weak ws] showOnly in
            guard let self, let ws else { return }
            self.filesChanged(in: ws, showOnly: showOnly)
        }
        workspace = ws
        Task {
            await ws.load()
            if let p = pendingSeek, p.id == id {
                pendingSeek = nil
                if let t = p.transcript { ws.visibleTranscripts.insert(t) }
                ws.player.seek(to: p.time)
            }
        }
    }

    /// Open a search hit: select its recording and seek to the line.
    func open(_ hit: SearchHit) {
        if selectedID == hit.recordingID, let ws = workspace, ws.isLoaded {
            ws.visibleTranscripts.insert(hit.transcriptURL)
            ws.player.seek(to: hit.start)
        } else {
            pendingSeek = (hit.recordingID, hit.start, hit.transcriptURL)
            selectedID = hit.recordingID
        }
    }

    /// Open a recording by folder (after a cut export or a join).
    func reveal(folder: URL) {
        // One-folder mode: a copy written elsewhere joins the list first.
        if isFocused, !focusFolders.contains(where: { $0.standardizedFileURL == folder.standardizedFileURL }),
           FileManager.default.fileExists(atPath: folder.path) {
            focusFolders.append(folder)
            Task {
                await rescan()
                reveal(folder: folder)
            }
            return
        }
        if let rec = recordings.first(where: { $0.folder.standardizedFileURL == folder.standardizedFileURL }) {
            selectedID = rec.id
        }
    }

    // MARK: - Rename and Trash

    /// The last rename / Move to Trash that failed, for the alert.
    var fileOpError: String?
    /// The recording the rename sheet is open for.
    var renameRequest: Recording?
    /// The recordings the Move to Trash confirmation is asking about.
    var trashRequest: [Recording] = []

    /// Ask to rename the one selected recording (menu, context menu).
    func requestRename(_ ids: Set<String>? = nil) {
        let ids = ids ?? selection
        guard ids.count == 1, let rec = recordings.first(where: { ids.contains($0.id) }) else { return }
        renameSuggestion = nil
        renameRequest = rec
    }

    /// The name the rename sheet proposes instead of the current one
    /// (a name taken from the meeting or the minutes).
    var renameSuggestion: String?

    /// The name `recording` would take when named after `title`: the
    /// title in front of `recording-<date>-<time>` and what follows it
    /// (see `RecordingNaming`). `start` is when the recording started.
    func name(of recording: Recording, after title: String, start: Date) -> String? {
        RecordingNaming.name(title: title, currentName: renameName(of: recording), start: start)
    }

    /// Open the rename sheet for `recording` with the name it would take
    /// after `title` filled in; the user confirms or edits it.
    func requestRename(_ recording: Recording, after title: String, start: Date) {
        guard let proposed = name(of: recording, after: title, start: start) else {
            fileOpError = "“\(title)” leaves nothing to name the recording with."
            return
        }
        renameSuggestion = proposed
        renameRequest = recording
    }

    /// Ask to move recordings to the Trash (the selection by default).
    func requestTrash(_ ids: Set<String>? = nil) {
        let ids = ids ?? selection
        trashRequest = recordings.filter { ids.contains($0.id) }
    }

    /// Show recordings in Finder.
    func revealInFinder(_ ids: Set<String>) {
        let urls = recordings.filter { ids.contains($0.id) }.flatMap { rec -> [URL] in
            rec.sharesFolder ? rec.tracks.map(\.url) : [rec.folder]
        }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    /// The name a rename of `recording` edits (its folder's or its stem).
    func renameName(of recording: Recording) -> String {
        guard let root else { return recording.stem }
        return RecordingFileOps.currentName(recording, libraryRoot: root)
    }

    /// Whether renaming `recording` renames its session folder, and with
    /// it every part of the session.
    func renameRenamesSession(_ recording: Recording) -> Bool {
        guard let root, case .folder = RecordingFileOps.renameTarget(recording, libraryRoot: root) else { return false }
        return recordings.contains {
            $0.id != recording.id && $0.folder.standardizedFileURL == recording.folder.standardizedFileURL
        }
    }

    /// Rename a recording, then keep it selected under its new name.
    /// Returns why it could not, or nil when it was renamed.
    func rename(_ recording: Recording, to name: String) async -> String? {
        guard let root else { return "No library folder is chosen." }
        let wasSelected = selection.contains(recording.id)
        let wasOpen = workspace?.recording.id == recording.id
        // The open recording's player holds its files.
        if wasOpen { selection = [] }
        do {
            let (folder, stem) = try RecordingFileOps.rename(recording, to: name, libraryRoot: root)
            // One-folder mode: follow a renamed folder.
            if let i = focusFolders.firstIndex(where: { $0.standardizedFileURL == recording.folder.standardizedFileURL }) {
                focusFolders[i] = folder
                if Self.launchFolder?.standardizedFileURL == recording.folder.standardizedFileURL { Self.launchFolder = folder }
            }
            await rescan()
            let newID = folder.appendingPathComponent(stem).path
            if wasSelected || wasOpen, recordings.contains(where: { $0.id == newID }) { selection = [newID] }
            return nil
        } catch {
            if wasSelected || wasOpen { selection = [recording.id] }
            return error.localizedDescription
        }
    }

    /// Move recordings to the Trash (Finder's Put Back restores them).
    func moveToTrash(_ recs: [Recording]) async {
        guard let root, !recs.isEmpty else { return }
        let ids = Set(recs.map(\.id))
        if let open = workspace?.recording.id, ids.contains(open) { selection = [] }
        selection.subtract(ids)
        var failures: [String] = []
        for rec in recs {
            do { try RecordingFileOps.moveToTrash(rec, libraryRoot: root) } catch {
                failures.append(error.localizedDescription)
            }
        }
        await rescan()
        if !failures.isEmpty { fileOpError = failures.joined(separator: "\n") }
    }

    // MARK: - Remove echo into a copy (2026-11-21)

    /// Progress (0…1) of the one background job on a recording's files
    /// (a cleaned copy, silence being written), and what it is.
    private(set) var jobProgress: Double?
    private(set) var jobLabel: String?

    /// Whether `ids` (the selection by default) is one recording with
    /// separate microphone and system tracks, and no copy is being written.
    func canRemoveEcho(_ ids: Set<String>? = nil) -> Bool {
        let ids = ids ?? selection
        guard jobProgress == nil, ids.count == 1,
              let rec = recordings.first(where: { ids.contains($0.id) }) else { return false }
        return rec.hasEchoReference
    }

    /// Write a copy of the recording with the echo removed from its
    /// microphone track (`RecordingCutExporter.cleanCopy`), then open it.
    /// The original is not changed.
    func removeEchoIntoCopy(_ ids: Set<String>? = nil) {
        let ids = ids ?? selection
        guard canRemoveEcho(ids), let rec = recordings.first(where: { ids.contains($0.id) }) else { return }
        let settings = EchoFilterSettings.load()
        jobProgress = 0
        jobLabel = "Removing echo from \(rec.displayName)"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try RecordingCutExporter.cleanCopy(of: rec, echoSettings: settings) { p in
                        Task { @MainActor in if self.jobProgress != nil { self.jobProgress = p } }
                    }
                }.value
                jobProgress = nil
                await rescan()
                reveal(folder: result.folder)
            } catch {
                jobProgress = nil
                fileOpError = "Removing the echo failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Changing a recording itself (2026-11-22)

    /// Move the mic or system track of `rec` to the Trash and reopen it.
    /// The open recording is closed first: its player holds the files.
    func removeTrack(_ role: AudioTrackRole, from rec: Recording) async {
        guard let root, jobProgress == nil else { return }
        let wasOpen = workspace?.recording.id == rec.id
        if wasOpen { selection = [] }
        do {
            _ = try await Task.detached { try RecordingFileOps.removeTrack(role, from: rec, libraryRoot: root) }.value
        } catch {
            fileOpError = "Removing the track failed: \(error.localizedDescription)"
        }
        await rescan()
        if wasOpen, recordings.contains(where: { $0.id == rec.id }) { selection = [rec.id] }
    }

    /// Write the silenced ranges into the track files of `rec` (the files
    /// as they were go to the Trash) and reopen it.
    func writeSilence(_ silence: ChannelSilence, into rec: Recording) async {
        guard let root, jobProgress == nil else { return }
        let wasOpen = workspace?.recording.id == rec.id
        if wasOpen { selection = [] }
        jobProgress = 0
        jobLabel = "Writing silence into \(rec.displayName)"
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try RecordingFileOps.writeSilence(silence, into: rec, libraryRoot: root) { p in
                    Task { @MainActor in if self.jobProgress != nil { self.jobProgress = p } }
                }
            }.value
        } catch {
            fileOpError = "Writing the silence failed: \(error.localizedDescription)"
        }
        jobProgress = nil
        await rescan()
        if wasOpen, recordings.contains(where: { $0.id == rec.id }) { selection = [rec.id] }
    }

    // MARK: - Join

    /// The join of the selected recordings, when two or more are selected.
    private(set) var joinPlan: JoinPlan?
    private(set) var joinPlanError: String?
    private(set) var joinPreparing = false
    private(set) var joinProgress: Double?
    private(set) var joinError: String?
    @ObservationIgnored private var joinPrepareTask: Task<Void, Never>?

    /// Read the selected recordings and check they can be joined.
    private func prepareJoin() {
        joinPrepareTask?.cancel()
        joinPlan = nil
        joinPlanError = nil
        joinError = nil
        let recs = selectedRecordings
        guard recs.count >= 2 else { joinPreparing = false; return }
        joinPreparing = true
        joinPrepareTask = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<JoinPlan, Error> in
                Result { try RecordingJoiner.plan(try recs.map(JoinPart.load)) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let plan): joinPlan = plan
            case .failure(let error): joinPlanError = error.localizedDescription
            }
            joinPreparing = false
        }
    }

    /// Write the joined recording, then open it.
    func join() {
        guard let plan = joinPlan, joinProgress == nil else { return }
        joinProgress = 0
        joinError = nil
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try RecordingJoiner.join(plan) { p in
                        Task { @MainActor in if self.joinProgress != nil { self.joinProgress = p } }
                    }
                }.value
                joinProgress = nil
                await rescan()
                reveal(folder: result.folder)
            } catch {
                joinProgress = nil
                joinError = "Join failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Search

    var filteredRecordings: [Recording] {
        let words = TranscriptSearchIndex.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return recordings }
        return recordings.filter { r in
            let name = TranscriptSearchIndex.fold(r.displayName + " " + r.stem)
            return words.allSatisfy(name.contains)
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = query
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else {
            hits = []
            searching = false
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let found = await index.search(q, limit: 300)
            guard !Task.isCancelled else { return }
            hits = found
            searching = false
        }
    }
}
