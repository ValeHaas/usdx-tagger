# usdx-tagger

An [UltraStar Deluxe](https://usdx.eu/) plugin for tagging songs from inside the game.

Press a key while a song is selected, previewing, or playing, and the plugin writes a
`.ultrastar-tags.yaml` file into that song's directory. The tags live next to the song,
so they can be found and processed with ordinary filesystem tools — no database, no
network, no separate service.

The primary use case is quickly flagging problematic songs during a karaoke session,
then reviewing them later.

> **Status:** early development. The requirements are specified in
> [docs/initial_idea.md](docs/initial_idea.md); the implementation is not complete yet.

## Why

During a party, nobody wants to alt-tab out of the game to note that a song has broken
lyrics or out-of-sync audio. Hit `G`, keep singing, sort it out tomorrow with `grep`.

## Tag file

Each tagged song directory gets one extra file:

```text
Songs/
└── Artist - Song Title/
    ├── Artist - Song Title.txt
    ├── Artist - Song Title.mp3
    └── .ultrastar-tags.yaml
```

```yaml
version: 1
tags:
  - bad-audio
  - review
```

The format is documented in full — including optional metadata, versioning, and the
minimal accepted file — in [docs/initial_idea.md](docs/initial_idea.md#4-yaml-file-format).

Notes on the format:

- `version` may be omitted; it then defaults to `1`.
- Tag names are arbitrary. They are trimmed, compared case-insensitively, and stored
  lowercase, so `Bad-Audio`, ` bad-audio `, and `bad-audio` are the same tag.
- Tag order is stable; new tags are appended.
- When the last tag is removed, the file is deleted by default (configurable), which
  keeps filesystem searches meaningful.

Suggested starting tags: `bad`, `review`, `bad-audio`, `bad-video`, `bad-lyrics`,
`bad-timing`, `duplicate`, `favorite`.

## Default key bindings

| Key       | Action                       |
|-----------|------------------------------|
| `G`       | Add the quick tag (`bad`)    |
| `Shift+G` | Remove the quick tag         |
| `T`       | Open the tag menu            |
| `Shift+T` | Remove a tag                 |
| `Ctrl+T`  | Show tags for current song   |

All shortcuts and the quick tag are configurable, so they can be moved out of the way of
UltraStar Deluxe's own controls.

## Configuration

Configuration lives in the platform-appropriate user config directory — never in the song
library:

```ini
enabled=true
quick_tag=bad
tag_menu_key=T
quick_add_key=G
quick_remove_key=Shift+G
show_notifications=true
show_existing_tags=true
delete_empty_tag_file=true
hide_marked_songs=false
```

Missing or malformed configuration falls back to defaults rather than failing to load.

## Working with tags outside the game

The whole point of a plain YAML file per song directory is that you don't need this
plugin — or UltraStar Deluxe — to use the data.

Find every tagged song:

```bash
find Songs -name '.ultrastar-tags.yaml'
```

List the directories of everything tagged `bad`:

```bash
grep -rl --include='.ultrastar-tags.yaml' -e '- bad$' Songs | xargs -n1 dirname
```

Move songs marked `review` into a quarantine folder:

```bash
grep -rl --include='.ultrastar-tags.yaml' -e '- review$' Songs \
  | xargs -n1 dirname \
  | xargs -I{} mv {} Quarantine/
```

PowerShell equivalent:

```powershell
Get-ChildItem -Recurse -Force -Filter '.ultrastar-tags.yaml' |
  Where-Object { (Get-Content $_.FullName) -match '^\s*-\s*bad\s*$' } |
  ForEach-Object { $_.Directory.FullName }
```

## Design

UltraStar-specific and platform-specific code is isolated behind adapters, so the tag
logic can be tested — and reused by other tools — without the game running.

```text
UltraStarTagsPlugin
├── UltraStarAdapter    -- current song, actions, notifications
├── TagService          -- add / remove / list / has / clear
├── TagFileRepository   -- load / save / exists / deleteIfEmpty
├── TagValidator
└── PluginConfig
```

`TagService` and `TagFileRepository` have no dependency on UltraStar Deluxe.

## Guarantees

The plugin owns exactly one file per song directory and nothing else. It will never:

- delete, rename, or move song directories,
- touch the `.txt`, audio, video, cover, or MIDI files,
- modify UltraStar song metadata by default,
- execute shell commands,
- require a database, network access, or administrator privileges.

Writes to `.ultrastar-tags.yaml` are atomic (temp file in the same directory, then
replace), YAML is parsed in safe mode with no object deserialization, and unknown fields
are preserved where possible. Errors — no current song, read-only directory, invalid
YAML, permission denied — surface as a notification and a log entry, never as a crash.

Song title and artist may be stored in the file for diagnostics, but the authoritative
identity of a song is always its actual filesystem path, obtained from UltraStar Deluxe
rather than reconstructed from artist and title.

## Platform support

Windows, Linux, and macOS, as far as the UltraStar Deluxe plugin API allows. Unicode
paths, spaces and punctuation, nested song directories, multiple song libraries, and
writable network mounts are all supported.

## Installation

Not yet available — the plugin has no releases. Installation instructions will follow the
first working version.

## Contributing

Contributions are welcome. Tag-file behavior is expected to be covered by unit tests that
run without UltraStar Deluxe; see the testing requirements in
[docs/initial_idea.md](docs/initial_idea.md#14-testing-requirements).

## License

[GNU General Public License v3.0](LICENSE)
