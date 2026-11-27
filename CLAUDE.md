<structure-and-conventions>
## Structure & Conventions — Documentation Map

<!-- Maintained automatically. The master copy is block/structure-and-conventions.md in
     the structure-and-conventions Claude Code plugin (repository
     BikS2013-coding-agents/structure-and-conventions-repo), which checks this copy at
     every session start and brings it up to date — edit the master, never this block. The block is committed with the repository on
     purpose: it tells anyone (human or agent) working with this repo where the
     project's documentation lives and how to read and maintain it. -->

### Where the documentation lives

- `docs/plans/` — every plan, one file per plan, named `plan-NNN-<indicative-description>.md`.
- `docs/design/` — all other planning and design documents:
  - `project-design.md` — the complete, always-current project design; update it with every new design or design change.
  - `project-functions.md` — the registry of all functional requirements and feature descriptions.
  - `configuration-guide.md` — the project's configuration guide, when one exists (structure below).
- `docs/reference/` — all reference material collected for the project.
- `docs/refined_requests/` — every refined request specification (create the folder if missing), one file per request named `refined-request-NNN-<slug>.md`. `NNN` is a zero-padded three-digit sequential number: the next number is the highest `NNN` already present in the folder plus one, starting at `001` — and when the category has an archive history branch, the archive's numbering counts too (see "Archiving historical documents" below). `<slug>` is the request slug reused by all downstream artifacts of the same request.
- `docs/prompts/` — every prompt created while working on the project (create the folder if missing), one file per prompt named `NNN-<indicative-description>.md`. `NNN` is a zero-padded three-digit sequential number: the next number is the highest `NNN` already present in the folder plus one, starting at `001` — and when the category has an archive history branch, the archive's numbering counts too (see "Archiving historical documents" below). The description states the prompt's use and purpose.
- `docs/tools/<tool-name>.md` — one dedicated documentation file per project tool.
- `test_scripts/` — every test script goes here; create the folder if it doesn't exist.
- `Issues - Pending Items.md` (project root) — the register of every issue, pending item, inconsistency, or discrepancy detected while working on the project. Pending items come first (most critical and important on top), completed items after. Whenever a defect or issue is fixed, check this file for an item to remove.

### How to use the documentation

- Every time an issue is solved, it must be resolved AND both the issue and the solution must be thoroughly documented.
- This file's "Tools" section (when present) lists each project tool with a one-or-two-sentence description of what it is capable of and the relative path to its dedicated documentation file under `docs/tools/` — retrieve the full documentation from there whenever it is needed. Full tool documentation must never be inlined into this file.
- Before writing any code script, consult the "Tools" section and the documentation under `docs/tools/` to check whether the planned code fits the scope of an existing tool. If so, implement it as an extension of that tool; otherwise build a generic, abstract version of the code as a new tool in the project's toolset, document it under `docs/tools/`, and reference it in the "Tools" section. The goal is to progressively grow the tools needed to test, evaluate, generate data, collect information, etc., and reuse them consistently.

### Archiving historical documents (history branches)

