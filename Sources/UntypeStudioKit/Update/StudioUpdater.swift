// UntypeStudioKit/Update/StudioUpdater.swift — FR-STU-32 (2026-11-27).
//
// untype studio looks for a newer version among its GitHub releases
// (biks2013-tools/untype-studio, `releases/latest`) and offers to install
// it: the release's notarized zip is downloaded, checked (its SHA-256
// against the release's SHA256SUMS, its signature against the running
// app's own designated requirement), put in the place of the running app,
// and the studio starts again. Ported from untype's updater (its plan-079);
// the studio's versions are `0.9.0`-style, tagged `v0.9.0`.

import CryptoKit
import Foundation
import Security

/// A studio version, `0.9.0` → [0, 9, 0], compared part by part.
public struct StudioVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    /// `0.9.0` or `v0.9.0`; nil for anything else.
    public init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        guard trimmed.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil else { return nil }
        parts = trimmed.split(separator: ".").compactMap { Int($0) }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (a: StudioVersion, b: StudioVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: StudioVersion, b: StudioVersion) -> Bool { !(a < b) && !(b < a) }

    /// The running app's version (`CFBundleShortVersionString`).
    public static var current: StudioVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(StudioVersion.init)
    }
}

/// A release of the studio on GitHub.
public struct StudioRelease: Equatable, Sendable {
    public let tag: String
    public let version: StudioVersion
    /// The release's notes (Markdown).
    public let notes: String
    public let page: URL
    /// The notarized zip of the app, and the file of checksums.
    public let archive: URL
    public let archiveName: String
    public let checksums: URL

    public static func == (a: StudioRelease, b: StudioRelease) -> Bool { a.tag == b.tag && a.archive == b.archive }

    /// The release in GitHub's answer to `releases/latest` (nil when it is
    /// not a release of the app: another tag, a draft, no zip of the app).
    public static func parse(latestRelease data: Data) -> StudioRelease? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let version = StudioVersion(tag), tag.hasPrefix("v"),
              object["draft"] as? Bool != true,
              object["prerelease"] as? Bool != true,
              let page = (object["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = object["assets"] as? [[String: Any]] else {
            return nil
        }
        func asset(_ name: String) -> URL? {
            for asset in assets where asset["name"] as? String == name {
                return (asset["browser_download_url"] as? String).flatMap(URL.init(string:))
            }
            return nil
        }
        // scripts/release.sh: the zip is made again after the ticket is stapled.
        let archiveName = "untype-studio-\(version).zip"
        guard let archive = asset(archiveName), let checksums = asset("SHA256SUMS") else { return nil }
        return StudioRelease(
            tag: tag, version: version, notes: object["body"] as? String ?? "", page: page,
            archive: archive, archiveName: archiveName, checksums: checksums
        )
    }

    /// What changed, for the offer: the "Changes in <version>" part of the
    /// notes (everything when they have none).
    public var changes: String {
        var text = notes
        if let start = notes.range(of: #"(?m)^## Changes in [^\n]*$"#, options: .regularExpression) {
            text = String(notes[start.upperBound...])
            if let next = text.range(of: #"(?m)^## "#, options: .regularExpression) {
                text = String(text[..<next.lowerBound])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The checksum of `name` in a `shasum -a 256` file.
    public static func checksum(of name: String, in sums: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count == 2, parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) == name, parts[0].count == 64 {
                return parts[0].lowercased()
            }
        }
        return nil
    }
}

public enum StudioUpdateError: LocalizedError, Equatable {
    case notAnApp
    case notWritable(String)
    case network(String)
    case checksum
    case unpack(String)
    case signature(String)
    case notNewer
    case busy(String)

    public var errorDescription: String? {
        switch self {
        case .notAnApp:
            return "This copy of untype studio is not an installed app, so it cannot update itself."
        case .notWritable(let folder):
            return "untype studio cannot write in \(folder). Download the new version from the release page and replace the app by hand."
        case .network(let message):
            return "The download failed: \(message)"
        case .checksum:
            return "The downloaded file does not match the checksum published with the release. Nothing was installed."
        case .unpack(let message):
            return "The downloaded file could not be opened: \(message)"
        case .signature(let message):
            return "The downloaded app is not signed as this untype studio is (\(message)). Nothing was installed. Install it from the release page once."
        case .notNewer:
            return "The downloaded app is not newer than the one running. Nothing was installed."
        case .busy(let what):
            return "\(what) Install the update afterwards."
        }
    }
}

/// The steps of installing a release that do not need the user interface.
public enum StudioUpdateInstaller {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/biks2013-tools/untype-studio/releases/latest")!

    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        // A generic client name: nothing about the user or the Mac.
        request.setValue("untype-studio-updater", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        return request
    }

    public static func latestRelease(session: URLSession = .shared) async throws -> StudioRelease? {
        var request = request(latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw StudioUpdateError.network("GitHub answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return StudioRelease.parse(latestRelease: data)
    }

    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The running app's own designated requirement. A Developer ID build
    /// names its team and bundle id, so a later release satisfies it; an
    /// ad-hoc build names only its own code, so nothing else does.
    public static func ownRequirement() throws -> SecRequirement {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement else {
            throw StudioUpdateError.signature("this copy has no signature to compare with")
        }
        return requirement
    }

    /// Whether the running app is signed with a Developer ID (an ad-hoc
    /// build cannot take a release: no release satisfies its requirement).
    public static func isDeveloperIDSigned() -> Bool {
        guard let requirement = try? ownRequirement() else { return false }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return false }
        return (text as String).contains("certificate leaf[subject.OU]")
    }

    /// Checks that `app` is whole, signed, and signed as `requirement` says.
    public static func verify(_ app: URL, satisfies requirement: SecRequirement) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw StudioUpdateError.signature("it cannot be read as an app")
        }
        var error: Unmanaged<CFError>?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidityWithErrors(staticCode, flags, requirement, &error)
        guard status == errSecSuccess else {
            let reason = error.map { CFErrorCopyDescription($0.takeRetainedValue()) as String } ?? "status \(status)"
            throw StudioUpdateError.signature(reason)
        }
    }

