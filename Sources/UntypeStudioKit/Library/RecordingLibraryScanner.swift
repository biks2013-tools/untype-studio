// UntypeStudioKit/Library/RecordingLibraryScanner.swift — plan-024 T2.
//
// Walks a library folder and groups its files into `Recording`s (see
// `Recording.swift` for the naming rules). Pure file-system read: it
// never opens an audio file, so a library of a few hundred recordings
// scans in milliseconds.

import Foundation

public enum RecordingLibraryScanner {

    public static let audioExtensions: Set<String> = ["m4a", "wav", "caf"]
    static let transcriptSuffix = ".transcript.jsonl"
    /// Session-folder files written by ntakker's Save.
    static let sessionNotes = ["transcript.md", "qa.md"]
    /// Folder depth searched below the library root.
    public static let maxDepth = 4

    /// All recordings under `root`, newest first.
    public static func scan(root: URL, fileManager: FileManager = .default) -> [Recording] {
        var out: [Recording] = []
        scanDirectory(root, depth: 0, fileManager: fileManager, into: &out)
        return out.sorted { $0.createdAt > $1.createdAt }
    }

    /// The recordings of one folder (not recursive).
    public static func recordings(inFolder folder: URL, fileManager: FileManager = .default) -> [Recording] {
        let entries = (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let files = entries.filter { !isDirectory($0) }
        return group(files: files, folder: folder)
    }

    private static func scanDirectory(_ dir: URL, depth: Int, fileManager: FileManager, into out: inout [Recording]) {
        let entries = contents(of: dir, fileManager: fileManager)
        var files: [URL] = []
        for entry in entries {
            if isDirectory(entry) {
                if depth < maxDepth, entry.pathExtension != "app" {
                    scanDirectory(entry, depth: depth + 1, fileManager: fileManager, into: &out)
                }
            } else {
                files.append(entry)
            }
        }
        out.append(contentsOf: group(files: files, folder: dir))
    }

    /// The entries of a folder. A link to a folder cannot be listed itself
    /// (FileManager does not follow it), so its target is listed and the
    /// entries are given back through the link's path.
    static func contents(of dir: URL, fileManager: FileManager) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .creationDateKey, .fileSizeKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        guard (try? dir.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else {
            return (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: options)) ?? []
        }
        let target = dir.resolvingSymlinksInPath()
        return ((try? fileManager.contentsOfDirectory(at: target, includingPropertiesForKeys: keys, options: options)) ?? [])
            .map { dir.appendingPathComponent($0.lastPathComponent) }
    }

    /// Group the files of one folder into recordings.
    static func group(files: [URL], folder: URL) -> [Recording] {
        var tracksByStem: [String: [AudioTrack]] = [:]
        for file in files where audioExtensions.contains(file.pathExtension.lowercased()) {
            let base = file.deletingPathExtension().lastPathComponent
            let (stem, role) = splitRole(base)
            tracksByStem[stem, default: []].append(AudioTrack(url: file, role: role))
        }
        guard !tracksByStem.isEmpty else { return [] }

        // Longest stem first, so `x.part01` claims its transcripts
        // before `x` does.
        let stems = tracksByStem.keys.sorted { $0.count > $1.count }
        var transcriptsByStem: [String: [TranscriptFile]] = [:]
        for file in files {
            let name = file.lastPathComponent
            guard name.hasSuffix(transcriptSuffix) else { continue }
            let prefix = String(name.dropLast(transcriptSuffix.count))
            guard let stem = stems.first(where: { prefix == $0 || prefix.hasPrefix($0 + ".") }) else { continue }
            let label = prefix == stem ? "" : String(prefix.dropFirst(stem.count + 1))
            // `x.part01.transcript.jsonl` with no `x.part01` audio is not `x`'s.
            if label.split(separator: ".").first.map(isPartToken) == true { continue }
            transcriptsByStem[stem, default: []].append(TranscriptFile(url: file, label: label))
        }

        let names = Set(files.map(\.lastPathComponent))
        let notes = sessionNotes.filter(names.contains).map { folder.appendingPathComponent($0) }

        // Stems without their `.partNN`: one base means the folder is a
        // single recording's session folder.
        let bases = Set(tracksByStem.keys.map { stem -> String in
            if let last = stem.split(separator: ".").last, isPartToken(last) {
                return String(stem.dropLast(last.count + 1))
            }
            return stem
        })

        return tracksByStem.map { stem, tracks in
            let ordered = tracks.sorted { order($0.role) < order($1.role) }
            let transcripts = (transcriptsByStem[stem] ?? []).sorted { transcriptOrder($0) < transcriptOrder($1) }
            var attachments: [URL] = []
            // untype's video digest (plan-080 of untype) sits beside the recording it was made from.
            for suffix in ["minutes.md", "mic.minutes.md", "system.minutes.md", "studio-qa.md", "digest.html", "digest.docx"] where names.contains("\(stem).\(suffix)") {
                attachments.append(folder.appendingPathComponent("\(stem).\(suffix)"))
            }
            attachments.append(contentsOf: notes)
            let created = ordered.compactMap { creationDate($0.url) }.min() ?? .distantPast
            let size = ordered.reduce(Int64(0)) { $0 + fileSize($1.url) }
            return Recording(
                folder: folder, stem: stem, tracks: ordered, transcripts: transcripts,
                attachments: attachments, createdAt: created, byteSize: size,
                sharesFolder: bases.count > 1,
                kind: names.contains("\(stem).video.json") ? .video : .meeting
            )
        }
    }

    /// `name.mic` → (`name`, .microphone); `name.system` → (`name`, .system).
    static func splitRole(_ base: String) -> (String, AudioTrackRole) {
        if base.hasSuffix(".mic") { return (String(base.dropLast(4)), .microphone) }
        if base.hasSuffix(".system") { return (String(base.dropLast(7)), .system) }
        return (base, .mixed)
    }

    static func isPartToken(_ token: Substring) -> Bool {
        token.count == 6 && token.hasPrefix("part") && Int(token.dropFirst(4)) != nil
    }

    private static func order(_ role: AudioTrackRole) -> Int {
        switch role {
        case .mixed: return 0
        case .microphone: return 1
        case .system: return 2
        }
    }

    private static func transcriptOrder(_ t: TranscriptFile) -> String {
        switch t.label {
        case "": return "0"
        case "microphone": return "1"
        case "system": return "2"
        default: return "3" + t.label
        }
    }

    /// A folder, or a link to one: a library can hold a link to a folder kept
    /// elsewhere (untype's video digests in iCloud Drive, linked as
    /// `<library>/Videos`). The path through the link is kept, so the
    /// recordings in it stay inside the library for renaming and the Trash.
    private static func isDirectory(_ url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return true
        }
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else {
            return false
        }
        return (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    static func creationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
    }

    private static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
