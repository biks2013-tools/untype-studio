# untype studio

A macOS Dock app for studying finished recordings made with [ntakker](https://github.com/biks2013-tools/ntakker): the transcript follows playback, a click on a line jumps the audio there, and the whole library is searchable.

- **Library:** every recording under your recordings folder, with full-text search across all transcripts; rename recordings or move them to the Trash from the sidebar.
- **Listen and read:** playback at 0.75–2×, mic and system channels as separate lanes, optional echo removal.
- **Edit copies, never originals:** cut ranges out, silence noise on one channel, join the parts of a paused session.
- **Understand:** ask questions over the whole transcript, write meeting minutes, rename speakers, fix transcript text, re-transcribe with a batch provider, match recordings to calendar meetings.

Until 2026-11-20 this app was `ntakker-studio`, part of the ntakker repository. It still reads ntakker's recordings and ntakker's settings file (`~/.tool-agents/ntakker/.env`).

## Build

Requires macOS 26 and the Swift 6.2 toolchain.

```sh
swift build                                  # debug build
swift test                                   # 58 tests
bash scripts/package-untype-studio-app.sh    # dist/untype-studio.app (ad-hoc signed)
bash scripts/redeploy-untype-studio.sh       # rebuild, install to /Applications, launch
```

## Layout

| Path | What |
|---|---|
| `Sources/untype-studio` | The SwiftUI app |
| `Sources/UntypeStudioKit` | Its testable logic (library scan, timing, cuts, join, Ask, search, re-transcribe) |
| `Sources/NtakkerCore`, `Sources/NtakkerSettingsUI` | Vendored copies of ntakker's engine and shared Settings panes |
| `Tests/UntypeStudioTests` | Swift Testing suites |
| `docs/tools/untype-studio.md` | Full documentation |
| `docs/design/` | Design and functional requirements |

Releasing (signed, notarized): see "Releasing" in [`docs/tools/untype-studio.md`](docs/tools/untype-studio.md).
