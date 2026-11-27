// untype-studio/UntypeStudioApp.swift — plan-024 T9.
//
// The recordings explorer that sits next to ntakker: browse the library,
// study transcripts against the audio, cut, ask, write minutes,
// re-transcribe. A normal Dock app (bundle id com.giorgosmarinos.untype-studio).
//
// At launch it loads `~/.tool-agents/ntakker/.env` into the process, so
// Ask / minutes and re-transcription use the same settings as ntakker.

import AppKit
import Logging
import NtakkerCore
import SwiftUI

/// The app; started by `StudioMain` (StudioCommandLine.swift) when no
/// command is given.
struct UntypeStudioApp: App {
    @NSApplicationDelegateAdaptor(StudioAppDelegate.self) private var appDelegate
    @State private var library = LibraryStore()

    var body: some Scene {
        WindowGroup("untype studio", id: "main") {
            ContentView()
                .environment(library)
                .frame(minWidth: 1180, minHeight: 680)
                .task { await library.rescan() }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Choose Library Folder…") { library.chooseFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Rescan Library") { Task { await library.rescan() } }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Rename Recording…") { library.requestRename() }
                    .disabled(library.selection.count != 1)
                Button("Rename After Minutes…") { library.requestRename(from: .minutes) }
                    .disabled(!library.canRename(from: .minutes))
                Button("Rename After Linked Meeting…") { library.requestRename(from: .meeting) }
                    .disabled(!library.canRename(from: .meeting))
                Button("Remove Echo into a Copy") { library.removeEchoIntoCopy() }
                    .disabled(!library.canRemoveEcho())
                Button("Move to Trash") { library.requestTrash() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(library.selection.isEmpty)
            }
            CommandGroup(after: .toolbar) {
                StudioAppearancePicker()
            }
            CommandMenu("Playback") {
                Button("Play / Pause") { library.workspace?.player.togglePlay() }
                    .keyboardShortcut(.space, modifiers: .option)
                Button("Back 5 Seconds") { library.workspace?.player.skip(by: -5) }
                    .keyboardShortcut(.leftArrow, modifiers: .option)
                Button("Forward 5 Seconds") { library.workspace?.player.skip(by: 5) }
                    .keyboardShortcut(.rightArrow, modifiers: .option)
            }
        }

        Settings {
            StudioSettingsView()
                .environment(library)
        }
    }
}

final class StudioAppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(label: "untype-studio.app")

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before any window opens, so a dark choice never flashes light.
        StudioAppearance.apply(StudioAppearance.current.rawValue)
        do {
            let loaded = try EnvFileStore.loadIntoProcess(toolName: "ntakker")
            logger.info("loaded \(loaded.count) settings from ~/.tool-agents/ntakker/.env")
        } catch {
            logger.error("could not load ~/.tool-agents/ntakker/.env: \(error)")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        PlaybackKeys.install()
    }

    /// Quitting (also by closing the window) would drop minutes that are
    /// still being written: ask first. (2026-11-26)
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = LibraryStore.current?.minutesJobs.running ?? []
        guard !running.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = running.count == 1
            ? "The minutes of “\(running[0].recordingName)” are still being written."
            : "The minutes of \(running.count) recordings are still being written."
        alert.informativeText = "Quitting now stops them; nothing is saved for them, and minutes written earlier stay as they are."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit Anyway")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Space plays / pauses and ←/→ skip 5 s, unless a text field has focus;
/// in a text field the system's editing keys keep their meaning.
@MainActor
enum PlaybackKeys {
    static var player: (() -> PlayerController?)?
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // While text is being edited, the arrows and Delete with
            // Command or Option are the system's editing keys (word and
            // line moves, with Shift to select, delete word / to line
            // start). They go straight to the text, before the menu's
            // shortcuts (Option-←/→ skip, Command-Delete Move to Trash)
            // or anything else can take them. (2026-11-22)
            if let text = NSApp.keyWindow?.firstResponder as? NSTextView,
               !event.modifierFlags.intersection([.command, .option]).isEmpty,
               [123, 124, 125, 126, 51, 117].contains(event.keyCode) {
                text.interpretKeyEvents([event])
                return nil
            }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSText),
                  let p = player?() else { return event }
            switch event.keyCode {
            case 49: p.togglePlay(); return nil          // space
            case 123: p.skip(by: -5); return nil         // ←
            case 124: p.skip(by: 5); return nil          // →
            default: return event
            }
        }
    }
}
