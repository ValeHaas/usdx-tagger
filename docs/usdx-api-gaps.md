# What this plugin needs from UltraStar Deluxe

This plugin does not run on a stock UltraStar Deluxe build. Its Lua API, as shipped in
`v2026.8.1`, cannot reach the two things a tagger fundamentally needs: which song the user
is pointing at, and a keypress to act on.

Everything below was verified against the source at `v2026.8.1` and by running a probe
plugin inside the game, not inferred from documentation.

## The Lua plugin system, as it actually is

It is alive and loaded: `src/lua/`, plugins are `.usdx` files discovered recursively
under `<install>/plugins`, the entry point is `plugin_init()` returning true, and
`ULuaCore.PrepareState` calls `lual_openLibs`, so the whole standard library including
`io` and `os` is available, unsandboxed. Drawing is possible through `Usdx.Text`.

What was missing:

| Needed | Status in a stock build |
|---|---|
| The selected song's directory | Not exposed. `ScreenSing` offered scores, rating, BPM, beats, rects, settings and `GetSongLines`; `Party` offered teams and ranking. Nothing reached `TSong.Path`. |
| Keyboard input | No input API and no key hook anywhere in `src/lua/`. |
| The song selection screen | Not hookable. The four hooks were `Usdx.LoadingFinished`, `Display.PreDraw`, `Display.Draw` and `ScreenSing.SongLoaded`. |
| A writable directory of the plugin's own | Not exposed. `Usdx` offered only `Version`, `Time`, `Hook` and `ShutMeDown`, and the plugin directory sits under the read-only shared path. |

The data all existed internally — `TSong.Path: IPath`, `FileName: IPath`, `Artist`/`Title`
in `src/base/USong.pas` — it simply had no route to Lua.

## The additions

Kept generic on purpose: no new dependency, no on-disk format, no opinion about tags.
They are useful to any plugin author, not just this one.

| Addition | Where |
|---|---|
| `ScreenSing.GetSongInfo()` | `src/lua/ULuaScreenSing.pas` |
| `Usdx.ScreenSong` module with `GetSelectedSong()` | new `src/lua/ULuaScreenSong.pas` |
| `ScreenSong.ParseInput` hook, breakable | `src/screens/UScreenSong.pas` |
| `ScreenSong.SongSelected` hook | `src/screens/UScreenSong.pas` |
| `Usdx.GetUserPath()`, two results | `src/lua/ULuaUsdx.pas` |
| `Lua_PushIOPath()` | `src/lua/ULuaUtils.pas` |

Both song getters return `Path`, `FileName`, `PathUTF8`, `FileNameUTF8`, `Artist` and
`Title`, or nil when there is no song to describe.

`Usdx.GetUserPath()` returns two values for the same reason those getters carry two spellings
of each path: the first is in the encoding Lua's `io` library expects, the second is UTF-8 for
display. On Windows they differ as soon as the path leaves the active code page, and using the
wrong one means either a failed open or mojibake on screen.

`ScreenSong.ParseInput` fires **after** the song menu and jump-to overlays have been
offered the key, so a plugin cannot steal input from an open menu. It receives a table:

```lua
{ Key = <SDL keycode>, Char = <code point or 0>, Mod = <KMOD_* mask>, Down = <boolean> }
```

Being breakable, a plugin **consumes** the key by returning any value from its hook and
**passes it on** by returning nothing.

## Three things that cost real debugging time

Recorded because none of them is discoverable from the wiki, and each produced a silent
failure rather than an error.

### The plugin's main chunk runs before the standard library exists

`ULuaCore.pas`, `TLuaPlugin.Load`, loads the file and calls it *before*
`LuaCore.PrepareState`. At main-chunk time there is no `package`, no `require`, no `io`,
no `string` — the comment in the source says so outright. Libraries only appear by the
time `plugin_init()` is called, which is why every stock plugin does its work inside
`plugin_init` and only defines functions at the top level.

A bundle that assigned to `package.preload` at the top level died with
*attempt to index a nil value (global 'package')* and the plugin was dropped. `build/bundle.lua`
now runs the generated main chunk in a bare environment as a build step, so this fails at
build time instead of in the game.

### `require` returns the wrong table

UltraStar's module loader hands back the *same unrelated table* for every `Usdx.*` module.
`require('Usdx.Log')`, `require('Usdx.ScreenSong')`, `require('Usdx.ScreenSing')` and
`require('Usdx.Text')` all returned one identical table. Only the global the loader
installs as a side effect is correct.

So `src/tagger/adapter.lua` calls `require` for the registration side effect and then
reads `_G.ScreenSong`. `spec/bundle_check.lua` reproduces the misleading return value, so
a regression here fails in the test suite rather than in the game.

### Lua cannot open a UTF-8 path on Windows

The first version of the API handed over `IPath.ToUTF8`, and every write into a song
folder with a non-ASCII name failed with *No such file or directory*. Lua's `io` library
goes straight to the narrow CRT, which reads bytes in the active ANSI code page; UTF-8
bytes there name a directory that does not exist. Confirmed directly: CP1252 bytes open
the file, the identical UTF-8 bytes do not.

Neither obvious conversion works:

- `IPath.ToNative` returns UTF-8, because UltraStar reaches the filesystem through the
  wide API and `IsNativeUTF8H()` is true.
- `SysUtils.Utf8ToAnsi` is a no-op, because `UMain.pas` calls
  `SetMultiByteConversionCodePage(CP_UTF8)` and thereby redefines the RTL's "ansi" as UTF-8.

`Lua_PushIOPath` therefore goes through UTF-16 and asks Windows for `CP_ACP` explicitly,
which is unaffected by either. A path holding characters the ANSI code page cannot
represent remains unreachable from Lua; that is a limit of the narrow CRT, and the plugin
reports the failure rather than pretending it built the path wrongly.

## Upstreaming

The additions are worth proposing upstream as *capabilities*, not as a tagging feature.
A feature PR would have to bring a YAML parser into a FreePascal project that has none,
and would invite the counter-proposal of storing tags in the existing SQLite database or
in the `.txt` header — either of which defeats the point of a file you can `grep`.

The project merges small, well-scoped changes quickly (`#1398` and `#1399` both landed
within a day) and redirects sprawling feature PRs (`#1369`, `#1370` and `#1385` were
closed unmerged in favour of a consolidated `#1386`).

One risk worth naming: issue `#469` asked in 2019 whether the Lua system was still alive
and was closed without a substantive answer. The API works, but it is undocumented beyond
a stub wiki page and has not grown in years, so maintainers may consider it legacy and
decline to extend it.

## Building the patched game

```bash
python dldlls.py                                   # DLLs and src/config-win.inc
7z x -y usdx-dlls-x86_64.zip -ogame "*.dll"
7z x -y usdx-dlls-x86_64.zip -osrc "config-win.inc"
```

Then build `src/ultrastardx.dpr` with FPC 3.2.2 for `x86_64-win64`. Note that the unit
search paths come from the `in '...'` clauses in the `.dpr`, which is the authoritative
unit list — a new unit has to be added there, not only to the `.lpi` files. `lib/ctypes`
must stay off the unit path for FPC builds, since FPC ships its own `ctypes` and the
local copy shadows it.

Install the plugin by dropping `dist/usdx-tagger.usdx` into `<install>/plugins/`. For a
release build on Windows that directory needs administrator rights; a build from source
uses the writable `game/plugins/` instead.
