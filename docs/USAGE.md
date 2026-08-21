# Using usdx-tagger

Everything beyond the quick start in the [README](../README.md): key bindings, configuration,
language, the tag file itself, and working with tags outside the game.

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
language=auto
```

`quick_tag` is the tag placed first in the menu, so the most common choice is one
keystroke away.

`language` is `auto` — follow UltraStar — or one of `English`, `German`, `French`, `Spanish`,
`Italian`, `Dutch`, `Portuguese`, `Polish`, `Russian`, `Swedish`. A name with no translation
is reported in the log instead of silently showing English.

Key bindings accept modifiers: `T`, `Shift+T`, `Ctrl+T`, `Alt+F5`, and the named keys
`Space`, `Escape`, `Return`, `Tab`, the arrows, and `F1`-`F12`.

A missing file, a missing key, or a malformed value each fall back to the default and are
noted in UltraStar Deluxe's log rather than failing to load.

## Language

The plugin follows whatever language UltraStar Deluxe is set to. Play in German and the menu,
the confirmations and the tag names are German.

Translations exist for German, French, Spanish, Italian, Dutch, Portuguese, Polish, Russian
and Swedish. Any other language falls back to English. They have **not** been reviewed by
native speakers, so corrections are welcome — a language lives in one table in
[src/tagger/i18n.lua](../src/tagger/i18n.lua), and adding a new one is a data-only change.

**The tag written to the file is never translated.** Only its display name is:

```text
Tags  (auf/ab, Enter schaltet um, Esc schließt)
> [x] schlecht (bad)
  [ ] prüfen (review)
  [ ] Ton fehlerhaft (bad-audio)
```

The file still says `- bad`, so `grep` keeps working across machines and across languages,
which is the entire reason the file exists. The canonical name stays visible in the menu for
the same reason: a player who only ever saw `schlecht` would have no idea what to search for
later.

UltraStar's log also stays English, since log lines end up in bug reports read by people who
do not share the player's language.

Set `language=` in the config to pin the plugin to one language regardless of the game, or
leave it at `auto`. How the game's setting is discovered, and what else turned out to be
reachable from a plugin, is written up in [i18n.md](i18n.md).

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
minimal accepted file — in [FORMAT.md](FORMAT.md).

Notes on the format:

- `version` is the [semantic version](https://semver.org) of the plugin that last wrote
  the file. It may be omitted, and an unfamiliar value is read rather than rejected, so a
  file written by a newer plugin never costs you your tags.
- Tag names are arbitrary. They are trimmed, compared case-insensitively, and stored
  lowercase, so `Bad-Audio`, ` bad-audio `, and `bad-audio` are the same tag.
- Tag order is stable; new tags are appended.
- When the last tag is removed, the file is deleted by default (configurable), which
  keeps filesystem searches meaningful.

Suggested starting tags: `good`, `duplicate`, `bad-audio`, `bad-video`, `bad-lyrics`,
`bad-timing`, `bad-notes`, `bad`.

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
