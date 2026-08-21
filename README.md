# usdx-tagger

[![CI](https://github.com/ValeHaas/usdx-tagger/actions/workflows/ci.yml/badge.svg)](https://github.com/ValeHaas/usdx-tagger/actions/workflows/ci.yml)

An [UltraStar Deluxe](https://usdx.eu/) plugin for tagging songs from inside the game.

Press a key while a song is selected, previewing, or playing, and the plugin writes a
`.usdx-user-tags.yaml` file into that song's directory. The tags live next to the song,
so they can be found and processed with ordinary filesystem tools — no database, no
network, no separate service.

The primary use case is quickly flagging problematic songs during a karaoke session,
then reviewing them later.

## Why

During a party, nobody wants to alt-tab out of the game to note that a song has broken
lyrics or out-of-sync audio. Hit `T`, pick a tag, keep singing, sort it out tomorrow
with `grep`.

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

## Usage

Press `T` on the song selection screen and the tag menu opens over it. `[x]` marks a tag the
song already carries, so the same key both adds and removes.

![The tag menu open over the song selection screen](docs/tag-editor.png)

Moving through the songs shows what each one is already tagged with, so a glance tells you
what has been dealt with and what has not.

![Existing tags listed under the selected song](docs/tag-preview.png)

| Key | Action             |
|-----|--------------------|
| `T` | Open the tag menu  |

Tags are written to a `.usdx-user-tags.yaml` file next to the song, so they can be
searched with `grep` or `find` even without the game running, e.g.
`grep -rl -e '- bad$' Songs`.

See [docs/USAGE.md](docs/USAGE.md) for key bindings, configuration, language, the tag
file format, and more filesystem examples.

## Documentation

- [docs/USAGE.md](docs/USAGE.md) — key bindings, configuration, language, the tag file
  format, working with tags outside the game, guarantees, platform support
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — architecture, running tests, git hooks,
  what CI checks, cutting a release
- [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) — contribution guidelines

## License

[GNU General Public License v3.0](LICENSE)
