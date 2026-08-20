--[[
  Loads the built dist/usdx-tagger.usdx with UltraStar Deluxe stubbed out and
  drives it through real key events.

  This runs as its own process (see spec/run.lua) so the bundle's inlined
  modules are the ones under test, rather than the copies under src/ that the
  unit specs already loaded.

  Usage: lua spec/bundle_check.lua
]]

local BUNDLE = 'dist/usdx-tagger.usdx'

local runner = dofile('spec/runner.lua')
local test, equal, is_nil, is_true, contains =
  runner.test, runner.equal, runner.is_nil, runner.is_true, runner.contains

--------------------------------------------------------------------------
-- the UltraStar Deluxe stub
--------------------------------------------------------------------------

local host = {
  now = 0,
  song = nil,          -- what GetSelectedSong returns
  hooks = {},          -- event name -> global function name
  drawn = {},          -- text drawn this frame
  log = {},
  user_path = nil,
  registered = nil,
}

local ScreenSong = {
  GetSelectedSong = function()
    return host.song
  end,
}

local ScreenSing = {
  GetSongInfo = function()
    return nil
  end,
}

local Text = {
  Pos = function() end,
  Size = function() end,
  Style = function() end,
  Italic = function() end,
  Color = function() end,
  Width = function(s) return #s * 8 end,
  Print = function(s) host.drawn[#host.drawn + 1] = s end,
}

local Log = {}
for _, level in ipairs({ 'LogInfo', 'LogWarn', 'LogError', 'LogDebug', 'LogStatus' }) do
  Log[level] = function(msg)
    host.log[#host.log + 1] = level .. ': ' .. tostring(msg)
  end
end

local Usdx = {
  Version = function() return 'stub' end,
  Time = function() return host.now end,
  -- two results, as the game does: the path io wants, then a UTF-8 spelling for
  -- display. The second is deliberately unopenable, so a plugin that reaches for
  -- the wrong one fails here instead of on someone's non-ASCII profile.
  GetUserPath = function()
    return host.user_path, 'DISPLAY-ONLY' .. host.user_path
  end,
  ShutMeDown = function() end,
  Hook = function(event, func_name)
    -- mirrors ULuaCore: an unknown event is an error
    if event ~= 'ScreenSong.ParseInput'
       and event ~= 'ScreenSong.SongSelected'
       and event ~= 'Display.Draw' then
      error('event does not exist: ' .. tostring(event), 0)
    end
    host.hooks[event] = func_name
    return { Unhook = function() end }
  end,
}

-- UltraStar exposes Usdx as a global and the rest through require('Usdx.*'),
-- with the loader also installing a global of the short name
_G.Usdx = Usdx
_G.ScreenSong = ScreenSong
_G.ScreenSing = ScreenSing
_G.Text = Text
_G.Log = Log

-- UltraStar's module loader returns the SAME unrelated table for every Usdx.*
-- module (checked against v2026.8.1). Only the global it installs is correct.
-- The stub reproduces that, so a plugin that trusts require()'s return value
-- fails here exactly as it does in the game.
local BOGUS = { this_is_not_a_real_module = true }

package.preload['Usdx.ScreenSong'] = function() return BOGUS end
package.preload['Usdx.ScreenSing'] = function() return BOGUS end
package.preload['Usdx.Text'] = function() return BOGUS end
package.preload['Usdx.Log'] = function() return BOGUS end

function _G.register(name, version, author, url)
  host.registered = { name = name, version = version, author = author, url = url }
end

--------------------------------------------------------------------------
-- driving the plugin
--------------------------------------------------------------------------

local LF = string.char(10)

local KMOD_LSHIFT = 0x0001
local KMOD_LCTRL = 0x0040

local KEY_T = 116
local KEY_G = 103
local KEY_Z = 122
local KEY_ESC = 27
local KEY_ENTER = 13
local KEY_DOWN = 1073741824 + 81
local KEY_RIGHT = 1073741824 + 79

--- Sends a key-down event through the ParseInput hook.
-- @return whatever the hook returned (non-nil means the key was consumed)
local function press(key, mod)
  local fn = _G[host.hooks['ScreenSong.ParseInput']]
  return fn(true, { Key = key, Char = 0, Mod = mod or 0, Down = true })
end

--- Opens the tag menu, steps down `n` entries, toggles that entry, and closes.
local function menu_toggle(n)
  press(KEY_T)
  for _ = 1, (n or 0) do
    press(KEY_DOWN)
  end
  press(KEY_ENTER)
  press(KEY_ESC)
end

local function song_selected()
  local fn = _G[host.hooks['ScreenSong.SongSelected']]
  return fn(false)
end

local function draw()
  host.drawn = {}
  local fn = _G[host.hooks['Display.Draw']]
  fn(false)
  return host.drawn
end

local function screen()
  return table.concat(draw(), ' | ')
end

--- Lets any pending notification expire, so the next assertion sees only what
-- the step under test produced.
local function settle()
  host.now = host.now + 60000
  draw()
end

local function tagfile_path(dir)
  return dir .. '/.usdx-user-tags.yaml'
end

--- Writes an UltraStar config.ini into the stub user path.
-- Pinned deliberately: without a config there, the plugin would fall back to
-- %APPDATA%/ultrastardx/config.ini and pick up whatever language the developer
-- running the tests happens to play in, so the assertions below would depend on
-- the machine.
local function set_game_language(name)
  runner.write_file(host.user_path .. '/config.ini',
    '[Game]' .. LF .. 'Players=1' .. LF .. 'Language=' .. name .. LF)
end

--- Pushes the clock past the language re-check interval and fires the hook that
-- performs it, which is how a language change reaches the plugin mid-session.
local function refresh_language()
  host.now = host.now + 10000
  song_selected()
end

local function set_song(dir)
  host.song = {
    Path = dir,
    FileName = dir .. '/song.txt',
    PathUTF8 = dir,
    FileNameUTF8 = dir .. '/song.txt',
    Artist = 'Claude',
    Title = 'Smoke Test',
  }
end

--------------------------------------------------------------------------
-- load the bundle
--------------------------------------------------------------------------

host.user_path = runner.tmpdir('userpath')
set_game_language('English')

local chunk, load_err = loadfile(BUNDLE)
if not chunk then
  io.write('FATAL: bundle does not load: ', tostring(load_err), '\n')
  os.exit(1)
end
chunk()

test('the user path is taken from the first result, the one io can open', function()
  local io_path, display = Usdx.GetUserPath()
  is_true(io_path ~= display, 'the stub returns two different values')
  is_true(io.open(display .. '/config.ini', 'rb') == nil,
    'and the display one really is unopenable')
end)

test('the bundle exposes plugin_init', function()
  equal(type(_G.plugin_init), 'function')
end)

test('the stub reproduces UltraStar returning one shared table', function()
  -- guards the guard: if this stops being true, the plugin's workaround for it
  -- is no longer being tested
  is_true(require('Usdx.ScreenSong') == require('Usdx.Log'),
    'requires return the same table')
  is_true(require('Usdx.ScreenSong').GetSelectedSong == nil,
    'and it is not the real module')
end)

test('plugin_init registers and returns true', function()
  equal(plugin_init(), true, 'return value')
  is_true(host.registered ~= nil, 'register was called')
  equal(host.registered.name, 'usdx-tagger', 'plugin name')
  is_true(host.registered.version ~= nil and host.registered.version ~= '',
    'version passed')
end)

test('plugin_init hooks the three events it needs', function()
  equal(host.hooks['ScreenSong.ParseInput'], 'usdx_tagger_on_parse_input', 'ParseInput')
  equal(host.hooks['ScreenSong.SongSelected'], 'usdx_tagger_on_song_selected', 'SongSelected')
  equal(host.hooks['Display.Draw'], 'usdx_tagger_on_draw', 'Draw')
end)

--------------------------------------------------------------------------
-- tagging through the menu
--------------------------------------------------------------------------

test('the menu writes the tag file into the song directory', function()
  local dir = runner.tmpdir('menuadd')
  set_song(dir)

  menu_toggle(0) -- the first entry is the quick tag, "bad"

  local text = runner.read_file(tagfile_path(dir))
  is_true(text ~= nil, 'tag file created')
  contains(text, '- bad', 'holds the chosen tag')

  runner.rmdir(dir)
end)

test('toggling the same entry twice removes the tag again', function()
  local dir = runner.tmpdir('menutoggle')
  set_song(dir)

  menu_toggle(0)
  is_true(runner.file_exists(tagfile_path(dir)), 'created first')

  menu_toggle(0)
  equal(runner.file_exists(tagfile_path(dir)), false,
    'file deleted along with the last tag')

  runner.rmdir(dir)
end)

test('two different entries give two tags, with no duplicate', function()
  local dir = runner.tmpdir('menutwo')
  set_song(dir)

  menu_toggle(0) -- bad
  menu_toggle(1) -- review

  local text = runner.read_file(tagfile_path(dir))
  contains(text, '- bad', 'first tag')
  contains(text, '- review', 'second tag')

  local count = 0
  for _ in text:gmatch('%- bad') do count = count + 1 end
  equal(count, 1, 'bad appears once')

  runner.rmdir(dir)
end)

test('the retired quick-tag keys are no longer bound', function()
  local dir = runner.tmpdir('nog')
  set_song(dir)

  is_nil(press(KEY_G), 'G does nothing')
  is_nil(press(KEY_G, KMOD_LSHIFT), 'Shift+G does nothing')
  equal(runner.file_exists(tagfile_path(dir)), false, 'nothing written')

  runner.rmdir(dir)
end)

test('an unbound key is not consumed', function()
  local dir = runner.tmpdir('unbound')
  set_song(dir)

  is_nil(press(KEY_Z), 'z is left alone')
  is_nil(press(KEY_RIGHT), 'right arrow is left alone')

  runner.rmdir(dir)
end)

test('the menu key does not fire while shift is held', function()
  local dir = runner.tmpdir('shiftt')
  set_song(dir)

  is_nil(press(KEY_T, KMOD_LSHIFT), 'Shift+T is not the menu key')
  equal(runner.file_exists(tagfile_path(dir)), false, 'nothing written')

  runner.rmdir(dir)
end)

test('ctrl+T shows the tags instead of opening the menu', function()
  local dir = runner.tmpdir('ctrlt')
  set_song(dir)
  menu_toggle(0)
  settle()

  is_true(press(KEY_T, KMOD_LCTRL), 'consumed')
  contains(screen(), 'Tags:', 'tags reported')

  runner.rmdir(dir)
end)

--------------------------------------------------------------------------
-- notifications
--------------------------------------------------------------------------

test('tagging produces an on-screen confirmation', function()
  local dir = runner.tmpdir('notify')
  set_song(dir)
  settle()

  press(KEY_T)
  press(KEY_ENTER)
  press(KEY_ESC)

  contains(screen(), 'Added tag', 'confirmation text')

  runner.rmdir(dir)
end)

test('a notification expires', function()
  local dir = runner.tmpdir('expire')
  set_song(dir)
  settle()

  menu_toggle(0)
  is_true(#draw() > 0, 'visible right away')

  host.now = host.now + 60000
  equal(#draw(), 0, 'gone later')

  runner.rmdir(dir)
end)

--------------------------------------------------------------------------
-- the tag menu
--------------------------------------------------------------------------

test('the menu key opens a menu that draws entries', function()
  local dir = runner.tmpdir('menu')
  set_song(dir)
  settle()

  is_true(press(KEY_T), 'T consumed')

  local lines = screen()
  contains(lines, 'Tags', 'menu header')
  contains(lines, 'bad', 'a tag entry')
  contains(lines, '[ ]', 'unset marker')

  press(KEY_ESC)
  runner.rmdir(dir)
end)

test('the menu marks tags the song already carries', function()
  local dir = runner.tmpdir('menumark')
  set_song(dir)

  menu_toggle(0)          -- set "bad"
  settle()
  press(KEY_T)            -- reopen

  contains(screen(), '[x] bad', 'set marker')

  press(KEY_ESC)
  runner.rmdir(dir)
end)

test('the menu swallows keys while open', function()
  local dir = runner.tmpdir('menuswallow')
  set_song(dir)

  press(KEY_T)
  is_true(press(KEY_Z), 'z consumed by the menu')
  press(KEY_ESC)
  is_nil(press(KEY_Z), 'z free again once closed')

  runner.rmdir(dir)
end)

test('choosing a menu entry applies that tag', function()
  local dir = runner.tmpdir('menuchoose')
  set_song(dir)

  menu_toggle(1) -- one step down from the quick tag selects "review"

  local text = runner.read_file(tagfile_path(dir))
  is_true(text ~= nil, 'tag file created')
  contains(text, '- review', 'second entry applied')

  runner.rmdir(dir)
end)

test('escape closes the menu without tagging', function()
  local dir = runner.tmpdir('menuescape')
  set_song(dir)

  press(KEY_T)
  press(KEY_ESC)

  equal(runner.file_exists(tagfile_path(dir)), false, 'nothing written')
  runner.rmdir(dir)
end)

--------------------------------------------------------------------------
-- existing tags and error paths
--------------------------------------------------------------------------

test('selecting a tagged song reports its tags', function()
  local dir = runner.tmpdir('existing')
  set_song(dir)
  menu_toggle(0)
  settle()

  song_selected()
  contains(screen(), 'Tags:', 'tags reported')

  runner.rmdir(dir)
end)

test('with no current song nothing crashes and a warning shows', function()
  host.song = nil
  settle()

  is_true(press(KEY_T), 'key still consumed')
  contains(screen(), 'No song is selected', 'warning shown')
end)

test('an unsupported tag file is refused, not overwritten', function()
  local dir = runner.tmpdir('unsupported')
  set_song(dir)

  local original = 'version: 1\ntags: [bad, review]\n'
  runner.write_file(tagfile_path(dir), original)
  settle()

  press(KEY_T)

  equal(runner.read_file(tagfile_path(dir)), original, 'file untouched')
  contains(screen(), 'Cannot read', 'warning shown')

  runner.rmdir(dir)
end)

test('a song directory that vanished reports an error', function()
  local dir = runner.tmpdir('vanished')
  set_song(dir)
  runner.rmdir(dir)
  settle()

  menu_toggle(0)
  contains(screen(), 'Cannot save tags', 'error shown')
end)

test('a Unicode song directory works end to end', function()
  local dir = runner.tmpdir('Bj' .. string.char(195, 182) .. 'rk - Test!')
  set_song(dir)
  settle()

  menu_toggle(0)
  contains(runner.read_file(tagfile_path(dir)) or '', '- bad', 'tag written')

  runner.rmdir(dir)
end)

--------------------------------------------------------------------------
-- following UltraStar's language
--------------------------------------------------------------------------

test('the plugin reads the language out of UltraStar config.ini', function()
  local dir = runner.tmpdir('langde')
  set_song(dir)
  settle()

  set_game_language('German')
  refresh_language()
  settle()

  menu_toggle(0)
  contains(screen(), 'hinzugef' .. string.char(195, 188) .. 'gt',
    'the confirmation is German')

  runner.rmdir(dir)
end)

test('the log stays English while the screen is translated', function()
  local dir = runner.tmpdir('langlog')
  set_song(dir)
  settle()

  set_game_language('German')
  refresh_language()
  settle()

  local before = #host.log
  menu_toggle(0)

  local logged = {}
  for i = before + 1, #host.log do
    logged[#logged + 1] = host.log[i]
  end
  local text = table.concat(logged, ' | ')
  contains(text, 'Added tag', 'English in the log')
  contains(text, '"bad"', 'and the canonical tag name, not the translation')
  is_true(not text:find('schlecht', 1, true), 'no German in the log')

  runner.rmdir(dir)
end)

test('the tag menu header is translated too', function()
  local dir = runner.tmpdir('langmenu')
  set_song(dir)

  set_game_language('German')
  refresh_language()
  settle()

  press(KEY_T)
  contains(screen(), 'schaltet um', 'German menu header')
  press(KEY_ESC)

  runner.rmdir(dir)
end)

test('the menu shows translated tag names with the canonical name kept', function()
  local dir = runner.tmpdir('langlabels')
  set_song(dir)

  set_game_language('German')
  refresh_language()
  settle()

  press(KEY_T)
  local lines = screen()
  contains(lines, 'schlecht (bad)', 'translated label plus canonical name')
  contains(lines, 'Duplikat (duplicate)', 'and for the other entries')
  press(KEY_ESC)

  runner.rmdir(dir)
end)

test('the confirmation names the tag in the local language', function()
  local dir = runner.tmpdir('langconfirm')
  set_song(dir)

  set_game_language('German')
  refresh_language()
  settle()

  menu_toggle(0)
  contains(screen(), 'schlecht', 'translated tag on screen')

  runner.rmdir(dir)
end)

test('tag names are not translated, whatever the language', function()
  -- the whole point: the file has to stay greppable across machines
  local dir = runner.tmpdir('langtags')
  set_song(dir)

  set_game_language('German')
  refresh_language()
  settle()

  menu_toggle(0)
  local text = runner.read_file(tagfile_path(dir))
  contains(text, '- bad', 'the tag is still "bad"')
  contains(text, 'tags:', 'the key is still "tags"')

  runner.rmdir(dir)
end)

test('a language with no catalogue falls back to English', function()
  local dir = runner.tmpdir('langnone')
  set_song(dir)

  set_game_language('Icelandic')
  refresh_language()
  settle()

  menu_toggle(0)
  contains(screen(), 'Added tag', 'English confirmation')

  runner.rmdir(dir)
end)

test('going back to English takes effect without a restart', function()
  local dir = runner.tmpdir('langback')
  set_song(dir)

  set_game_language('German')
  refresh_language()
  settle()

  set_game_language('English')
  refresh_language()
  settle()

  menu_toggle(0)
  contains(screen(), 'Added tag', 'English again')

  runner.rmdir(dir)
end)

--------------------------------------------------------------------------
-- failures reach the log, not just the screen
--------------------------------------------------------------------------

test('a user-visible failure is also recorded in the log', function()
  host.song = nil
  settle()

  local before = #host.log
  press(KEY_T)

  is_true(#host.log > before, 'something was logged')
  contains(table.concat(host.log, ' | '), 'No song is selected',
    'the reason is in the log')
end)

runner.rmdir(host.user_path)

os.exit(runner.report() and 0 or 1)
