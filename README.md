# usdx-tagger

An [UltraStar Deluxe](https://usdx.eu/) plugin for tagging songs from inside the game.

Press a key while a song is selected, previewing, or playing, and the plugin writes a
`.usdx-user-tags.yaml` file into that song's directory. The tags live next to the song,
so they can be found and processed with ordinary filesystem tools — no database, no
network, no separate service.

The primary use case is quickly flagging problematic songs during a karaoke session,
then reviewing them later.

> **Status:** early development. The requirements are specified in
> [docs/initial_idea.md](docs/initial_idea.md); the implementation is not complete yet.

## Why

During a party, nobody wants to alt-tab out of the game to note that a song has broken
lyrics or out-of-sync audio. Hit `T`, pick a tag, keep singing, sort it out tomorrow
with `grep`.

## Tag file

Each tagged song directory gets one extra file:

```text
Songs/
└── Artist - Song Title/
    ├── Artist - Song Title.txt
    ├── Artist - Song Title.mp3
    └── .usdx-user-tags.yaml
```

```yaml
# UltraStar Deluxe song tags set by the user
# Created by plugin https://github.com/ValeHaas/usdx-tagger
version: 0.1.0
tags:
  - bad-audio
  - review
```

The format is documented in full — including optional metadata, versioning, and the
minimal accepted file — in [docs/initial_idea.md](docs/initial_idea.md#4-yaml-file-format).

Notes on the format:

- `version` is the [semantic version](https://semver.org) of the plugin that last wrote
  the file. It may be omitted, and an unfamiliar value is read rather than rejected, so a
  file written by a newer plugin never costs you your tags.
- Tag names are arbitrary. They are trimmed, compared case-insensitively, and stored
  lowercase, so `Bad-Audio`, ` bad-audio `, and `bad-audio` are the same tag.
- Tag order is stable; new tags are appended.
- When the last tag is removed, the file is deleted by default (configurable), which
  keeps filesystem searches meaningful.

Suggested starting tags: `bad`, `review`, `bad-audio`, `bad-video`, `bad-lyrics`,
`bad-timing`, `duplicate`, `favorite`.

## Default key bindings

| Key      | Action                                  |
|----------|-----------------------------------------|
| `T`      | Open the tag menu                       |
| `Ctrl+T` | Show the current song's tags            |

In the menu: up/down to move, `Enter` to toggle the highlighted tag, `Esc` to close. A
tag the song already carries is marked `[x]`, and toggling it removes it again, so one
key covers both adding and removing. The menu stays open after a toggle so several tags
can be set in one visit.

Any key the plugin has no binding for is passed straight through to UltraStar Deluxe, so
its own controls keep working.

## Configuration

Configuration lives in the writable user directory that UltraStar Deluxe reports — never
in the song library. On Windows that is `%APPDATA%\ultrastardx\usdx-tagger.ini`, or the
executable's directory for a portable install.

```ini
enabled=true
quick_tag=bad
tag_menu_key=T
show_tags_key=Ctrl+T
show_notifications=true
show_existing_tags=true
delete_empty_tag_file=true
notification_ms=2500
```

`quick_tag` is the tag placed first in the menu, so the most common choice is one
keystroke away.

Key bindings accept modifiers: `T`, `Shift+T`, `Ctrl+T`, `Alt+F5`, and the named keys
`Space`, `Escape`, `Return`, `Tab`, the arrows, and `F1`-`F12`.

A missing file, a missing key, or a malformed value each fall back to the default and are
noted in UltraStar Deluxe's log rather than failing to load.

## Working with tags outside the game

The whole point of a plain YAML file per song directory is that you don't need this
plugin — or UltraStar Deluxe — to use the data.

Find every tagged song:

```bash
find Songs -name '.usdx-user-tags.yaml'
```

List the directories of everything tagged `bad`:

```bash
grep -rl --include='.usdx-user-tags.yaml' -e '- bad$' Songs | xargs -n1 dirname
```

Move songs marked `review` into a quarantine folder:

```bash
grep -rl --include='.usdx-user-tags.yaml' -e '- review$' Songs \
  | xargs -n1 dirname \
  | xargs -I{} mv {} Quarantine/
```

PowerShell equivalent:

```powershell
Get-ChildItem -Recurse -Force -Filter '.usdx-user-tags.yaml' |
  Where-Object { (Get-Content $_.FullName) -match '^\s*-\s*bad\s*$' } |
  ForEach-Object { $_.Directory.FullName }
```

## Design

UltraStar-specific and platform-specific code is isolated behind adapters, so the tag
logic can be tested — and reused by other tools — without the game running.

```text
src/tagger/
├── version.lua   -- the semantic version, single source of truth
├── tagset.lua    -- tag naming and set operations   (TagService + TagValidator)
├── tagfile.lua   -- reads and writes the tag file   (TagFileRepository)
├── keys.lua      -- key bindings and matching
├── config.lua    -- settings                         (PluginConfig)
├── notify.lua    -- on-screen messages
├── adapter.lua   -- the only module touching Usdx.*  (UltraStarAdapter)
└── init.lua      -- configuration, key handling, tag menu
```

Only `adapter.lua` knows UltraStar Deluxe exists. Everything else is plain Lua over plain
strings and files, which is what lets the test suite run the whole tag engine — and drive
the built plugin end to end — with the game absent.

`notify.lua` takes its clock and its drawing function as parameters rather than reaching
for them, for the same reason.

## Development

Requires a Lua interpreter; nothing else, and no luarocks.

```bash
lua spec/run.lua           # unit tests for the engine, no game needed
lua build/bundle.lua       # build dist/usdx-tagger.usdx
lua spec/bundle_check.lua  # drive the built plugin with UltraStar stubbed out
```

The plugin ships as a single `.usdx` file because UltraStar resolves only
`require('Usdx.*')` and its plugin directory is read-only in a release build, so
`build/bundle.lua` inlines the modules. It also runs the generated main chunk in a bare
environment as a build step — UltraStar executes a plugin's main chunk *before* opening
the standard library, and that check catches the resulting breakage at build time instead
of in the game.

`dist/` is not committed; build it when you need it.

## Guarantees

The plugin owns exactly one file per song directory and nothing else. It will never:

- delete, rename, or move song directories,
- touch the `.txt`, audio, video, cover, or MIDI files,
- modify UltraStar song metadata by default,
- execute shell commands,
- require a database, network access, or administrator privileges.

Writes to `.usdx-user-tags.yaml` are atomic (temp file in the same directory, then
replace), YAML is parsed in safe mode with no object deserialization, and unknown fields
are preserved where possible. Errors — no current song, read-only directory, invalid
YAML, permission denied — surface as a notification and a log entry, never as a crash.

Song title and artist may be stored in the file for diagnostics, but the authoritative
identity of a song is always its actual filesystem path, obtained from UltraStar Deluxe
rather than reconstructed from artist and title.

## Platform support

Windows, Linux, and macOS, as far as the UltraStar Deluxe plugin API allows. Spaces and
punctuation, nested song directories, multiple song libraries, and writable network
mounts are all supported.

Unicode paths work, with one caveat on Windows: Lua's `io` library reaches the filesystem
through the narrow C runtime, which reads paths in the active ANSI code page. A song
folder whose name needs characters that code page cannot represent is not openable from a
plugin at all. Names within the code page — `Björk`, `Motörhead`, `Sigur Rós` — are fine.
The failure is reported, never silently ignored.

## Installation

The plugin needs an UltraStar Deluxe build that exposes the selected song and a key hook
to Lua. A stock build has neither, so a patched game is required for now; what is missing
and why is written up in [docs/usdx-api-gaps.md](docs/usdx-api-gaps.md).

With such a build, drop `dist/usdx-tagger.usdx` into its `plugins/` directory. A release
build on Windows keeps that directory under `Program Files`, which needs administrator
rights; a build from source has a writable `game/plugins/` instead.

To confirm it loaded, look for `usdx-tagger` in `Error.log`:

```text
INFO:   usdx-tagger: ready, tag menu on "T"
```

## Contributing

Contributions are welcome. Tag-file behavior is expected to be covered by unit tests that
run without UltraStar Deluxe; see the testing requirements in
[docs/initial_idea.md](docs/initial_idea.md#14-testing-requirements).

## License

[GNU General Public License v3.0](LICENSE)
