#!/usr/bin/env bash
#
# Points git at the hooks in this directory.
#
#   bash .githooks/install.sh
#
# This sets core.hooksPath rather than copying anything into .git/hooks, so the
# hooks stay versioned and an update arrives with a normal pull.

set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"

git config core.hooksPath .githooks

# The repository is often cloned on Windows with core.filemode off, which loses
# the executable bit. Put it back in the index so other platforms get it.
for hook in .githooks/pre-commit .githooks/pre-push .githooks/lib.sh .githooks/install.sh; do
  chmod +x "$hook" 2>/dev/null || true
  git update-index --chmod=+x "$hook" 2>/dev/null || true
done

printf 'hooks installed: core.hooksPath = %s\n' "$(git config core.hooksPath)"
printf 'pre-commit  syntax, lint, unit tests (against the staged tree)\n'
printf 'pre-push    the above plus the plugin build, the built plugin, and version checks\n'
printf '\nSkip once with --no-verify, or always with USDX_TAGGER_SKIP_HOOKS=1.\n'
printf 'If your Lua is not on PATH, point USDX_TAGGER_LUA at it.\n'
