# Project Functions — untype studio

The registry of functional requirements for **untype studio** (until 2026-11-20: `ntakker-studio`, in the ntakker repository). Requirement ids are kept from that repository.

## 1. Functional requirements

### Recordings explorer (2026-10-17 onwards)

#### FR-STU-1..10 — untype-studio, the recordings explorer
**Status:** IMPLEMENTED (2026-10-17, plan-024, user request; see `docs/refined_requests/refined-request-001-untype-studio.md`). A separate Dock app next to ntakker (`com.giorgosmarinos.untype-studio`).
- **FR-STU-1 Library.** Lists every recording under a library folder (the studio's own setting; first launch adopts ntakker's recording folder; otherwise the user must choose one), grouped by month. A recording is the audio and transcripts sharing a stem; each `.partNN` is its own entry.
- **FR-STU-2 Player.** Plays the recording; a split recording plays mic and system together. Speeds 0.75–2×. Space and ←/→ when no text field has focus.
- **FR-STU-3 Transcript study.** All transcripts of the recording on one timeline with time, speaker and source; the line being played is highlighted and followed; text and speaker filters; several transcripts can be shown at once.
- **FR-STU-4 Jump to moment.** Clicking a line (or its time) seeks the player to where the line was spoken. A per-recording offset corrects live-transcript timing.
- **FR-STU-5 Cut.** Ranges selected on the waveform or from lines are removed in a new copy (audio in the same format, transcripts re-timed, lines mostly inside a cut dropped). The originals are never modified. Cut preview skips the ranges during playback.
- **FR-STU-6 Ask.** Questions over the whole transcript through ntakker's Ask provider; answers cite `[mm:ss]` moments that are clickable; saved to `<stem>.studio-qa.md`.
- **FR-STU-7 Minutes.** Summary, topics, decisions, action items and open questions with timecodes, optionally in a chosen language; saved to `<stem>.minutes.md`.
- **FR-STU-8 Speakers.** Rename diarized speakers per recording (`<stem>.studio.json`); names are used everywhere in the studio.
- **FR-STU-9 Edit text.** Fix a line's text; saved back to the JSONL, with a one-time `.orig` backup.
- **FR-STU-11 Echo filter.** On a split recording, a player switch removes the system audio that leaked into the microphone, in real time during playback; the echo delay is measured per recording. Files are not changed; the Cut tab's export can write a copy with the echo removed from the mic track, with or without cuts. Adjustable: strength, extra suppression (off / low / high), adaptation (stable / fast) and a per-recording echo delay override. (Added 2026-10-17.)
- **FR-STU-12 Appearance.** *(2026-10-18, user request.)* System / Light / Dark for every studio window, in Settings ▸ General and View ▸ Appearance; applied at once and at launch before any window opens; a per-app preference, not a shared setting.
- **FR-STU-13 Meetings from the calendar.** *(2026-10-18, user request.)* A configurable command (`NTAKKER_CALENDAR_COMMAND`, `{from}`/`{to}` days, e.g. `m365mail calendar export`) prints calendar JSON; each recording is matched to the meeting that best fits its time span (fit + name hint, confidence strong/likely/weak, several back-to-back meetings reported as such). Info ▸ Meeting finds and links one (saved in `<stem>.studio.json`); `untype-studio match-meetings` prints the matches for the library as JSON. No default command: unset = not configured.
- **FR-STU-14 Join recordings.** *(2026-10-19, user request.)* Select two or more recordings (typically the `.partNN` parts of a paused session; a part offers *Join the N Parts…*) and write one new recording: tracks end to end in recording order (pauses left out, short tracks padded, other formats converted), every transcript re-timed with exact timing, start/speaker names/meeting carried over. Different track layouts are refused. Also `untype-studio join --name TEXT [--dry-run]`. Originals unchanged.
- **FR-STU-10 Re-transcribe and search.** Re-transcribe a recording with a batch provider (parakeet, whisperkit, gemini, azure, elevenlabs) into a new exact-timed transcript. Search every transcript in the library (case- and accent-insensitive, all words) and open a result at its moment.

#### FR-SET-1 — One settings file and one Settings window for all three tools
**Status:** IMPLEMENTED (2026-10-17, plan-025, user request). ntakker, ntakker-cli and untype studio share `~/.tool-agents/ntakker/.env`; both apps' Settings windows show every shared setting, grouped (Recording, Transcription, Asking, providers, Studio), and follow changes made elsewhere at once. Earlier per-tool values are migrated once. UI state stays per app.

---

### Added 2026-10-21 — Studio: the two channels apart

**FR-STU-15** — For a split recording the studio shows the mic and
system channels as separate waveform lanes; each can be muted while
listening (to hear the other alone, files untouched). A range selected
on a lane can be replaced with silence on that channel only (or a whole
channel silenced); silenced ranges are heard as silence at once and
written silent — with short fades — by Export Copy, together with any
cuts and echo removal, into a new copy (`-silenced`); the original is
never changed and transcript lines are kept. IMPLEMENTED.

**FR-STU-16** — From the library sidebar (context menu, File menu,
Delete / Cmd-Delete) the user can rename a recording and move one or
several recordings to the Trash, without Finder. Rename renames the
session folder when the recording has it to itself (every part of a
session follows), otherwise the recording's own `<stem>.…` files; Move
to Trash asks first and moves the session folder when nothing else
lives in it, otherwise only the recording's files (recoverable with
Put Back). The library folder is never renamed or trashed, and a
recording still being written is refused. IMPLEMENTED.

### Added 2026-11-04 — Resizable inspector

**FR-STU-17** — The inspector column is resized by dragging the divider between it and the transcript; a double-click restores the standard width. The width is remembered and the transcript keeps its minimum width. IMPLEMENTED.

### Added 2026-11-20 — Separate project

**FR-STU-18** — The studio is its own project and app, **untype studio** (`untype-studio`, `com.giorgosmarinos.untype-studio`), built and released from its own folder without the ntakker repository. It keeps reading ntakker's recordings and ntakker's settings file. IMPLEMENTED (built and tested locally; not yet released).