- A project MAY move accumulated historical, write-once process artifacts — deployment reports, codebase scans, refined requests, plans, session handoffs, and similar — off the default branch to keep its documentation lean. Living, authoritative documents (`project-design.md`, `project-functions.md`, the guides, tool docs, the issue register) are never archived.
- Each archived category gets a dedicated **orphan, docs-only branch** named `<category>-history`, whose tree contains ONLY that category's files at their original repository paths — so retrieval paths never change: `git show <category>-history:<original-path>`, no branch switching required. A pointer note/README stays in the category's folder on the default branch stating the branch name, the retrieval command, and (for numbered categories) the next number. Archive branches are append-only: never rebase, rewrite, delete, or merge them.
- **Numbering across the archive**: for every `NNN`-numbered folder, the next number is `max(highest NNN in the folder, highest NNN on the category's archive branch) + 1`. Before creating the FIRST document of a numbered category, check whether an archive branch exists for it (the folder's README/pointer note, or `git branch --list --all '*-history'`) and continue from the archive's highest number — never restart at `001`, never reuse an archived number. The archive branch is authoritative over the pointer note's recorded "next number" if they disagree.
- **Migration** runs in a temporary linked worktree so the main checkout — and any uncommitted changes in it — is never disturbed: `git worktree add <tmp> <category>-history` (first-time archiving: `git worktree add --detach <tmp> <default-branch>`, then inside it `git switch --orphan <category>-history` and `git checkout <default-branch> -- <category-paths>`); bring the new artifacts over at their original paths and commit ONLY the category's files; then on the default branch `git rm` the migrated files, update the pointer note, and commit referencing the archive commit. Verify with `git ls-tree -r <category>-history --name-only` and a `git show` spot-check.
- The project's concrete category → branch registry (which categories are archived, under which branch names) is project-specific and lives OUTSIDE this synced block — typically a "Document Archiving Strategy" section in the project's CLAUDE.md.

<configuration-guide>
- A configuration guide, when requested, is created at `docs/design/configuration-guide.md` and explains:
  - When multiple configuration options exist (config file, env variables, CLI params, etc.), what the options are and the priority of each one.
  - The purpose and use of each configuration variable.
  - How the user can obtain such a configuration variable.
  - The recommended approach for storing or managing the variable.
  - Which options exist for the variable and what each option means for the project.
  - Any default value the parameter has.
  - For configuration parameters that expire (e.g., PAT keys, tokens), propose adding a parameter that captures the expiration date, so the app or service can proactively warn users to renew.
</configuration-guide>

</structure-and-conventions>

## Project Memory / Approved Exceptions

This section records explicit, user-approved exceptions to the Structure & Conventions above. Both were approved for the ntakker project, where this app was built until 2026-11-20, and carry over with the code.

### Exception 001 — Implementation language: Swift instead of TypeScript

- **Rule overridden**: "Tools created in the context of a project are always written in TypeScript."
- **Approved**: 2026-04-26 (ntakker project); carried over 2026-11-20.
- **Scope**: this project (`untype-studio`).
- **Reason**: the app is a native macOS SwiftUI app built on ntakker's Swift engine (`AVFoundation`, `Accelerate`, on-device transcription models).

### Exception 002 — Deployment target macOS 26

- **Approved**: 2026-04-28 (ntakker project); carried over 2026-11-20.
- **Scope**: project-wide (`Package.swift` `platforms: [.macOS(.v26)]`), required by the vendored `NtakkerCore` (SpeechAnalyzer).

### Settings location — not an exception, a recorded decision (2026-11-20)

untype studio has no configuration folder of its own. It reads and edits ntakker's settings file `~/.tool-agents/ntakker/.env` (`NTAKKER_*` variables), because it works on ntakker's recordings with ntakker's providers. A missing required setting is reported as an error; nothing is defaulted.

## Tools

### untype-studio

macOS Dock app (`com.giorgosmarinos.untype-studio`; until 2026-11-20 `ntakker-studio` in the ntakker repository) for exploring finished ntakker recordings: library and full-text search across every transcript, renaming recordings (also after the linked meeting or the minutes' title, in front of `recording-<date>-<time>`) and moving them to the Trash from the sidebar, playback with the transcript followed line by line and click-to-jump, cutting ranges into a new copy with re-timed transcripts, writing a new recording from one range or one channel, removing a channel or writing silence into the recording itself, the mic and system channels as separate lanes, joining recordings (also `untype-studio join`), writing a copy with the system audio removed from the microphone track (also `untype-studio clean-echo`), Ask and meeting minutes over the whole transcript (minutes also of the mic or the system side alone, written in the background, several at once), splitting the mic and system tracks into two recordings, speaker renaming, transcript text edits, re-transcription with batch providers, and mapping recordings to calendar meetings (`untype-studio match-meetings`). `untype-studio <folder>` opens the app on the recording in that folder alone, without the library. `Sources/NtakkerCore` and `Sources/NtakkerSettingsUI` are vendored copies of ntakker's engine and Settings panes.

Documentation: [docs/tools/untype-studio.md](docs/tools/untype-studio.md)
