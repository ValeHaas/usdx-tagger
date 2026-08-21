# Developing usdx-tagger

## Design

UltraStar-specific and platform-specific code is isolated behind adapters, so the tag
logic can be tested — and reused by other tools — without the game running.

```text
src/tagger/
├── version.lua   -- the semantic version, single source of truth
├── i18n.lua      -- message catalogues and language resolution
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
luacheck src spec build    # lint, if you have it
```

The plugin ships as a single `.usdx` file because UltraStar resolves only
`require('Usdx.*')` and its plugin directory is read-only in a release build, so
`build/bundle.lua` inlines the modules. It also runs the generated main chunk in a bare
environment as a build step — UltraStar executes a plugin's main chunk *before* opening
the standard library, and that check catches the resulting breakage at build time instead
of in the game.

`dist/` is not committed; build it when you need it, or take
`usdx-tagger.usdx` from a [release](https://github.com/ValeHaas/usdx-tagger/releases) or
from a CI run's artifacts.

### Git hooks

The same checks CI runs are available locally:

```bash
bash .githooks/install.sh
```

That sets `core.hooksPath`, so the hooks stay versioned and an update arrives with a
normal `git pull` — nothing is copied into `.git/hooks`.

| Hook | Runs |
|------|------|
| `pre-commit` | syntax, lint, unit tests |
| `pre-push` | the above, plus the plugin build, the built plugin, and the version checks |

`pre-commit` deliberately tests the **staged** tree, not your working directory: it
exports the index to a temporary directory and runs there. Committing a subset of your
changes is common, and the question worth answering is whether *that* passes.

`pre-push` additionally checks, when you push a `v*` tag, that the tag matches
`version.lua` — the release workflow would refuse it otherwise, and finding out before
the push is cheaper.

Both hooks find a Lua interpreter themselves, including one installed somewhere not on
`PATH`. Point `USDX_TAGGER_LUA` at a specific one if you need to. `luacheck` is optional
and is skipped with a note when it is absent.

Skip once with `git commit --no-verify`, or set `USDX_TAGGER_SKIP_HOOKS=1` to disable
both.

### What CI checks

Every push and pull request runs three jobs:

- **Lint** — `luacheck`, configured with `std = 'min'`. That standard is the intersection
  of every Lua standard library, so the lint doubles as a portability gate: using
  something that exists in 5.4 but not 5.1 fails the build.
- **Test** — the full suite on Lua 5.1, 5.2, 5.3 and 5.4 on Linux, plus 5.4 on Windows
  and macOS. UltraStar Deluxe links against whichever Lua its build used, and its own
  `COMPILING.md` allows any of 5.1–5.4, so all of them have to work. The Windows and
  macOS legs exist because the test runner and the tag writer both have
  platform-specific paths. Each leg syntax-checks every file, runs the unit tests, builds
  the plugin, and then drives the built plugin with the game stubbed out.
- **Version** — `src/tagger/version.lua` is a valid semantic version, and the value the
  tag writer stamps into song folders matches it.

### Cutting a release

Bump `src/tagger/version.lua`, commit, then tag it:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

The release workflow refuses to publish if the tag and `version.lua` disagree — otherwise
the download would stamp a different version into users' files than the one they think
they installed. It then runs the tests, builds the plugin, and attaches
`usdx-tagger.usdx` to a GitHub release.
