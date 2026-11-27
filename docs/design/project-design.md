# Project Design — untype studio

The always-current design of **untype studio**, the macOS Dock app for studying finished recordings. Until 2026-11-20 the app was `ntakker-studio`, one of three products in the ntakker repository; the sections below were carried over from that repository's `project-design.md` with the names updated.

## Split from ntakker (2026-11-20)

- **What moved:** the app (`Sources/untype-studio`, was `Sources/ntakker-studio`), its logic library (`Sources/UntypeStudioKit`, was `NtakkerStudioKit`), its tests, icon, packaging and release scripts, and its documentation.
- **Vendored engine:** `Sources/NtakkerCore` and `Sources/NtakkerSettingsUI` are copies of ntakker's engine and shared Settings panes, taken from the ntakker working tree on 2026-11-20 (after ntakker commit `2ab0909` plus studio 0.7.1). They keep ntakker's module names so a newer copy can replace them; the studio uses the settings file, transcript formats, transcription and Ask providers and the echo canceller from them. The recorder code in `NtakkerCore` is compiled but not used by the studio. `NtakkerCore`'s own tests stay in the ntakker repository.
- **Identity:** executable and bundle `untype-studio`, bundle id `com.giorgosmarinos.untype-studio`, display name "untype studio". A new bundle id means a new preferences domain; `studio.*` preferences were copied once from `com.giorgosmarinos.ntakker-studio` on the developer's Mac.
- **Settings:** unchanged. The studio still reads and edits ntakker's shared settings file `~/.tool-agents/ntakker/.env` (the `NTAKKER_*` variables, including `NTAKKER_STUDIO_*`), because it works on ntakker's recordings with ntakker's providers. Per-recording files (`<stem>.studio.json`, minutes, Q&A) are unchanged, so both apps read the same library.
- **Version:** continues from ntakker-studio 0.7.1 as 0.8.0.
- **ntakker repository:** `ntakker-studio` was left in place there; new studio work happens here.

## untype-studio — Recordings Explorer (plan-024)

Added 2026-10-17. Request: `docs/refined_requests/refined-request-001-untype-studio.md`. Plan: `docs/plans/plan-024-untype-studio.md`. User guide: `docs/tools/untype-studio.md`.

### STU-1 — Targets

| Target | Kind | Role |
|---|---|---|
| `UntypeStudioKit` | library (`Sources/UntypeStudioKit`) | All testable logic. Depends on `NtakkerCore` only. |
| `untype-studio` | executable (`Sources/untype-studio`) | SwiftUI Dock app; embeds `Resources/UntypeStudio-Info.plist` (`com.giorgosmarinos.untype-studio`). |
| `UntypeStudioTests` | Swift Testing | Kit suites; real-file timing/cut suites run only with `STUDIO_WAVEFORM_FILE` / `STUDIO_CUT_FILE` set. |

Packaging mirrors ntakker: `scripts/package-untype-studio-app.sh`, `scripts/redeploy-untype-studio.sh`.

### STU-2 — Kit modules

