// untype-studio/Views/InspectorPane.swift — plan-024 T9.

import AppKit
import NtakkerCore
import UntypeStudioKit
import SwiftUI

struct InspectorPane: View {
    let workspace: RecordingWorkspace
    @AppStorage("studio.inspectorTab") private var tab = Tab.ask

    enum Tab: String, CaseIterable, Identifiable {
        case ask = "Ask", minutes = "Minutes", speakers = "Speakers", cut = "Cut", retranscribe = "Re-transcribe", info = "Info"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .ask: return "bubble.left.and.text.bubble.right"
            case .minutes: return "list.bullet.clipboard"
            case .speakers: return "person.2"
            case .cut: return "scissors"
            case .retranscribe: return "waveform.badge.magnifyingglass"
            case .info: return "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tool", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Image(systemName: t.icon).help(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            Text(tab.rawValue).font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
            Divider().padding(.top, 6)
            Group {
                switch tab {
                case .ask: AskPanel(workspace: workspace)
                case .minutes: MinutesPanel(workspace: workspace)
                case .speakers: SpeakersPanel(workspace: workspace)
                case .cut: CutPanel(workspace: workspace)
                case .retranscribe: RetranscribePanel(workspace: workspace)
                case .info: InfoPanel(workspace: workspace)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Ask

struct AskPanel: View {
    let workspace: RecordingWorkspace
    @State private var question = ""

    private let suggestions = [
        "What were the main points?",
        "What did we agree on?",
        "Which open questions remain?",
        "What did each participant want?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if workspace.exchanges.isEmpty && !workspace.isAsking {
                            Text("Ask anything about this recording. Answers cite the moments they rely on — click a time to listen.")
                                .foregroundStyle(.secondary)
                            ForEach(suggestions, id: \.self) { s in
                                Button(s) { workspace.ask(s) }.buttonStyle(.link)
                            }
                        }
                        ForEach(Array(workspace.exchanges.enumerated()), id: \.offset) { _, x in
                            ExchangeView(question: x.question, answer: x.answer)
                        }
                        if let q = workspace.pendingQuestion {
                            ExchangeView(question: q, answer: workspace.streamingAnswer.isEmpty ? "…" : workspace.streamingAnswer)
                                .id("pending")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .onChange(of: workspace.streamingAnswer) { _, _ in proxy.scrollTo("pending", anchor: .bottom) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .bottom) {
                    TextField("Ask about this recording", text: $question, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .onSubmit(send)
                    if workspace.isAsking {
                        Button("Stop") { workspace.stopAsking() }
                    } else {
                        Button("Ask", action: send)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || workspace.entries.isEmpty)
                    }
                }
                Text(footer).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    private var footer: String {
        let who = workspace.askProviderLine.map { "Using \($0)" } ?? "Uses ntakker's Ask settings"
        return "\(who) · the whole transcript is sent · answers are saved to \(workspace.recording.studioQAURL.lastPathComponent)"
    }

    private func send() {
        workspace.ask(question)
        question = ""
    }
}

struct ExchangeView: View {
    let question: String
    let answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question).font(.body.bold()).textSelection(.enabled)
            MarkdownText(markdown: answer)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Minutes

struct MinutesPanel: View {
    @Environment(LibraryStore.self) private var library
    let workspace: RecordingWorkspace
    @AppStorage("studio.minutesLanguage") private var language = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Language (blank: as spoken)", text: $language)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                Spacer()
                if workspace.minutesGenerating {
                    ProgressView().controlSize(.small)
                    Button("Stop") { workspace.stopMinutes() }
                } else {
                    Button(workspace.minutes.isEmpty ? "Write Minutes" : "Rewrite") {
                        let l = language.trimmingCharacters(in: .whitespaces)
                        workspace.generateMinutes(language: l.isEmpty ? nil : l)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(workspace.entries.isEmpty)
                }
            }
            .padding(12)
            Divider()
            ScrollView {
                if workspace.minutes.isEmpty && !workspace.minutesGenerating {
                    Text("Minutes summarise the meeting: topics, decisions, action items and open questions, each linked to the moment it was said. They are saved to \(workspace.recording.minutesURL.lastPathComponent).")
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    MarkdownText(markdown: workspace.minutes).padding(12)
                }
            }
            if !workspace.minutes.isEmpty && !workspace.minutesGenerating {
                Divider()
                HStack {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(workspace.minutes, forType: .string)
                    }
                    if FileManager.default.fileExists(atPath: workspace.recording.minutesURL.path) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([workspace.recording.minutesURL]) }
                        Button("Open") { NSWorkspace.shared.open(workspace.recording.minutesURL) }
                    }
                    Spacer()
                    if let title = RecordingNaming.minutesTitle(workspace.minutes) {
                        Button("Rename After Title…") {
                            library.requestRename(workspace.recording, after: title, start: workspace.audioStart)
                        }
                        .help("Name the recording after the minutes' title, “\(title)”, in front of its date and time.")
                    }
                }
                .padding(10)
            }
        }
    }
}

// MARK: - Speakers

struct SpeakersPanel: View {
    let workspace: RecordingWorkspace
    @State private var drafts: [String: String] = [:]

