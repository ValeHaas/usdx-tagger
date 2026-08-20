#!/usr/bin/env bash
#
# Shared helpers for the git hooks in this directory.
#
# Sourced, never run directly.

set -uo pipefail

# ---------------------------------------------------------------- output

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_DIM=$'\033[2m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BOLD=''; C_OFF=''
fi

hook_name=''

say()  { printf '%s\n' "$*"; }
step() { printf '%s  %s%s ... ' "$C_DIM" "$*" "$C_OFF"; }
ok()   { printf '%sok%s\n' "$C_GREEN" "$C_OFF"; }
skip() { printf '%sskipped%s (%s)\n' "$C_YELLOW" "$C_OFF" "$*"; }
bad()  { printf '%sFAILED%s\n' "$C_RED" "$C_OFF"; }

die() {
  printf '\n%s%s: %s%s\n' "$C_RED$C_BOLD" "$hook_name" "$*" "$C_OFF" >&2
  printf 'Commit or push anyway with %s--no-verify%s, or set %sUSDX_TAGGER_SKIP_HOOKS=1%s.\n' \
    "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF" >&2
  exit 1
}

# Runs a command quietly, printing its output only when it fails. Hooks should
# be silent when everything is fine and loud when it is not.
run_step() {
  local label="$1"; shift
  local output status

  step "$label"
  output=$("$@" 2>&1)
  status=$?

  if [ $status -ne 0 ]; then
    bad
    printf '\n%s\n' "$output" >&2
    die "$label failed"
  fi

  ok
}

# ---------------------------------------------------------------- tooling

# Locates a Lua interpreter. PATH first, then the places the usual Windows and
# Unix installers put one, because a working Lua is frequently not on PATH.
find_lua() {
  local candidate

  if [ -n "${USDX_TAGGER_LUA:-}" ]; then
    printf '%s' "$USDX_TAGGER_LUA"
    return 0
  fi

  for candidate in lua lua5.4 lua54 lua5.3 lua53 lua5.2 lua5.1 luajit; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done

  # winget's Lua package, which does not put itself on PATH for every shell
  for candidate in \
    "${LOCALAPPDATA:-$HOME/AppData/Local}"/Microsoft/WinGet/Packages/DEVCOM.Lua_*/bin/lua.exe \
    "$HOME"/.luarocks/bin/lua \
    /usr/local/bin/lua /opt/homebrew/bin/lua
  do
    if [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  return 1
}

# Prints a command line that runs luacheck, or nothing when it is unavailable.
# Optional: a missing linter warns, it does not block a commit.
find_luacheck() {
  local lua="$1"
  local main

  if command -v luacheck >/dev/null 2>&1; then
    printf '%s' "$(command -v luacheck)"
    return 0
  fi

  # installed as a rock but without a usable wrapper, which is what luarocks
  # leaves behind on Windows
  for main in "$HOME"/.luarocks/share/lua/*/luacheck/main.lua; do
    if [ -f "$main" ]; then
      printf '%s' "$main"
      return 0
    fi
  done

  return 1
}

# Runs luacheck however it was found.
run_luacheck() {
  local lua="$1" luacheck="$2"; shift 2

  case "$luacheck" in
    *)
      if [ "${luacheck%main.lua}" = "$luacheck" ]; then
        # a real wrapper on PATH
        "$luacheck" "$@"
        return
      fi
      ;;
  esac

  # A bare rock with no usable wrapper: drive main.lua and point Lua at the
  # rock tree ourselves.
  local share lib script
  share=$(cd "$(dirname "$luacheck")/.." && pwd)          # .../share/lua/<ver>
  lib="${share%/share/lua/*}/lib/lua/${share##*/}"         # .../lib/lua/<ver>
  script="$luacheck"

  # Git Bash rewrites path-looking *arguments* for native executables but
  # leaves environment variables alone, so LUA_PATH has to be converted by
  # hand or lua.exe cannot read it.
  if command -v cygpath >/dev/null 2>&1; then
    share=$(cygpath -m "$share")
    lib=$(cygpath -m "$lib")
    script=$(cygpath -m "$script")
  fi

  LUA_PATH="$share/?.lua;$share/?/init.lua;;" \
  LUA_CPATH="$lib/?.so;$lib/?.dll;;" \
    "$lua" "$script" "$@"
}

# ---------------------------------------------------------------- checks

# Parses every file given, so a syntax error is reported as one clear failure
# rather than as a stack trace out of the test runner.
#
# The file list is expanded by the shell and passed in: an earlier version asked
# Lua to shell out to "ls", which silently enumerated nothing on Windows and so
# passed while checking zero files. Hence the count guard at the end - a check
# that cannot fail is worse than no check.
check_syntax() {
  local lua="$1"; shift
  local file out count=0 failures=''

  for file in "$@"; do
    [ -f "$file" ] || continue
    count=$((count + 1))

    # long-bracket string, so backslashes in Windows paths stay literal
    if ! out=$("$lua" -e "assert(loadfile([[$file]]))" 2>&1); then
      failures="$failures$out"$'\n'
    fi
  done

  if [ "$count" -eq 0 ]; then
    printf 'no Lua files found to check\n' >&2
    return 1
  fi

  if [ -n "$failures" ]; then
    printf '%s' "$failures" >&2
    return 1
  fi

  printf 'checked %d files\n' "$count"
}

# ---------------------------------------------------------------- setup

# Common preamble: honour the skip switch, move to the repository root, and
# resolve a Lua interpreter.
hook_setup() {
  hook_name="$1"

  if [ -n "${USDX_TAGGER_SKIP_HOOKS:-}" ]; then
    say "${C_YELLOW}$hook_name skipped${C_OFF} (USDX_TAGGER_SKIP_HOOKS is set)"
    exit 0
  fi

  local root
  root=$(git rev-parse --show-toplevel) || die 'not inside a git repository'
  cd "$root" || die "cannot enter $root"

  LUA=$(find_lua) || die 'no Lua interpreter found. Install one, or point USDX_TAGGER_LUA at it.'
  export LUA

  say "${C_BOLD}$hook_name${C_OFF} ${C_DIM}($("$LUA" -v 2>&1 | head -1))${C_OFF}"
}
