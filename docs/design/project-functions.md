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

**FR-STU-19** *(2026-11-21, user request.)* — For a split recording,
*Remove Echo into a Copy* (sidebar context menu, File menu) and
`untype-studio clean-echo --name TEXT` write a copy whose microphone
track has the system audio removed, with nothing cut; the original is
never changed. The echo filter's extra suppression is high when it is
not set (was off). IMPLEMENTED (the command was run on a real recording;
the menu items were built, not clicked).

**FR-STU-20** *(2026-11-22, user request.)* — In the Cut tab: a new
recording from the selected range of both tracks, of the microphone
only or of the system track only; a new recording with the whole of one
track; and, changing the recording itself (user decision), removing its
microphone or system track (to the Trash, with that channel's
transcript) and writing the silenced ranges into its own track files
(the files as they were go to the Trash). IMPLEMENTED (file operations
unit-tested; the buttons were built, not clicked).

**FR-STU-21** *(2026-11-22, user request.)* — A recording can be renamed
after the calendar meeting it is linked to (Info ▸ Meeting: *Rename After
Meeting…*, and *Link & Rename…* when linking) or after the title of its
minutes (Minutes tab: *Rename After Title…*). In both cases the new name
goes in front of `recording-<date>-<time>`; what follows it (a copy's
suffix, a part number) is kept. The name is proposed in the Rename sheet
and applied when the user confirms (FR-STU-16 rename). IMPLEMENTED (the
naming is unit-tested, `RecordingNamingTests`; the buttons were built,
not clicked).

**FR-STU-22** *(2026-11-22, user request.)* — `untype-studio <folder>`
opens the app on the recording in that folder alone: the files are found
directly in the folder, the recording opens at once, and only it and its
copies are listed. Meant for cleaning up the audio, writing the minutes
or linking the meeting of one recording, wherever its folder is.
IMPLEMENTED (launched on a real recording folder: one recording listed
and opened; the error exits were run).

**FR-STU-23** *(2026-11-26, user request.)* — The window shows a
*Settings* button that opens the Settings window. IMPLEMENTED (seen in
the toolbar of the running app; not clicked).

**FR-STU-24** *(2026-11-26, user request.)* — Minutes go on being
written when the user opens another recording, and the minutes of
several recordings can be written at the same time, each finishing on
its own without mixing with the others. IMPLEMENTED (`MinutesJobs`,
unit-tested with interleaved streams, stop and failure; not run against
a provider from the app).

**FR-STU-25** *(2026-11-26, user request.)* — Minutes can be written
separately from the microphone's lines and from the system audio's
lines, next to the minutes of the whole recording, each in its own file.
IMPLEMENTED (line filtering, files, jobs and the request text are
unit-tested, `MinutesScopeTests`; not run against a provider).

**FR-STU-26** *(2026-11-26, user request.)* — Minutes can be deleted
(their file goes to the Trash, after a confirmation). IMPLEMENTED (built,
not clicked).

**FR-STU-27** *(2026-11-26, user request.)* — A recording whose
microphone and system tracks hold different conversations can be split
into two recordings, one per track, each with its lines and that side's
minutes. IMPLEMENTED (two FR-STU-20 channel copies in one action; the
copies are unit-tested, the button and the minutes copy were not run).

**FR-STU-28** *(2026-11-26, user request.)* — The cuts can be removed
from the recording itself, without a new folder (Cut tab: *Cut This
Recording…*); what is replaced goes to the Trash. IMPLEMENTED (file
operations unit-tested, `CutInPlaceTests`; the button was built, not
clicked).

**FR-STU-29** *(2026-11-26, user request.)* — Renaming a recording
offers two sources next to the free name: its minutes and its linked
calendar meeting (sidebar context menu, File menu, and inside the Rename
sheet). Extends FR-STU-21. IMPLEMENTED (on a real recording both menu
entries were found enabled; the sheet's two buttons were not clicked).

**FR-STU-30** *(2026-11-27, user request.)* — The library shows the
video digests untype makes (untype's plan-080), which live in iCloud
Drive/untype/Videos: a link to that folder inside the library
(`<library>/Videos`) is scanned like a folder, the recordings in it keep
their path through the link (so renaming and the Trash work as for the
others), and each one lists its digest (`<stem>.digest.html`,
`<stem>.digest.docx`) among its attachments. IMPLEMENTED (scanner
unit-tested with a linked folder; the link created on the user's Mac;
the app redeployed, the library not yet looked at by the user).

**FR-STU-31** *(2026-11-27, user request.)* — Videos are listed apart from
the meeting recordings: a recording whose folder holds `<stem>.video.json`
(written by untype's video digest) is a video, every other one a meeting.
A Meetings / Videos switch at the top of the sidebar (with the count of
each) chooses the list; the choice is remembered, the month groups, the
search (names and transcript lines) and the footer count follow it, and a
recording opened from elsewhere switches to its own list. IMPLEMENTED
(scanner unit-tested; not yet looked at by the user).

**FR-STU-32** *(2026-11-27, user request.)* — untype studio updates
itself from its GitHub releases (`biks2013-tools/untype-studio`,
`releases/latest`), as untype does: it looks 30 s after it starts and
every 6 hours (Settings ▸ General ▸ Updates: *Look for new versions
automatically*, on by default; **Check Now**; also untype studio ▸ Check
for Updates…), and offers a newer version once per version and start
with what changed (**Install and Restart**, **Later**, **Skip This
Version**, **Release Page**), never while minutes are written or a copy,
cut or join is made. Installing downloads the release's notarized
`untype-studio-<version>.zip`, checks its SHA-256 against the release's
`SHA256SUMS` and its signature against the running app's own designated
requirement, checks it is newer, puts it in the place of the app (the old
one comes back on failure; log `~/.tool-agents/untype-studio/update.log`)
and opens it. The request carries nothing about the user (User-Agent
`untype-studio-updater`). A locally built (ad-hoc signed) copy cannot
update itself and says so. IMPLEMENTED (unit-tested: versions, release
parsing, checksums, policy, swap script).

**FR-STU-33** *(2026-11-28, user request.)* — The words of recording
names that say nothing about which meeting a recording was (a company's
or team's name, prep, test) are a setting: Settings ▸ Studio ▸
Calendar ▸ *Words to ignore*, `NTAKKER_CALENDAR_IGNORED_WORDS` in
`~/.tool-agents/ntakker/.env`, comma-separated, any case. Meeting
matching (Info ▸ Meeting and `untype-studio match-meetings`) leaves them
out of the name hint, on top of the words the studio always ignores
(those untype puts in file names — recording, record, meeting, call,
part, copy, clean, studio, video — and with, and, the). Unset or empty
means no words of the user's own. IMPLEMENTED (unit-tested: reading the
setting, the name words, matching).

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