    var body: some View {
        let speakers = workspace.speakers
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if speakers.isEmpty {
                    Text("No speakers yet — the transcript is empty.").foregroundStyle(.secondary)
                } else if speakers.allSatisfy({ $0.raw == nil }) {
                    Text("This transcript has no speaker labels (the provider did not separate speakers), so lines are labelled by source.")
                        .foregroundStyle(.secondary)
                }
                ForEach(speakers, id: \.key) { s in
                    HStack {
                        Circle().fill(SpeakerColor.color(for: s.key)).frame(width: 10, height: 10)
                        if let raw = s.raw {
                            TextField(workspace.metadata.speakerName(for: raw) ?? raw, text: Binding(
                                get: { drafts[raw] ?? workspace.metadata.speakerNames[raw] ?? "" },
                                set: { drafts[raw] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { save(raw) }
                        } else {
                            Text(s.label)
                        }
                        Text("\(s.count) lines").font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
                        Button {
                            workspace.player.seek(to: s.first)
                            workspace.player.play()
                        } label: { Image(systemName: "play.circle") }
                        .buttonStyle(.borderless)
                        .help("Hear this speaker's first line")
                    }
                }
                if speakers.contains(where: { $0.raw != nil }) {
                    HStack {
                        Spacer()
                        Button("Save Names") { for s in speakers { if let raw = s.raw { save(raw) } } }
                            .buttonStyle(.borderedProminent)
                            .disabled(drafts.isEmpty)
                    }
                    Text("Names are saved to \(workspace.recording.metadataURL.lastPathComponent) and used in the transcript, Ask and minutes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    private func save(_ raw: String) {
        guard let d = drafts[raw] else { return }
        workspace.renameSpeaker(raw: raw, to: d)
        drafts[raw] = nil
    }
}

// MARK: - Cut

struct CutPanel: View {
    @Environment(LibraryStore.self) private var library
    let workspace: RecordingWorkspace
    /// The track "Remove from This Recording" is asking about.
    @State private var trackToRemove: AudioTrackRole?

    var body: some View {
        let long = workspace.duration >= 3600
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(workspace.canSilence
                     ? "Drag across the waveform (or use a line's menu) to select a range, then add it as a cut, make a new recording from it — or, dragged on the Mic or System lane, silence it on that channel only, to take out a noise heard on one side. Export writes a new copy without the cuts (transcript times shifted to match), with the silenced ranges silent, and optionally with the echo removed from the microphone. The original changes only with Remove from This Recording and Write to This Recording; what they replace goes to the Trash."
                     : "Drag across the waveform (or use a line's menu) to select a range, then add it as a cut. Export writes a new copy without the cuts, transcript times shifted to match, and optionally with the echo removed from the microphone. The original is never changed.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("Selection") {
                    if let s = workspace.selection {
                        HStack {
                            Text("\(StudioAsk.timecode(s.start, longForm: long)) – \(StudioAsk.timecode(s.end, longForm: long))")
                                .monospacedDigit()
                            Text(String(format: "(%.1f s)", s.duration)).foregroundStyle(.secondary)
                            Spacer()
                            Button("Play") { workspace.player.seek(to: s.start); workspace.player.play() }
                            Button("Add as Cut") { workspace.addSelectionAsCut() }
                                .buttonStyle(.borderedProminent)
                        }
                        if workspace.canSilence {
                            HStack {
                                Text("Silence on").foregroundStyle(.secondary)
                                ForEach([AudioTrackRole.microphone, .system], id: \.self) { role in
                                    let button = Button(role == .microphone ? "Mic" : "System") { workspace.silenceSelection(on: role) }
                                        .help("Replace this range with silence on the \(role == .microphone ? "microphone" : "system") track only (in the exported copy; heard as silence now)")
                                    if workspace.selectionRole == role {
                                        button.buttonStyle(.borderedProminent)
                                    } else {
                                        button
                                    }
                                }
                                Spacer()
                            }
                        }
                        HStack {
                            Text("New recording from").foregroundStyle(.secondary)
                            if workspace.canSilence {
                                Button("Both") { workspace.newRecording(range: s, onlyRole: nil) }
                                    .help("Write a new recording with this range of the microphone and the system track")
                                ForEach([AudioTrackRole.microphone, .system], id: \.self) { role in
                                    Button(role == .microphone ? "Mic" : "System") { workspace.newRecording(range: s, onlyRole: role) }
                                        .help("Write a new recording with this range of the \(role == .microphone ? "microphone" : "system") track only")
                                }
                            } else {
                                Button("This Range") { workspace.newRecording(range: s, onlyRole: nil) }
                                    .help("Write a new recording with this range only")
                            }
                            Spacer()
                        }
                        .disabled(workspace.exportProgress != nil || s.duration <= 0.05)
                    } else {
                        Text("Nothing selected").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GroupBox("Cuts") {
                    VStack(alignment: .leading, spacing: 6) {
                        if workspace.cuts.isEmpty {
                            Text("No cuts yet").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(workspace.cuts) { c in
                            HStack {
                                Text("\(StudioAsk.timecode(c.start, longForm: long)) – \(StudioAsk.timecode(c.end, longForm: long))").monospacedDigit()
                                Text(String(format: "(%.1f s)", c.duration)).foregroundStyle(.secondary)
                                Spacer()
                                Button { workspace.player.seek(to: max(0, c.start - 3)); workspace.player.play() } label: { Image(systemName: "play.circle") }
                                    .help("Play from 3 s before the cut")
                                Button { workspace.removeCut(c) } label: { Image(systemName: "trash") }
                                    .help("Remove this cut")
                            }
                            .buttonStyle(.borderless)
                        }
                        if !workspace.cuts.isEmpty {
                            Divider()
                            let plan = workspace.cutPlan
                            Text("Removes \(StudioAsk.timecode(plan.removedDuration, longForm: true)); the copy will be \(StudioAsk.timecode(plan.resultDuration, longForm: true)) long.")
                                .font(.callout)
                        }
                    }
                }

                if workspace.canSilence {
                    SilencedBox(workspace: workspace, long: long)
                    GroupBox("Tracks") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("New recording with only").foregroundStyle(.secondary)
                                ForEach([AudioTrackRole.microphone, .system], id: \.self) { role in
                                    Button(role == .microphone ? "Mic" : "System") { workspace.newRecording(range: nil, onlyRole: role) }
                                        .help("Write a new recording that holds the whole \(role == .microphone ? "microphone" : "system") track and its transcript lines")
                                }
                                Spacer()
                            }
                            .disabled(workspace.exportProgress != nil)
                            HStack {
                                Text("Remove from this recording").foregroundStyle(.secondary)
                                ForEach([AudioTrackRole.microphone, .system], id: \.self) { role in
                                    Button(role == .microphone ? "Mic…" : "System…", role: .destructive) { trackToRemove = role }
                                        .help("Move the \(role == .microphone ? "microphone" : "system") track of this recording, and its transcript, to the Trash")
                                }
                                Spacer()
                            }
                            .disabled(workspace.exportProgress != nil)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if workspace.canRemoveEcho {
                    Toggle(isOn: Binding(get: { workspace.exportRemovesEcho }, set: { workspace.exportRemovesEcho = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remove echo from the microphone")
                            Text("Subtracts the system audio the mic picked up from the speakers, over the whole track. Useful before re-transcribing the copy. Takes about a minute per hour of audio.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                HStack {
                    if let p = workspace.exportProgress {
                        ProgressView(value: p).frame(maxWidth: 180)
                        Text(workspace.exportRemovesEcho && p < 0.7 ? "Removing echo…" : "Writing the copy…").foregroundStyle(.secondary)
                    } else {
                        Button("Clear Cuts") { workspace.clearCuts() }.disabled(workspace.cuts.isEmpty)
                        Spacer()
                        Button("Export Copy") { workspace.exportCut() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!workspace.hasEdits)
                    }
                }

                if let r = workspace.lastExport {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Saved \(r.folder.lastPathComponent)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(exportSummary(r))
                                .font(.callout).foregroundStyle(.secondary)
                            HStack {
                                Button("Open the Copy") { library.reveal(folder: r.folder) }
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([r.folder]) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .confirmationDialog(
            "Remove the \(trackToRemove == .microphone ? "microphone" : "system") track from this recording?",
            isPresented: Binding(get: { trackToRemove != nil }, set: { if !$0 { trackToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Move the Track to the Trash", role: .destructive) {
                guard let role = trackToRemove else { return }
                trackToRemove = nil
                workspace.pinAudioStart()
                let rec = workspace.recording
                Task { await library.removeTrack(role, from: rec) }
            }
            Button("Cancel", role: .cancel) { trackToRemove = nil }
        } message: {
            Text("Its audio file and the transcript of that channel go to the Trash; the recording keeps the other track. Finder's Put Back restores them. Cuts and silences not yet exported are dropped.")
        }
    }
}

private func exportSummary(_ r: CutExportResult) -> String {
    var parts: [String] = []
    if let role = r.onlyRole {
        parts.append("Holds the \(role == .microphone ? "microphone" : "system") track only.")
    }
    if r.isExtract {
        parts.append("A new recording from the selected range; \(r.droppedLines) transcript lines outside it left out.")
    } else if r.removedSeconds > 0 {
        parts.append("Removed \(StudioAsk.timecode(r.removedSeconds, longForm: true)) and \(r.droppedLines) transcript lines.")
    }
    if let d = r.echoDelay {
        parts.append("Echo removed from the microphone (echo delay \(Int(d * 1000)) ms).")
    }
    for (role, name) in [(AudioTrackRole.microphone, "microphone"), (.system, "system audio")] {
        if let secs = r.silencedSeconds[role] {
            parts.append("Silenced \(StudioAsk.timecode(secs, longForm: true)) of the \(name).")
        }
    }
    return parts.joined(separator: " ")
}

/// The ranges silenced on each channel, with "whole track" shortcuts.
private struct SilencedBox: View {
    @Environment(LibraryStore.self) private var library
    let workspace: RecordingWorkspace
    let long: Bool
    @State private var confirmWrite = false

    var body: some View {
        GroupBox("Silenced") {
            VStack(alignment: .leading, spacing: 6) {
                if workspace.silence.isEmpty {
                    Text("Nothing silenced. Drag on the Mic or System lane, then press Silence on Mic / System.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach([AudioTrackRole.microphone, .system], id: \.self) { role in
                    let name = role == .microphone ? "Mic" : "System"
                    ForEach(workspace.silence.ranges(for: role)) { r in
                        HStack {
                            Text(name).font(.caption.bold()).frame(width: 46, alignment: .leading)
                            Text("\(StudioAsk.timecode(r.start, longForm: long)) – \(StudioAsk.timecode(r.end, longForm: long))").monospacedDigit()
                            Text(String(format: "(%.1f s)", r.duration)).foregroundStyle(.secondary)
                            Spacer()
                            Button { workspace.player.seek(to: max(0, r.start - 3)); workspace.player.play() } label: { Image(systemName: "play.circle") }
                                .help("Play from 3 s before")
                            Button { workspace.removeSilence(r, from: role) } label: { Image(systemName: "trash") }
                                .help("Hear this range again (remove the silence)")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Divider()
                HStack {
                    Button("Silence Whole Mic") { workspace.silenceWholeTrack(.microphone) }
                        .help("Silence the microphone track over the whole recording in the copy")
                    Button("Silence Whole System") { workspace.silenceWholeTrack(.system) }
                        .help("Silence the system-audio track over the whole recording in the copy")
                    Spacer()
                    Button("Clear") { workspace.clearSilences() }.disabled(workspace.silence.isEmpty)
                }
                .controlSize(.small)
                HStack {
                    Button("Write to This Recording…", role: .destructive) { confirmWrite = true }
                        .disabled(workspace.silence.isEmpty || workspace.exportProgress != nil)
                        .help("Write the silenced ranges into this recording's own track files; the files as they are now go to the Trash")
                    Spacer()
                }
                .controlSize(.small)
                Text("Silenced ranges are heard as silence now and written silent by Export Copy and New recording, or into this recording itself by Write to This Recording. The transcript lines are kept.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog("Write the silence into this recording?", isPresented: $confirmWrite, titleVisibility: .visible) {
            Button("Write the Silence", role: .destructive) {
                workspace.pinAudioStart()
                let rec = workspace.recording, silence = workspace.silence
                Task { await library.writeSilence(silence, into: rec) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The track files with silenced ranges are rewritten, in the same format and length. The files as they are now go to the Trash (Finder's Put Back restores them, once the rewritten file is moved away). Cuts not yet exported are dropped.")
        }
    }
}

// MARK: - Re-transcribe

struct RetranscribePanel: View {
    let workspace: RecordingWorkspace
    @AppStorage("studio.retranscribeProvider") private var provider = "parakeet"
    @AppStorage("studio.retranscribeLanguages") private var languages = ""

    private let names: [String: String] = [
        "parakeet": "Parakeet (on this Mac)",
        "whisperkit": "WhisperKit (on this Mac)",
        "gemini": "Google Gemini",
        "azure": "Azure OpenAI",
        "elevenlabs": "ElevenLabs",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Run the recording through a transcription provider again, for a better transcript or one from a different engine. The result is saved as a new transcript next to the recording, with exact timing; the existing ones stay.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Provider", selection: $provider) {
                    ForEach(Retranscriber.batchProviderIds, id: \.self) { id in Text(names[id] ?? id).tag(id) }
                }
                TextField("Languages, e.g. el, en (blank: provider decides)", text: $languages)
                    .textFieldStyle(.roundedBorder)
                Text("Keys and models come from ntakker's settings (~/.tool-agents/ntakker/.env). Soniox, Apple and Azure Realtime only work live, so they are not offered here.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let p = workspace.retranscribeProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: p.fraction)
                        HStack {
                            Text("\(Int(p.fraction * 100))% · \(p.segmentsSoFar) lines").monospacedDigit()
                            Spacer()
                            Button("Cancel") { workspace.cancelRetranscribe() }
                        }
                        if let t = p.lastText {
                            Text(t).font(.callout).foregroundStyle(.secondary).truncationTooltip(t, lines: 3)
                        }
                    }
                } else {
                    HStack {
                        Spacer()
                        Button("Re-transcribe") {
                            let langs = languages.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                            workspace.retranscribe(providerId: provider, languages: langs)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                if let done = workspace.retranscribeDone {
                    Label("Wrote \(done.segmentCount) lines to \(done.files.map(\.lastPathComponent).joined(separator: ", ")). It is now the transcript shown; switch with the picker at the top.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }
}

// MARK: - Info

/// Info ▸ Meeting: the calendar meeting this recording is. Linked
/// meetings are saved in `<stem>.studio.json`; "Find in Calendar" runs the
/// configured calendar command (Settings ▸ Studio ▸ Calendar).
struct MeetingSection: View {
    @Environment(LibraryStore.self) private var library
    let workspace: RecordingWorkspace

    var body: some View {
        Section("Meeting") {
            if let m = workspace.metadata.meeting {
                linked(m)
            } else {
                lookup
            }
        }
    }

    private func linked(_ m: LinkedMeeting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(m.subject).font(.headline).textSelection(.enabled)
            Text(timeRange(m.start, m.end)).font(.callout).foregroundStyle(.secondary)
            if let o = m.organizer { Text("Organizer: \(o)").font(.caption) }
            if !m.attendees.isEmpty {
                Text("\(m.attendees.count) attendees: " + m.attendees.prefix(8).joined(separator: ", ") + (m.attendees.count > 8 ? ", …" : ""))
                    .font(.caption).foregroundStyle(.secondary)
                    .truncationTooltip("\(m.attendees.count) attendees: " + m.attendees.joined(separator: ", "), lines: 3)
            }
            HStack {
                if let link = m.webLink, let url = URL(string: link) {
                    Button("Open in Calendar") { NSWorkspace.shared.open(url) }
                }
                Button("Rename After Meeting…") { renameAfter(m.subject) }
                    .help("Name the recording after the meeting's subject, in front of its date and time.")
                Button("Unlink") { workspace.unlinkMeeting() }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var lookup: some View {
        HStack {
            Button(workspace.meetingResult == nil ? "Find in Calendar" : "Search Again") { workspace.findMeeting() }
                .disabled(workspace.findingMeeting)
            if workspace.findingMeeting { ProgressView().controlSize(.small) }
        }
        if let error = workspace.meetingError {
            Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
        }
        if let r = workspace.meetingResult {
            if r.matches.isEmpty {
                Text("No meeting in your calendar overlaps this recording.").font(.caption).foregroundStyle(.secondary)
            } else {
                if r.spansSeveralMeetings {
                    Text("This recording spans \(r.covered.count) meetings: " + r.covered.map(\.event.subject).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(Array(r.matches.prefix(5).enumerated()), id: \.offset) { i, m in
                    candidate(m, best: i == 0, confidence: i == 0 ? r.confidence : nil)
                }
            }
        }
    }

    private func candidate(_ m: MeetingMatch, best: Bool, confidence: MeetingMatch.Confidence?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.event.subject).fontWeight(best ? .semibold : .regular).truncationTooltip(m.event.subject, lines: 2)
                Text(timeRange(m.event.start, m.event.end)).font(.caption).foregroundStyle(.secondary)
                Text(detail(m, confidence: confidence)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Button("Link") { workspace.linkMeeting(m.event) }
                Button("Link & Rename…") {
                    workspace.linkMeeting(m.event)
                    renameAfter(m.event.subject)
                }
                .help("Link the meeting and name the recording after its subject, in front of its date and time.")
            }
        }
    }

    private func renameAfter(_ subject: String) {
        library.requestRename(workspace.recording, after: subject, start: workspace.audioStart)
    }

    private func detail(_ m: MeetingMatch, confidence: MeetingMatch.Confidence?) -> String {
        var parts: [String] = []
        if let confidence { parts.append(confidence.rawValue) }
        parts.append("\(Int((m.meetingCoverage * 100).rounded())) % of the meeting recorded")
        parts.append("\(Int((m.recordingCoverage * 100).rounded())) % of the recording")
        if m.nameMatches { parts.append("name matches") }
        return parts.joined(separator: " · ")
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
            + "–" + end.formatted(.dateTime.hour().minute())
    }
}

struct InfoPanel: View {
    let workspace: RecordingWorkspace

    var body: some View {
        let rec = workspace.recording
        Form {
            MeetingSection(workspace: workspace)
            Section("Timing") {
                LabeledContent("Audio started") {
                    Text(workspace.audioStart, format: .dateTime.day().month().year().hour().minute().second())
                }
                LabeledContent("Line offset") {
                    HStack {
                        Text(String(format: "%+.2f s", workspace.metadata.syncOffsetSec)).monospacedDigit()
                        Stepper("", value: Binding(
                            get: { workspace.metadata.syncOffsetSec },
                            set: { workspace.setSyncOffset($0) }
                        ), in: -30...30, step: 0.25)
                        .labelsHidden()
                        Button("Reset") { workspace.setSyncOffset(0) }
                            .disabled(workspace.metadata.syncOffsetSec == 0)
                    }
                }
                Text("Live transcripts are placed by the clock time each line was written. If lines start a little early or late, shift them here. Transcripts made by the studio have exact timing and are not shifted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Audio") {
                ForEach(rec.tracks, id: \.url) { t in fileRow(t.url, detail: t.role.rawValue) }
            }
            Section("Transcripts") {
                ForEach(rec.transcripts) { t in fileRow(t.url, detail: workspace.isExact(t) ? "exact timing" : "live") }
            }
            if !rec.attachments.isEmpty {
                Section("Notes") {
                    ForEach(rec.attachments, id: \.self) { fileRow($0, detail: nil) }
                }
            }
            Section {
                Button("Show Folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([rec.tracks.first?.url ?? rec.folder]) }
            }
        }
        .formStyle(.grouped)
    }

    private func fileRow(_ url: URL, detail: String?) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(url.lastPathComponent).truncationMode(.middle).truncationTooltip(url.lastPathComponent)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.borderless).help("Open")
        }
    }
}
