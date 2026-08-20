-- luacheck configuration
--
-- Run with: luacheck src spec build

-- "min" is the intersection of every Lua standard library luacheck knows
-- about, so anything it flags would break on at least one of the versions
-- UltraStar Deluxe might have been linked against (5.1 through 5.5). That
-- makes the lint a portability gate, not just a style check.
std = 'min'

max_line_length = 100

-- Globals UltraStar Deluxe injects into a plugin's environment. Read-only:
-- the plugin has no business assigning to them.
read_globals = {
  'Usdx',
  'ScreenSong',
  'ScreenSing',
  'Text',
  'Log',
  'register',
  'current_filename',
}

files['src/tagger/'] = {
  -- The modules are loaded by the bundle's own require shim, which shadows the
  -- global require on purpose.
  allow_defined_top = false,
}

files['build/bundle.lua'] = {
  -- setfenv exists only in 5.1, which is why the bundler tests for it before
  -- use. std = 'min' is right to flag it; the guard is the answer.
  read_globals = { 'setfenv' },
}

files['spec/bundle_check.lua'] = {
  -- This spec loads the built plugin, which defines its entry points as
  -- globals, and stubs the host by assigning the globals UltraStar would.
  globals = {
    'plugin_init',
    'usdx_tagger_on_parse_input',
    'usdx_tagger_on_song_selected',
    'usdx_tagger_on_draw',
    'Usdx',
    'ScreenSong',
    'ScreenSing',
    'Text',
    'Log',
    'register',
  },
}

-- 542: empty if branch.
--
-- The tag-file and config readers walk a file one line at a time, and several
-- line kinds are deliberately no-ops ("blank or comment", "opaque, preserved").
-- Saying so in an empty branch reads better than folding it into an inverted
-- condition, and the comment is the point.
ignore = { '542' }