    static func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Downloads, checks and unpacks `release` next to `installed` (same
    /// volume). Returns the new app, ready to take its place.
    public static func prepare(
        _ release: StudioRelease,
        replacing installed: URL,
        current: StudioVersion,
        requirement givenRequirement: SecRequirement? = nil,
        session: URLSession = .shared,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        guard installed.pathExtension == "app" else { throw StudioUpdateError.notAnApp }
        let parent = installed.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path), FileManager.default.isWritableFile(atPath: installed.path) else {
            throw StudioUpdateError.notWritable(parent.path)
        }
        let requirement = try givenRequirement ?? ownRequirement()
        let work = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: installed, create: true)

        progress("Downloading \(release.version)…")
        let archive = work.appendingPathComponent(release.archiveName)
        do {
            let (downloaded, response) = try await session.download(for: request(release.archive))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw StudioUpdateError.network("the server answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            try FileManager.default.moveItem(at: downloaded, to: archive)
            let (sums, sumsResponse) = try await session.data(for: request(release.checksums))
            guard (sumsResponse as? HTTPURLResponse)?.statusCode == 200 else {
                throw StudioUpdateError.network("the checksums could not be read")
            }
            progress("Checking the download…")
            guard let expected = StudioRelease.checksum(of: release.archiveName, in: String(decoding: sums, as: UTF8.self)),
                  try sha256(of: archive) == expected else {
                throw StudioUpdateError.checksum
            }
        } catch let error as StudioUpdateError {
            throw error
        } catch {
            throw StudioUpdateError.network(error.localizedDescription)
        }

        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        let ditto = try run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
        guard ditto.status == 0 else {
            throw StudioUpdateError.unpack(ditto.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let app = unpacked.appendingPathComponent(installed.lastPathComponent)
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw StudioUpdateError.unpack("it does not hold \(installed.lastPathComponent)")
        }
        try verify(app, satisfies: requirement)
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let version = (info?["CFBundleShortVersionString"] as? String).flatMap(StudioVersion.init),
              version > current, version == release.version else {
            throw StudioUpdateError.notNewer
        }
        return app
    }

    /// The script that takes over when the studio quits: it waits for the
    /// process to end, puts the new app in the place of the old one (which
    /// comes back if that fails) and opens it.
    public static func swapScript(pid: Int32, new: URL, installed: URL, backup: URL, log: URL) -> String {
        func quoted(_ url: URL) -> String {
            "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return """
        #!/bin/sh
        exec >> \(quoted(log)) 2>&1
        echo "$(date -u +%FT%TZ) update: waiting for untype studio (\(pid)) to quit"
        n=0
        while kill -0 \(pid) 2>/dev/null; do
          n=$((n + 1))
          if [ "$n" -gt 300 ]; then echo "update: untype studio did not quit; nothing was changed"; exit 1; fi
          sleep 0.2
        done
        if mv \(quoted(installed)) \(quoted(backup)); then
          if mv \(quoted(new)) \(quoted(installed)); then
            echo "$(date -u +%FT%TZ) update: installed"
            rm -rf \(quoted(backup))
          else
            echo "update: the new app could not be put in place; the previous one is back"
            mv \(quoted(backup)) \(quoted(installed))
          fi
        else
          echo "update: the installed app could not be moved; nothing was changed"
        fi
        /usr/bin/open \(quoted(installed))
        """
    }

    /// Starts the swap script, which outlives the studio.
    public static func startSwap(new: URL, installed: URL, log: URL) throws {
        let work = new.deletingLastPathComponent().deletingLastPathComponent()
        let script = work.appendingPathComponent("swap.sh")
        let backup = work.appendingPathComponent("previous.app")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try swapScript(pid: ProcessInfo.processInfo.processIdentifier, new: new, installed: installed, backup: backup, log: log)
            .write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

/// When to look for a release and when to offer it.
public struct StudioUpdatePolicy: Equatable, Sendable {
    /// Between two looks at GitHub.
    public static let checkInterval: TimeInterval = 6 * 3600

    public var lastCheck: Date?
    /// The version the user said to skip.
    public var skipped: String?
    /// The version already offered since the studio started.
    public var offered: String?

    public init(lastCheck: Date? = nil, skipped: String? = nil, offered: String? = nil) {
        self.lastCheck = lastCheck
        self.skipped = skipped
        self.offered = offered
    }

    public func isCheckDue(now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= Self.checkInterval
    }

    public static func isNewer(_ release: StudioRelease, than current: StudioVersion?) -> Bool {
        guard let current else { return false }
        return release.version > current
    }

    /// Whether to put the offer in front of the user now: once per version
    /// and start, not a skipped version, and not while minutes are being
    /// written or a copy is being made.
    public func shouldOffer(_ release: StudioRelease, current: StudioVersion?, busy: Bool) -> Bool {
        Self.isNewer(release, than: current)
            && release.version.description != skipped
            && release.version.description != offered
            && !busy
    }
}
