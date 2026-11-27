// untype-studio/Model/StudioUpdateModel.swift — FR-STU-32 (2026-11-27).
//
// The updater as the app sees it: a look at GitHub 30 s after the start
// and every 6 hours (Settings ▸ General ▸ Updates can turn it off), an
// offer window once per version, and Install and Restart. The steps that
// need no interface are in UntypeStudioKit/Update/StudioUpdater.swift.

import AppKit
import Logging
import SwiftUI
import UntypeStudioKit

@MainActor
@Observable
final class StudioUpdateModel {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case installing(String)
        case failed(String)
    }

    static let shared = StudioUpdateModel()

    private static let automaticKey = "studio.updates.automatic"
    private static let skippedKey = "studio.updates.skipped"

    private(set) var phase: Phase = .idle
    private(set) var release: StudioRelease?
    private(set) var lastChecked: Date?
    /// Look for new versions without being asked (on until switched off).
    var checksAutomatically: Bool {
        didSet { defaults.set(checksAutomatically, forKey: Self.automaticKey) }
    }

    /// What the studio is busy with, if anything (then nothing is installed).
    var busyReason: () -> String? = { nil }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let logger = Logger(label: "untype-studio.update")
    @ObservationIgnored private var policy: StudioUpdatePolicy
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var window: NSWindow?
    let current = StudioVersion.current
    /// Only a Developer ID signed, installed app can take a release.
    let isSigned = StudioUpdateInstaller.isDeveloperIDSigned()

    private init() {
        checksAutomatically = defaults.object(forKey: Self.automaticKey) as? Bool ?? true
        policy = StudioUpdatePolicy(skipped: defaults.string(forKey: Self.skippedKey))
    }

    var isInstalledApp: Bool { current != nil && Bundle.main.bundleURL.pathExtension == "app" }
    var canUpdate: Bool { isInstalledApp && isSigned }

    var isUpdateAvailable: Bool {
        release.map { StudioUpdatePolicy.isNewer($0, than: current) } ?? false
    }

    var versionLabel: String { current?.description ?? "development build" }

    /// Looks a little after the start, then keeps looking.
    func start() {
        guard canUpdate, timer == nil else { return }
        let timer = Timer(timeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            self?.tick()
        }
    }

    private func tick() {
        guard checksAutomatically else { return }
        if policy.isCheckDue(now: Date()) {
            check(userAsked: false)
        } else {
            offerIfDue()
        }
    }

    /// Looks for a newer release now.
    func check(userAsked: Bool) {
        guard canUpdate, phase != .checking else { return }
        if case .installing = phase { return }
        phase = .checking
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let latest = try await StudioUpdateInstaller.latestRelease()
                policy.lastCheck = Date()
                lastChecked = policy.lastCheck
                if let latest, StudioUpdatePolicy.isNewer(latest, than: current) {
                    if release?.version != latest.version {
                        logger.info("update: \(latest.version) is available (this is \(versionLabel))")
                    }
                    release = latest
                    phase = .available
                    if userAsked {
                        policy.offered = latest.version.description
                        showOffer()
                    } else {
                        offerIfDue()
                    }
                } else {
                    release = nil
                    phase = .upToDate
                }
            } catch {
                // An automatic look that fails is tried again later, quietly.
                phase = userAsked ? .failed("Could not look for updates: \(error.localizedDescription)") : .idle
                logger.warning("update check failed: \(error.localizedDescription)")
            }
        }
    }

    private func offerIfDue() {
        guard let release, policy.shouldOffer(release, current: current, busy: busyReason() != nil) else { return }
        policy.offered = release.version.description
        showOffer()
    }

    /// "Skip This Version": not offered again; the next one is.
    func skip() {
        guard let release else { return }
        policy.skipped = release.version.description
        defaults.set(release.version.description, forKey: Self.skippedKey)
    }

    /// Downloads, checks and installs the release, then restarts the studio.
    func install() {
        guard let release, let current else { return }
        if case .installing = phase { return }
        if let reason = busyReason() {
            phase = .failed(StudioUpdateError.busy(reason).localizedDescription)
            return
        }
        phase = .installing("Starting…")
        logger.info("update: installing \(release.version)")
        let installed = Bundle.main.bundleURL
        Task { @MainActor [weak self] in
            do {
                let new = try await StudioUpdateInstaller.prepare(release, replacing: installed, current: current) { message in
                    Task { @MainActor in self?.phase = .installing(message) }
                }
                guard let self else { return }
                // The download took a while: minutes may have started.
                if let reason = busyReason() { throw StudioUpdateError.busy(reason) }
                phase = .installing("Restarting untype studio…")
                let log = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".tool-agents/untype-studio/update.log")
                try StudioUpdateInstaller.startSwap(new: new, installed: installed, log: log)
                logger.info("update: \(release.version) downloaded and checked; restarting")
                NSApp.terminate(nil)
            } catch {
                self?.phase = .failed(error.localizedDescription)
                self?.logger.warning("update not installed: \(error.localizedDescription)")
            }
        }
    }

    /// The offer window, in front without taking the keyboard.
    func showOffer() {
        let window = self.window ?? {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "untype studio update"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: StudioUpdateView(model: self, close: { [weak self] in self?.window?.close() }))
            w.center()
            return w
        }()
        self.window = window
        window.orderFrontRegardless()
    }
}

struct StudioUpdateView: View {
    let model: StudioUpdateModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let release = model.release {
                Text("untype studio \(release.version.description) is available").font(.headline)
                Text("You have \(model.versionLabel).").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    MarkdownText(markdown: release.changes)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 220)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                status
                HStack {
                    Button("Skip This Version") { model.skip(); close() }
                        .disabled(isInstalling)
                    Button("Release Page") { NSWorkspace.shared.open(release.page) }
                    Spacer()
                    Button("Later", action: close).disabled(isInstalling)
                    Button("Install and Restart") { model.install() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isInstalling)
                }
            } else {
                Text("untype studio is up to date.")
                Button("Close", action: close)
            }
        }
        .padding(18)
        .frame(width: 480)
    }

    private var isInstalling: Bool {
        if case .installing = model.phase { return true }
        return false
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .installing(let message):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        default:
            Text("The download is checked against the release's checksum and this app's own signature before anything is replaced. The studio restarts; your settings and recordings stay.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Settings ▸ General ▸ Updates.
struct StudioUpdateSettingsSection: View {
    @Bindable var model: StudioUpdateModel

    var body: some View {
        Section("Updates") {
            Toggle("Look for new versions automatically", isOn: $model.checksAutomatically)
                .disabled(!model.canUpdate)
            LabeledContent(statusText) {
                HStack {
                    if model.isUpdateAvailable { Button("Show…") { model.showOffer() } }
                    Button("Check Now") { model.check(userAsked: true) }
                        .disabled(!model.canUpdate || model.phase == .checking)
                }
            }
        }
    }

    private var statusText: String {
        if !model.isInstalledApp { return "This copy of untype studio is not an installed app" }
        if !model.isSigned { return "This copy was built locally (not Developer ID signed), so it cannot update itself. Install a release once." }
        switch model.phase {
        case .checking: return "Looking…"
        case .available: return model.release.map { "\($0.version.description) is available" } ?? "A new version is available"
        case .installing(let message): return message
        case .failed(let message): return message
        case .upToDate: return "untype studio is up to date (\(model.versionLabel))"
        case .idle: return "untype studio \(model.versionLabel)"
        }
    }
}
