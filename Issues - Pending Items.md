# Issues — Pending Items

> Pending items are listed most-critical-first; completed items follow.

## Pending items (most critical first)

### Video digests from untype in the library — open items (2026-11-27)
- **Not looked at in the app yet**: the library with the `Videos` link (on this Mac `~/Recordings/Videos` → iCloud Drive/untype/Videos) and a digest's HTML opened from the attachments.
- **Meetings / Videos switch (FR-STU-31) not looked at in the app yet**: the sidebar's switch, its counts, and search limited to the list shown.
- **Digests made on the iPhone have no audio** until the Mac resumes them, so they are not recordings and do not show in the library.
- **iCloud files not downloaded** (Optimize Mac Storage) show as `.icloud` placeholders and are skipped until downloaded.

### Rename After Minutes / After Linked Meeting on the recording — open items (2026-11-26)
- **The Rename sheet's "Name it after" buttons were not clicked**, nor the two entries of the right-click menu; the File menu entries were listed and their availability checked on one real recording (both available).
- **The menus read the recording's `studio.json` and minutes file** each time they are built, to know whether an entry applies (small files; not measured on a slow disk).

### Cut This Recording (cuts in place) — open items (2026-11-26)
- **Not clicked in the app.** `applyInPlace` is unit-tested on WAV fixtures (lengths, re-timed lines, kept meeting, refusals); the button, its confirmation and the reopening of the recording were not run, and no real AAC recording was cut in place.
- **Minutes, saved answers and text exports keep the old timecodes** after a cut in place (`.minutes.md`, `.studio-qa.md`, `.transcript.txt`, `segments.jsonl`); nothing marks them as out of date.
- **AAC is encoded again** for the whole track, as with every cut.
- **Undo is by hand:** move the new files away, then Put Back the five or so files from the Trash.
- **The 10 s "still recording" check** blocks another in-place change right after.

### Minutes of one side, deleting minutes, splitting the channels — open items (2026-11-26)
- **Not run in the app.** The Both / Mic / System picker, *Delete…* and *Split into Two Recordings* were built, not clicked, and no one-sided minutes were requested from a provider. Unit-tested: the line filter, file names, jobs per scope, the request text, the scanner and the channel copies.
- **The microphone's lines can hold the other side's words** when the system audio leaked into the microphone (speakers, no headphones): the microphone transcript then repeats the call, and its minutes look like the call's. Remove the echo into a copy and re-transcribe it first for a clean microphone side.
- **One-sided minutes need source tags.** The picker appears only when the shown transcripts have lines of both channels; a transcript without them (a mixed recording) has the whole only.
- **Split keeps the timeline.** Each copy has the full length of the recording, silence included; nothing is trimmed, and the copies are not linked to a meeting.
- **Minutes of the whole are not copied** by the split, and the copies' `studio.json` keeps the speaker names of both sides.

### Minutes jobs and the Settings button — open items (2026-11-26)
- **Not run against a provider from the app.** The jobs are unit-tested with fed streams (`MinutesJobsTests`: two in turns, stop, failure, second start refused); pressing *Write Minutes* on two real recordings and switching between them was not done (it replaces their minutes and sends the transcripts to the provider). The Settings button was seen in the toolbar, not clicked; the quit question was not seen.
- **"Keep Running" after closing the window** (the quit question appears because closing the last window quits): whether the window then stays or the app is left without one until the Dock icon is clicked was not checked.
- **Quitting drops running jobs** (after asking). Jobs are not resumed at the next launch.
- **Ask and re-transcription still stop** when another recording is opened; only minutes were moved to app-level jobs.
- **Removing a track or writing silence is not blocked** while that recording's minutes are written (the minutes file is not touched by them; the minutes describe the transcript as it was at the start).
- **Provider rate limits:** several jobs at once are several requests at once; a provider that refuses them shows as a failed job on that recording.

### One-folder mode (`untype-studio <folder>`) — open items (2026-11-22)
- **Checked only at launch.** Started on a real recording folder: the window opened with that one recording listed and open. Copies joining the list, following a renamed folder and leaving the mode with Choose Library Folder were not exercised.
- **No headless form.** It opens the app; minutes, meeting linking and clean-up are still done with its buttons (`clean-echo` is the only one with a terminal-only command).
- **Transcript search covers only the listed recordings** in this mode, and the Join panel only them.
- **A folder whose name is a command word** (`join`, `open`, …) must be given with a path (`./join`).

