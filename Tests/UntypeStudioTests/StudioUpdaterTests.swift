// FR-STU-32: the studio's own updater (releases, versions, checksums, policy).

import Foundation
import Testing
@testable import UntypeStudioKit

@Suite("Studio updater")
struct StudioUpdaterTests {
    private func latest(tag: String = "v0.9.1", draft: Bool = false, assets: [String] = ["untype-studio-0.9.1.dmg", "untype-studio-0.9.1.zip", "SHA256SUMS"],
                        body: String = "Intro\n\n## Changes in 0.9.1\n\n- **Auto update.** It looks.\n\n## Older\n\nx") -> Data {
        let object: [String: Any] = [
            "tag_name": tag, "draft": draft, "prerelease": false,
            "html_url": "https://github.com/biks2013-tools/untype-studio/releases/tag/\(tag)",
            "body": body,
            "assets": assets.map { ["name": $0, "browser_download_url": "https://github.com/biks2013-tools/untype-studio/releases/download/\(tag)/\($0)"] },
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    @Test("versions compare part by part")
    func versions() throws {
        let v = { (s: String) in try #require(StudioVersion(s)) }
        #expect(try v("0.9.1") > v("0.9.0"))
        #expect(try v("0.10.0") > v("0.9.9"))
        #expect(try v("v1.0") == v("1.0.0"))
        #expect(StudioVersion("0.9.0-beta") == nil)
        #expect(StudioVersion("") == nil)
    }

    @Test("a release is read from GitHub's latest-release answer")
    func parse() throws {
        let r = try #require(StudioRelease.parse(latestRelease: latest()))
        #expect(r.version.description == "0.9.1")
        #expect(r.archiveName == "untype-studio-0.9.1.zip")
        #expect(r.archive.lastPathComponent == "untype-studio-0.9.1.zip")
        #expect(r.checksums.lastPathComponent == "SHA256SUMS")
        #expect(r.changes == "- **Auto update.** It looks.")
    }

    @Test("drafts, other tags and releases without the zip or the checksums are not offered")
    func notReleases() {
        #expect(StudioRelease.parse(latestRelease: latest(draft: true)) == nil)
        #expect(StudioRelease.parse(latestRelease: latest(tag: "nightly")) == nil)
        #expect(StudioRelease.parse(latestRelease: latest(assets: ["untype-studio-0.9.1.dmg", "SHA256SUMS"])) == nil)
        #expect(StudioRelease.parse(latestRelease: latest(assets: ["untype-studio-0.9.1.zip"])) == nil)
    }

    @Test("the checksum of the zip is found in SHA256SUMS")
    func checksum() {
        let a = String(repeating: "a", count: 64), b = String(repeating: "B", count: 64)
        let sums = "\(a)  untype-studio-0.9.1.zip\n\(b)  untype-studio-0.9.1.dmg\n"
        #expect(StudioRelease.checksum(of: "untype-studio-0.9.1.zip", in: sums) == a)
        #expect(StudioRelease.checksum(of: "untype-studio-0.9.1.dmg", in: sums) == b.lowercased())
        #expect(StudioRelease.checksum(of: "other.zip", in: sums) == nil)
    }

    @Test("offered once per version, not when skipped, not while busy")
    func policy() throws {
        let r = try #require(StudioRelease.parse(latestRelease: latest()))
        let old = StudioVersion("0.9.0"), same = StudioVersion("0.9.1")
        #expect(StudioUpdatePolicy().shouldOffer(r, current: old, busy: false))
        #expect(!StudioUpdatePolicy().shouldOffer(r, current: same, busy: false))
        #expect(!StudioUpdatePolicy().shouldOffer(r, current: old, busy: true))
        #expect(!StudioUpdatePolicy(skipped: "0.9.1").shouldOffer(r, current: old, busy: false))
        #expect(!StudioUpdatePolicy(offered: "0.9.1").shouldOffer(r, current: old, busy: false))
        #expect(!StudioUpdatePolicy().shouldOffer(r, current: nil, busy: false))
        let now = Date()
        #expect(StudioUpdatePolicy().isCheckDue(now: now))
        #expect(!StudioUpdatePolicy(lastCheck: now.addingTimeInterval(-60)).isCheckDue(now: now))
        #expect(StudioUpdatePolicy(lastCheck: now.addingTimeInterval(-7 * 3600)).isCheckDue(now: now))
    }

    @Test("the swap script waits, swaps, puts the old app back on failure and reopens")
    func swapScript() {
        let s = StudioUpdateInstaller.swapScript(
            pid: 42, new: URL(fileURLWithPath: "/tmp/w/unpacked/untype-studio.app"),
            installed: URL(fileURLWithPath: "/Applications/untype-studio.app"),
            backup: URL(fileURLWithPath: "/tmp/w/previous.app"), log: URL(fileURLWithPath: "/tmp/update.log"))
        #expect(s.contains("kill -0 42"))
        #expect(s.contains("mv '/Applications/untype-studio.app' '/tmp/w/previous.app'"))
        #expect(s.contains("mv '/tmp/w/previous.app' '/Applications/untype-studio.app'"))
        #expect(s.contains("/usr/bin/open '/Applications/untype-studio.app'"))
    }
}