- `Library/` — `Recording`, `AudioTrack`, `TranscriptFile`; `RecordingLibraryScanner` groups one folder's files by stem (longest stem claims `.partNN` transcripts first; `.mic`/`.system` → split tracks; a folder with one base stem is a session folder and lends its name).
- `Transcript/` — `StudioMetadata` (`<stem>.studio.json`; a corrupt file throws rather than being replaced), `SegmentTiming`, `TranscriptDocument` (load via `JSONLTranscriptReader`; save by writing every segment with `JSONLTranscriptWriter` to a temp file, `.orig` backup once, atomic replace).
- `Cutting/` — `CutPlan` (clamp, merge, kept ranges, time mapping), `TranscriptRetimer` (drop a line when < 50 % survives; new timestamp = audio start + mapped offset), `AudioCutter` (AVAudioFile copy of the kept frame ranges in the source's own settings; AAC stays AAC), `RecordingCutExporter` (destination folder rules; removes the half-written folder on failure).
- `Ask/` — `StudioAsk` (Q&A and minutes prompts; transcript as `[hh:mm:ss] Speaker: text`, same-speaker lines < 3 s apart merged; 6 exchanges of history), `StudioNotes` (append Q&A, replace minutes), `TimecodeLinks` (`[mm:ss]` → `untype-studio://seek?t=N`).
- `Search/` — `TranscriptSearchIndex` actor: folded (case, diacritics, width) lines; re-reads a transcript only when its modification date changes.
- `Retranscribe/` — `Retranscriber`: provider from `ConfigResolver(toolName: "ntakker")` with `NTAKKER_TRANSCRIBE` (and languages) overridden, built by `TranscriptionProviderFactory` through the shared `TranscriptionProviderFactoryInput(options:logger:)` (moved out of `RecordingSession`); decode to 16 kHz mono with `AVAudioConverter` (downmix); cut at the first quiet 50 ms frame after the target, else the quietest before the maximum (cloud: 20/30 s; on-device: the provider's `chunkPolicy`); `TranscriptSanitizer.clean` per chunk; one segment per chunk at `audioStart + chunk start`.
- `Audio/` — `WaveformPeaks`: per-1024-frame `vDSP_maxmgv` peaks folded into N buckets (≈1.3 s per 1.6 h AAC track).

### STU-3 — Timing model

ntakker stamps segments with wall-clock time. The studio places a line at `timestamp − audioStart`, where `audioStart` is `studio.json`'s value or the first audio file's creation date. Streaming providers (`soniox`, `apple`, `apple-cloud`, `azure-openai-realtime`, `gemini-live`) stamp the utterance start; the batch pipeline stamps the result's arrival, so `durationSec` is subtracted. A per-recording `syncOffsetSec` nudges live transcripts. Studio-written transcripts (cuts, re-transcriptions) are listed in `exactTimingTranscripts` and placed without correction.

### STU-4 — App

`LibraryStore` (folder, scan, index, search, selection) → `RecordingWorkspace` per open recording (documents, entries, filters, cuts, Ask/minutes/re-transcribe tasks) → `PlayerController` (AVPlayer over an `AVMutableComposition` of all tracks, 20 Hz time, skip ranges for cut preview). Views: `LibrarySidebar`, `RecordingDetailView` (header, `PlayerBar`, `WaveformStrip`), `TranscriptPane`, `InspectorPane` (Ask, Minutes, Speakers, Cut, Re-transcribe, Info), `MarkdownText`. The tools column is fixed-width in an HStack: an `HSplitView` sized panes by unwrapped text and pushed the content past the window edges.

### STU-4.1 — Playback echo filter (added 2026-10-17)

- `PlayerController` plays through `AVAudioEngine`: a `BlockReader` on its own queue reads 8192-frame blocks from every track, mixes them, and keeps four scheduled on an `AVAudioPlayerNode` (→ `AVAudioUnitTimePitch` for speed). Seeking bumps a generation counter, drops the schedule and restarts the reader; completions of an older generation are ignored. Time = start frame + the node's sample time.
- For a split recording the reader runs `SoftwareAECProcessor.processAligned(mic:reference:)` on every block, with the system track read from a second file handle `referenceDelay` frames behind playback. Output = cleaned mic (when the switch is on) or the original mic, plus the system track.
- `SoftwareAECProcessor.playbackConfiguration` (μ 0.3, step cap 1, leak 1e-6, 4096 taps, mono): fast convergence is safe because nothing is written; the double-talk gate and divergence reset still apply. `resetAlignedTimeline(clearingEchoPath:)` keeps the weights across a seek and clears them when the reference delay changes.
- `EchoDelayEstimator` (kit): cross-correlation of 1 ms RMS envelopes over two minutes a quarter into the recording, lags 0–500 ms. Real recordings: 114–142 ms, beyond the 85 ms window — without the delay the filter reached only 3–7 dB; with it 15–16 dB.
- Cost: about 18× real time per core in a debug build for one 48 kHz filter; it also runs while the switch is off, so switching on is instant.

### STU-4.2 — Adjustable echo filter (added 2026-10-17)

- `EchoProcessor` (kit) is the one echo pipeline for the player and `EchoCleaner`: NLMS canceller → optional `ResidualEchoSuppressor` → strength mix, configured by `EchoFilterSettings` (strength, suppression off/low/high, adaptation stable/fast; persisted app-wide under `studio.echo.*`). `update(_:)` applies new settings between blocks; a new adaptation speed makes a fresh canceller.
- `ResidualEchoSuppressor`: STFT 512 / hop 256, √Hann analysis and synthesis (perfect reconstruction, tested), per-bin gain `max(floor, 1 − k·S_echo/S_out)` with smoothed powers and gains; low k 0.6 / floor 0.3, high k 1.6 / floor 0.08. Latency 512 samples: the processor delays the dry mic by the same amount for the strength mix; `EchoCleaner` trims it so the cleaned track stays sample-aligned. In playback the mic is 10.7 ms behind the system track while the second stage is on (inaudible).
- The echo delay override is per recording (`StudioMetadata.echoDelayMs`); the player and the export use it instead of the measured delay.
- **2026-11-21:** `EchoFilterSettings.standard` (what unset settings mean) has suppression high instead of off; the vendored `StudioSettingsPane` shows the same default. `RecordingCutExporter.cleanCopy(of:echoSettings:)` reads a recording from disk (`JoinPart.load`) and exports it with no cuts and `removeEcho`; `LibraryStore.removeEchoIntoCopy` (sidebar context menu, File menu; progress in the sidebar footer) and `CleanEchoCommand` (`untype-studio clean-echo`) call it. `Recording.hasEchoReference` = separate microphone and system tracks.

### STU-4.4 — One channel or one range into a new recording; changing a recording itself (added 2026-11-22)

- `RecordingCutExporter.export` gained `onlyRole` (write that channel's track only; from every transcript keep the lines whose source is that channel's, and skip a transcript left empty or labelled as the other channel), `isExtract` (folder token `part` instead of `cut`) and `copyAudioStart` (the copy's audio start, used for the file dates, the re-timed lines and `studio.json`). `extract(recording:range:onlyRole:duration:…)` builds the plan — the two cuts around the range — and passes `audioStart + range.start` as the copy's start. Folder tokens, in order: `cut`/`part`, `mic`/`system`, `clean`, `silenced`.
- `RecordingFileOps.removeTrack(_:from:libraryRoot:)` trashes the track's file and `<stem>.<role>.transcript.jsonl` (+ `.orig`); refuses the only track. `writeSilence(_:into:libraryRoot:)` rewrites each track that has silenced ranges with `AudioCutter.cut` (no cuts) into `.silencing-<name>` in the same folder (hidden, so a scan does not see it), copies the creation date, then trashes the original and moves the rewrite into place.
- App: `RecordingWorkspace.newRecording(range:onlyRole:)` shares `runExport` with `exportCut`; `pinAudioStart()` stores the audio start before a track file changes (the scanner derives the start from the earliest track file's creation date). `LibraryStore.removeTrack` / `writeSilence` close the open recording (its player holds the files), run the operation, rescan and reopen it; `jobProgress` / `jobLabel` (was the echo copy's progress) show in the sidebar footer.

### STU-4.5 — Names from the meeting or the minutes (added 2026-11-22)

`RecordingNaming` (UntypeStudioKit/Library) builds the name: the sanitized title, `-`, then the part of the current name from `recording-YYYY-MM-DD-HH-MM` (or from the bare date in older names) to its end; with no date in the name, `recording-<start>` is made from the recording's start. The title is the linked meeting's subject (`studio.json` → `meeting.subject`) or the first `# heading` of `<stem>.minutes.md`; no model is called. `LibraryStore.requestRename(_:after:start:)` puts the proposal in `renameSuggestion` and opens the existing rename sheet, so the rename, its checks and the reselection are `RecordingFileOps.rename` unchanged. Nothing renames without the user's confirmation, also on *Link & Rename…*.

### STU-4.6 — One-folder mode (added 2026-11-22)

`StudioMain` treats a first argument that is a folder (or `open <folder>`) as the recording to open: it checks that the folder holds a recording, sets `LibraryStore.launchFolder`, registers `NSTreatUnknownArgumentsAsOpen = NO` (otherwise AppKit takes the path for a document and the app starts without its window) and starts the app. `LibraryStore` then has `focusFolders` instead of a library: `rescan()` scans those folders only, adding the folders next to the first whose name starts with its name (the studio's copies), and opens the launch folder's newest recording once. `root` is the folder's parent, so `RecordingFileOps` (rename of the folder, Trash) and the exporters work unchanged; a rename updates `focusFolders`. `followSharedFolder()` does nothing in this mode; choosing a library folder leaves it.

### STU-4.7 — Minutes jobs (added 2026-11-26)

`MinutesJobs` (UntypeStudioKit/Ask, main actor, observable) holds one `MinutesJob` per recording id: the text received so far, whether it runs, its error. `LibraryStore` owns the registry; `RecordingWorkspace.generateMinutes` builds the request (`StudioAsk.minutes`, one provider client per call, no shared state) and hands the token stream, the recording's name and its minutes URL to `start`, after which the job never reads the workspace. `workspace.minutes` / `minutesGenerating` / `minutesError` are views of the recording's job, or of the saved file. A job writes the file only on success and then leaves the registry (`onFinished` → the open workspace of that id reloads the file, the library rescans); a stopped job leaves without writing; a failed job stays with its error. A second start for an id that is running is refused. Because a job holds the path it will write, `LibraryStore.rename` and `moveToTrash` refuse a recording whose own job is running, or whose folder would be moved while a job runs in it, and `applicationShouldTerminate` asks before quitting while jobs run. Ask and re-transcription are still the workspace's own tasks and stop when another recording is opened.

`MinutesScope` (whole / microphone / system) gives each side its lines (`segment.source`), its file (`<stem>.minutes.md`, `.mic.minutes.md`, `.system.minutes.md`; the scanner lists all three as attachments, so they are renamed and trashed with the recording), its job id and the sentence the request adds about a one-sided transcript. A job carries its `recordingID`, so the sidebar and the rename / Trash checks find every job of a recording. `RecordingWorkspace.minutesScope` selects what the panel shows; `deleteMinutes()` sends the shown file to the Trash. `splitChannels()` runs `RecordingCutExporter.extract(range: nil, onlyRole:)` for the microphone and then the system track in one background task and copies each side's minutes file into its copy as `minutes.md`.

The Settings button is a `SettingsLink` in the window toolbar (`ContentView`).

### STU-4.3 — Joining recordings (added 2026-10-19)

- `RecordingJoiner` (kit, `Joining/`): `JoinPart.load` reads a recording's metadata (a corrupt `studio.json` throws), audio length (`RecordingTiming.duration`) and placed transcript entries; `plan(_:)` orders parts by audio start, requires the same set of track roles, and computes each part's offset and the pause before it; `join(_:)` writes the result and removes the folder on failure.
- `AudioJoiner.concatenate`: per role, writes in the first source's file settings; same processing format → direct copy (reads bounded by the file length: `AVAudioFile.read` throws eofErr past the end), else `AVAudioConverter`; pads each source with silence to its part's length.
- Transcripts: segments get `timestamp = joinedStart + partOffset + entry.start`, listed in `exactTimingTranscripts`.
- App: `LibraryStore.selection: Set<String>` (the sidebar list is multi-select; `selectedID` is the single selection); ≥ 2 selected → `JoinView`; `sessionParts(of:)` finds a part's siblings (same folder, same base stem).
- **STU-ADR-6** Joining writes a new recording and leaves the pauses out (no silence for the gap); the gap is shown before joining. (2026-10-19.)

### STU-5 — Decisions

- **STU-ADR-1** Cuts write a new copy; originals are read-only to the studio except for explicit text edits (backed up) and the studio's own sidecars. (User decision, 2026-10-17.)
- **STU-ADR-2** Ask/minutes use ntakker's Ask configuration; the studio loads `~/.tool-agents/ntakker/.env` at launch and has no configuration folder of its own. (User decision.)
- **STU-ADR-3** No silent library default: the studio adopts ntakker's folder setting or asks.
- **STU-ADR-5** The echo filter never changes files: playback filters on the fly, and a cleaned mic track is only ever written into an exported copy (`EchoCleaner`, via `RecordingCutExporter(removeEcho:)`, warm-up pass + full pass, cleaned before cutting so the echo stays aligned).
- **STU-ADR-6** *(User decision, 2026-11-22; narrows STU-ADR-1.)* Two actions change a recording's own audio: removing the mic or system track, and writing silenced ranges into the track files. Both ask first and send what they replace to the Trash (`RecordingFileOps.removeTrack`, `writeSilence`: every track is rewritten to a hidden temporary file before any original is trashed). A third was added on 2026-11-26: removing the cuts in place (`RecordingCutExporter.applyInPlace`: the normal export into a hidden `.cutting-<stem>` folder inside the recording's folder, the recording's own metadata merged in with exact timing, then each original to the Trash and the new file into its name, put back if a move fails). Everything else still writes copies.
- **STU-ADR-4** Re-transcription is batch-only in v1; streaming providers would need a faster-than-real-time feed and file-relative timestamps.

## Shared settings (plan-025)

Added 2026-10-17. Plan: `docs/plans/plan-025-shared-settings.md`. Configuration: `docs/design/configuration-guide.md` §0.

- **One file**, `~/.tool-agents/ntakker/.env`, for ntakker, ntakker-cli and untype studio (`SharedSettings` in NtakkerCore: file location, key names, `adopt` / `migrateLegacyCLIFile` / `valuesFromAppPreferences`). The CLI's `ConfigResolver(toolName:)` uses it as the user tier; its pid/log files stay in `~/.tool-agents/ntakker-cli/`.
- **`NtakkerSettingsUI`** (new library): `SharedSettingsStore` (main-actor observable; folder watcher for atomic replaces + file watcher for in-place edits, re-armed after each folder event; writes through `EnvFileStore.upsert`, mode 0600, `setenv`), `@SharedSetting` / `@SharedBoolSetting` (drop-in for `@AppStorage`), `@SharedTranscriptionEnabled` / `@SharedTranscriptionProvider` / `@SharedLanguageSlot` (present `NTAKKER_TRANSCRIBE` and the comma-separated language list in the popover's shape), the row helpers and provider/Ask panes moved from the ntakker app, new Recording / Transcription / Studio panes, and `SharedSettingsView` (shared panes + each app's own).
- **ntakker**: the popover's real settings use the wrappers; `RecordingStarter` reads the store; preferences copied into the file once at launch (`com.giorgosmarinos.ntakker.migratedToSharedSettings`).
- **untype studio**: library = `NTAKKER_RECORDINGS_DIR` (followed live); echo settings `NTAKKER_STUDIO_ECHO_*` (`EchoFilterSettings.from(_:)` / `fileValues`).
- **Decision (user, 2026-10-17)**: real settings only in the file; UI state stays per app.
- **Known limit**: `EnvFileStore.upsert` is read-modify-write; two writers at the same instant can lose one change (seen once in testing with a hand edit). Acceptable for settings changed by hand; see the issues register.

## Studio: the two channels apart (2026-10-21)

- `ChannelSilence` (UntypeStudioKit/Cutting): per-role
  (`AudioTrackRole`) sorted, merged ranges on the original timeline,
  normalised with `CutPlan`'s merge. `SilenceGain`: 0 inside a range,
  1 outside, a linear ramp over `fadeSeconds` (10 ms; shorter for a
  range under 20 ms) at both edges, applied in place to Float32
  channel data.
- One gain, two users: `BlockReader.produce()` applies it to each
  block of the mic / system samples it is about to mix (the echo
  filter still gets the unsilenced mic and reference), and
  `AudioCutter.cut(…, silence:)` applies it to each chunk read from the
  source before writing — so what is heard is what is written.
  `RecordingCutExporter.export(…, silence:)` passes each track its
  role's ranges; silences alone are a valid export (`-silenced`).
- Listening mute: `PlayerController.mutedRoles` → `BlockReader` leaves
  the role out of the mix (from the next block, ~0.17 s).
- Lanes: `WaveformPeaks.loadPerTrack` (one envelope per track on the
  longest track's timeline; `combined` = per-bucket max for the single
  strip). `RecordingWorkspace` keeps `channelWaveforms`, `silence`
  (mirrored to the player) and `selectionRole` (the lane a drag was
  made on). Not offered for mixed / stereo-split recordings (one file;
  the channels cannot be told apart reliably).
- Tests: `ChannelSilenceTests` (gain and merging; export silences one
  channel with a cut, the other untouched, the original unchanged;
  silences alone export).

## Studio: rename and Move to Trash from the library (2026-10-27)

- `RecordingFileOps` (UntypeStudioKit/Library) holds the file rules;
  `LibraryStore` (`rename`, `moveToTrash`, `requestRename`,
  `requestTrash`, `revealInFinder`) and `LibrarySidebar`
  (`contextMenu(forSelectionType:)`, `onDeleteCommand`, the
  `RenameRecordingSheet`, the trash confirmation) drive it; the File
  menu repeats the two commands.
- A recording's files: every `<stem>.…` file of its folder minus those
  of a longer stem of another recording in the same folder. This covers
  sidecars the scanner does not model (`.orig`, `.questions.jsonl`).
- Rename target: the folder when `!sharesFolder`, the folder is not the
  library root and lies inside it; otherwise the files (`<stem>` prefix
  replaced). Clash checks before any move; file renames are rolled back
  on a failure. A case-only change of a folder name is allowed.
- Trash: `FileManager.trashItem` — the folder when no other recording is
  in it (never the root), otherwise the recording's files.
- In-use guard: any track modified less than 10 s ago → refused
  (`stillRecording`), since ntakker keeps writing the files while
  recording.
- The open recording is closed (player torn down) before its files
  move; after a rename the store rescans and selects the new id
  (`folder/stem`). The search index follows from the rescan.
- Tests: `RecordingFileOpsTests` (files of a recording, folder and file
  renames, never the root, refusals leave files untouched, what the
  Trash takes, a real move to the Trash).
