# Issues — Pending Items

> Pending items are listed most-critical-first; completed items follow.

## Pending items (most critical first)

### Split from ntakker — open items (2026-11-20)
- **Not released and no repository yet.** The project builds, its 58 tests pass and an ad-hoc signed `dist/untype-studio.app` runs, but there is no git repository, GitHub repository, signed release or Homebrew cask. `scripts/release.sh` assumes the GitHub repository `biks2013-tools/untype-studio` and the tap `biks2013-tools/untype`; neither was created or confirmed.
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
