--[[
  Bundles src/tagger/*.lua into one dist/usdx-tagger.usdx.

  UltraStar loads a plugin as a single .usdx file and only resolves
  require('Usdx.*') through its own searcher; there is no documented way to
  require a file next to the plugin, and the plugin directory is read-only in a
  released build. So the modules are inlined.

  The important constraint is spelled out in ULuaCore.pas, TLuaPlugin.Load: the
  plugin file's main chunk is executed BEFORE the Lua state is prepared, so at
  that point there is no standard library at all - no package, no require, no
  io, no string. Libraries only exist by the time plugin_init() is called.

  Therefore the generated file's main chunk only *defines* things: local
  tables, closures and global functions, none of which touch a library. Every
  module factory is invoked later, from inside plugin_init(). A local `require`
  shadows the global one for the inlined modules and delegates anything else
  (the Usdx.* modules) to the host's require, which exists by then.

  Run from the repository root:  lua build/bundle.lua
]]

local OUT_DIR = 'dist'
local OUT_FILE = OUT_DIR .. '/usdx-tagger.usdx'

local MODULES = {
  'version',
  'tagset',
  'tagfile',
  'keys',
  'config',
  'notify',
  'adapter',
  'init',
}

local HEADER = [[
--[==[ UltraStar Deluxe song tagger

  Tags the selected song by writing .usdx-user-tags.yaml into its directory.

  GENERATED FILE - do not edit. Built from src/tagger/ by build/bundle.lua.
  Source and documentation: https://github.com/ValeHaas/usdx-tagger

  Requires an UltraStar Deluxe build that exposes ScreenSong.GetSelectedSong,
  the ScreenSong.ParseInput hook and Usdx.GetUserPath. See docs/usdx-api-gaps.md.

  This program is free software; you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free Software
  Foundation; either version 2 of the License, or (at your option) any later
  version.
]==]

-- Nothing in this chunk may call a library function: UltraStar runs the file
-- body before it opens the standard libraries (ULuaCore.pas, TLuaPlugin.Load).
-- Definitions only. The work happens in plugin_init().

local _factories = {}
local _loaded = {}

--- Resolves an inlined module, or defers to the host for anything else.
-- Shadows the global require for the rest of this chunk, including the module
-- bodies below, which is how their require('tagger.x') calls find each other.
local function require(name)
  local mod = _loaded[name]
  if mod ~= nil then
    return mod
  end

  local factory = _factories[name]
  if factory then
    mod = factory()
    _loaded[name] = mod
    return mod
  end

  -- the Usdx.* modules; _G and the real require exist by plugin_init time
  return _G.require(name)
end
]]

local FOOTER_TEMPLATE = [[

--------------------------------------------------------------------------
-- UltraStar entry points
--------------------------------------------------------------------------

-- assigned by plugin_init once the libraries are available
local tagger = nil

-- Hooks are registered by name, so the callbacks have to be globals. Each one
-- guards against being called before startup finished.
function usdx_tagger_on_parse_input(breakable, event)
  if not tagger then return end
  return tagger.on_parse_input(breakable, event)
end

function usdx_tagger_on_song_selected(breakable)
  if not tagger then return end
  return tagger.on_song_selected(breakable)
end

function usdx_tagger_on_draw(breakable)
  if not tagger then return end
  return tagger.on_draw(breakable)
end

function plugin_init()
  register('usdx-tagger', '@VERSION@', 'Valentin Haas',
           'https://github.com/ValeHaas/usdx-tagger')

  -- A plugin that returns false is unloaded, and a failure here is not worth
  -- taking the game down for, so problems are logged and the plugin stays
  -- inert instead.
  local ok, err = pcall(function()
    tagger = require('tagger.init')
    tagger.start()
  end)

  if not ok then
    tagger = nil
    if Log and Log.LogError then
      Log.LogError('usdx-tagger failed to start: ' .. tostring(err), 'usdx-tagger')
    end
  end

  return true
end
]]

--------------------------------------------------------------------------

local function read(path)
  local fh = assert(io.open(path, 'rb'), 'cannot read ' .. path)
  local text = fh:read('*a')
  fh:close()
  return text
end

--- Reads the plugin version from version.lua, the single source of truth.
local function detect_version(version_source)
  local version = version_source:match("return%s*'([^']+)'")
  -- one value only: assert returns its message too, which would land in
  -- gsub's replacement-count argument
  assert(version, 'could not find the version string in version.lua')
  assert(version:match('^%d+%.%d+%.%d+'),
    'version.lua must hold a semantic version, got ' .. version)
  return version
end

local function mkdir(path)
  local is_windows = package.config:sub(1, 1) == string.char(92)
  if is_windows then
    os.execute('mkdir "' .. path:gsub('/', string.char(92)) .. '" 2>nul')
  else
    os.execute("mkdir -p '" .. path .. "'")
  end
end

local sources = {}
for i = 1, #MODULES do
  sources[MODULES[i]] = read('src/tagger/' .. MODULES[i] .. '.lua')
end

local parts = { HEADER }

for i = 1, #MODULES do
  local name = MODULES[i]
  local body = sources[name]

  -- a trailing line comment without a newline would swallow our "end"
  if body:sub(-1) ~= '\n' then
    body = body .. '\n'
  end

  parts[#parts + 1] = string.format(
    '\n--------------------------------------------------------------------------\n' ..
    '-- src/tagger/%s.lua\n' ..
    '--------------------------------------------------------------------------\n' ..
    '_factories[%q] = function()\n%s\nend\n',
    name, 'tagger.' .. name, body)
end

parts[#parts + 1] = (FOOTER_TEMPLATE:gsub('@VERSION@', detect_version(sources.version)))

local text = table.concat(parts)

mkdir(OUT_DIR)

local out = assert(io.open(OUT_FILE, 'wb'), 'cannot write ' .. OUT_FILE)
out:write(text)
out:close()

--------------------------------------------------------------------------
-- checks that would otherwise only fail inside the game
--------------------------------------------------------------------------

local chunk, err = loadfile(OUT_FILE)
if not chunk then
  io.stderr:write('bundle does not parse: ', tostring(err), '\n')
  os.exit(1)
end

-- The main chunk must survive running with no standard library, because that
-- is exactly how UltraStar executes it. Run it in an environment holding only
-- the globals UltraStar has set by then, and confirm it defines the entry
-- points without reaching for anything else.
local sandbox = {}
local sandbox_ok, sandbox_err

if setfenv then                                  -- Lua 5.1
  setfenv(chunk, sandbox)
  sandbox_ok, sandbox_err = pcall(chunk)
else                                             -- Lua 5.2+
  local bare = loadfile(OUT_FILE, 't', sandbox)
  if not bare then
    io.stderr:write('bundle does not load into a bare environment\n')
    os.exit(1)
  end
  sandbox_ok, sandbox_err = pcall(bare)
end

if not sandbox_ok then
  io.stderr:write('main chunk needs a standard library, which UltraStar has ',
                  'not opened yet: ', tostring(sandbox_err), '\n')
  os.exit(1)
end

for _, name in ipairs({ 'plugin_init', 'usdx_tagger_on_parse_input',
                        'usdx_tagger_on_song_selected', 'usdx_tagger_on_draw' }) do
  if type(sandbox[name]) ~= 'function' then
    io.stderr:write('bundle did not define ', name, '\n')
    os.exit(1)
  end
end

io.write(string.format('wrote %s (%d modules, %d bytes)\n',
  OUT_FILE, #MODULES, #text))
io.write('main chunk runs without a standard library and defines all entry points\n')