### Editing keys in text fields (2026-11-22)
- **Fixed in code, not confirmed by typing.** Option-←/→ in any text field ran the Playback menu's Back / Forward 5 Seconds instead of moving by word, and Command-Delete ran Move to Trash; the user also reported Command-←/→ not working in the Rename sheet (cause not found: no shortcut of the app uses them). `PlaybackKeys` (UntypeStudioApp.swift) now hands the arrows and Delete with Command or Option straight to the text being edited. Needs the user's confirmation that all four combinations work, in the Rename sheet and the other fields.

### Rename after the meeting or the minutes — open items (2026-11-22)
- **Not clicked through live.** *Rename After Meeting…*, *Link & Rename…* and *Rename After Title…* were built and the app launched, but not pressed (they rename recordings in the user's library). The naming is unit-tested (`RecordingNamingTests`); the rename behind the sheet is the existing, tested one.
- **The rename sheet belongs to the sidebar's view.** The new buttons open it from the inspector; whether it also appears with the sidebar hidden was not checked.
- **A split session takes one name.** Renaming after the meeting renames the session folder, so every part follows, as with a plain rename.
- **No command-line form**, and no rename of several recordings at once (for example after `match-meetings`).

### Channels and ranges / changing a recording itself — open items (2026-11-22)
- **Not clicked through live.** The Cut tab's new buttons (New recording from Both / Mic / System, New recording with only Mic / System, Remove from this recording, Write to This Recording) were built and the app launched, but not pressed: they write into, or change, the user's library. The file operations are unit-tested (`ChannelCopyTests`), including real moves to the Trash.
- **Removing a track leaves that channel's lines in the main transcript** (`<stem>.transcript.jsonl`, `segments.jsonl`); only the channel's own transcript goes to the Trash.
- **Undo of Write to This Recording is by hand:** move the rewritten track away, then Put Back the original from the Trash.
- **Writing silence into an AAC track encodes it again** (one more lossy generation for the whole track, not only the silenced range).
- **The 10 s "still recording" check also blocks a second in-place change** made within 10 s of writing silence (the rewritten file is new).
- **No command-line form** for these actions (only the Cut tab).

### Echo removal into a copy — open items (2026-11-21)
- **The echo delay is measured in one place only.** `EchoDelayEstimator` looks at two minutes a quarter of the way into the recording. If the microphone is silent or muted there, no delay is found and `EchoCleaner` silently uses 0 ms, so the cleaning does little. Seen on `a test recording of 2026-11-19` (which has almost no echo, so nothing was lost). Fix: measure in several places and report when nothing is found.
- **The cleaned copy keeps the old microphone transcript**, with the other side's words in it, until the copy is re-transcribed. Whether a transcript of the cleaned microphone is free of them has not been checked.
- **Echo is reduced, not removed:** 21–25 dB with high suppression on four real recordings (16 kHz AAC). Trying other canceller settings on one recording (no divergence reset, smaller step, shorter filter) changed the typical frame by under 1 dB, so more needs a different method, not tuning.
- **Not clicked through live:** *Remove Echo into a Copy* in the sidebar menu and File menu was built, not clicked; `untype-studio clean-echo` was run on a copy of a real recording and `cleanCopy` is unit-tested.
- **Unset suppression now means high in the studio; ntakker's own copy of the Settings pane still shows Off** when `NTAKKER_STUDIO_ECHO_SUPPRESSION` is unset. Carry the one-line change (`SharedCorePanes.swift`) to ntakker, or it is lost when the vendored folders are copied again.

### Split from ntakker — open items (2026-11-20)
- **Released 2026-11-22 as v0.8.0** (Developer ID signed, notarized): GitHub release on `biks2013-tools/untype-studio`, cask `untype-studio` in the tap `biks2013-tools/homebrew-untype`. Signed with the Developer ID identity `2C7D…DF30` (the one `untype.app` uses) and the notarytool profile `untype-notary`. Installing with `brew install --cask` was not tried.
- **Two copies of the studio exist.** `ntakker-studio` is still in the ntakker repository (and in /Applications if installed). Both apps open the same library and write the same per-recording files. Decide when to retire `ntakker-studio` there (source, cask, docs).
- **The engine is a vendored copy.** `Sources/NtakkerCore` and `Sources/NtakkerSettingsUI` were copied from ntakker on 2026-11-20 and will drift: a provider or settings change in ntakker reaches the studio only when the folders are copied again. `NtakkerCore`'s tests were not copied. The recorder half of `NtakkerCore` (capture, encoders, session) is compiled but unused here and could be removed.
- **Settings still live in ntakker's file** (`~/.tool-agents/ntakker/.env`, `NTAKKER_*` names). Kept on purpose so the studio follows ntakker's recordings folder and keys; a studio-only file would need the variables renamed and a migration.
- **The Settings window still shows ntakker's recording panes** (format, layout, microphone…), because the shared panes were copied whole. They edit ntakker's settings; nothing in the studio uses them.
- **The icon is the ntakker-studio icon**, unchanged.

### Studio rename / Move to Trash — open items (2026-10-27)
- **Not clicked through live.** The debug build showed the new File-menu items on the real library (with throwaway `zz-studio-test-…` recordings, removed afterwards), but the automation could not select a sidebar row, so the context menu, rename sheet and trash confirmation were built, not clicked. The file rules are unit-tested (`RecordingFileOpsTests`), including a real move to the Trash.
- **"Still recording" is a 10 s modification-time check**, not a signal from ntakker. A recording paused for longer than that is not protected: renaming or trashing it before ntakker resumes may break the resume. Better fix: ntakker publishes the files it is writing (e.g. a state file) and the studio refuses those.
- **No Undo inside the studio** for either action: rename back by hand, Put Back from the Trash.

### Studio channel lanes / silencing — open items (2026-10-21)
- **Not heard.** Lanes, the listen mute (icon, dimmed lane), lane-only selection, Silence on Mic and the Silenced list were checked live in a debug build on the real library (Export not pressed there); what is heard could not be checked here. Playback and export use the same `SilenceGain`, and the export is tested on files.
- **Stereo-split recordings** (one stereo file, system left / mic right) are shown as one mix; the lanes and silencing are only for split recordings.
- **Silences are not saved** with the recording (like cuts): closing it before Export Copy drops them.

### Studio join — open items (2026-10-19)
- **Speaker ids are per part** in live transcripts; the join keeps raw ids, so "Speaker 1" of two parts may be two people. Renaming in the joined recording fixes it by hand.
- **Not clicked through live in the app:** the plan view (both the refusal and a 5-part plan) was checked on the real library; the Join button was not pressed there (it writes into the library). The write path was run through `untype-studio join` on a copy and unit-tested.

### Studio meeting matching — open items (2026-10-18)
- **Long recordings across back-to-back meetings** are flagged ("spans several meetings") but stay one recording; splitting one into per-meeting copies at the meeting boundaries (with the Cut export) is not offered yet.
- **Linking from the app was not clicked through live** (it writes `<stem>.studio.json` into the user's library); the save/load round trip is unit-tested and *Find in Calendar* was checked live.
- **Calendar command needs a full path** when the studio is started from the Dock (short PATH). Documented; the studio does not search for the program.
- **Recording start comes from the audio file's creation date** when `studio.json` has no `audioStart`; a copied file gets a new date and would match the wrong day.

### plan-025 shared settings — open items (2026-10-17)
- **Concurrent writes can lose a change.** `EnvFileStore.upsert` reads, edits and rewrites the whole file; two writers at the same instant (two apps, or an app and an editor) can drop one update. Not observed: the "lost line" seen in testing on 2026-10-17 was the missing-final-newline bug (resolved 2026-10-18, below). Fix if it matters: a file lock (`flock`) around read-modify-write.
- **Behaviour change for the CLI:** it now follows the apps' choices (format, layout, mic, transcription provider) because it reads the shared file. Flags still override.
- **Provider panes read the file when shown**, not live; a change made in the other app shows after switching panes. The Recording / Transcription / Studio panes and the popover update live.
- Manual check pending: launch the new ntakker once (it copies its preferences into the file), then confirm the popover, the studio's Settings and `ntakker-cli start` agree.

### plan-024 — untype-studio v1: open items (2026-10-17)
- **Live checks still to do by the user:** a first Ask question and a set of minutes against the configured provider (sends the whole transcript); exporting a cut of a real split recording from the app; a re-transcription with Parakeet. Unit tests cover all three paths, and an M4A cut was checked on a real file.
- **Audio start is estimated** from the audio file's creation date (≈±1 s), and batch-provider lines also carry the provider's round-trip delay. The Info tab's line offset corrects it per recording. Proper fix: ntakker writes the exact first-sample time into a session sidecar at record time, and the studio reads it as `audioStart`.
- **Streaming providers cannot re-transcribe** (Soniox, Apple, Apple Cloud, Azure Realtime). Soniox has an async file API that would also bring diarization to re-transcriptions; not implemented.
- **Mic and system transcripts both show by default**, so speech the system side also captured appears twice. Use the transcript picker to show one; a dedupe view could merge them.
- SRT / VTT / TXT sidecars are not read; JSONL is the source.

## Completed items

### Studio split into its own project, untype studio (2026-11-20)
- **Request:** make ntakker studio a separate application in its own project folder, with its source and documentation, renamed to untype studio.
- **Done:** see `docs/design/project-design.md`, "Split from ntakker (2026-11-20)".
