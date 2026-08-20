--[[
  adapter - the only module that talks to UltraStar Deluxe.

  Everything UltraStar-specific is confined here: the Usdx global, the
  require('Usdx.*') modules, the hook names and the drawing calls. The rest of
  the plugin sees plain Lua, which is what keeps the tag engine testable on its
  own and reusable outside the game.

  The modules this needs (ScreenSong, and Usdx.GetUserPath) only exist in an
  UltraStar build carrying the API additions described in docs/usdx-api-gaps.md.
  Every lookup is therefore guarded, and missing pieces are reported through
  probe() rather than raising during load.
]]

local adapter = {}

-- filled in by init(); nil until then
local M = {
  usdx = nil,
  screen_song = nil,
  screen_sing = nil,
  text = nil,
  log = nil,
}

--- Loads an UltraStar module and returns its table.
-- The value require() gives back cannot be trusted: UltraStar's module loader
-- returns the same unrelated table for every Usdx.* module (verified against
-- v2026.8.1, where Usdx.Log, Usdx.ScreenSong, Usdx.ScreenSing and Usdx.Text
-- all came back as one identical table). What it does reliably is install a
-- global named after the module, so that is what we read. The require call is
-- still needed, because it is what triggers the registration.
local function try_require(name)
  pcall(require, name)

  local short = name:match('%.([^.]+)$')
  if short and type(_G[short]) == 'table' then
    return _G[short]
  end

  return nil
end

--------------------------------------------------------------------------
-- setup
--------------------------------------------------------------------------

--- Resolves the UltraStar modules. Safe to call more than once.
function adapter.init()
  M.usdx = type(_G.Usdx) == 'table' and _G.Usdx or nil
  M.screen_song = try_require('Usdx.ScreenSong')
  M.screen_sing = try_require('Usdx.ScreenSing')
  M.text = try_require('Usdx.Text')
  M.log = try_require('Usdx.Log')
  return adapter
end

--- Reports what is and is not available, so init can refuse to run with a
-- clear message instead of failing later at an arbitrary keypress.
-- @return ok, array of missing capability names
function adapter.probe()
  local missing = {}

  if not M.usdx then
    missing[#missing + 1] = 'the Usdx global'
  elseif type(M.usdx.GetUserPath) ~= 'function' then
    missing[#missing + 1] = 'Usdx.GetUserPath()'
  end

  if not M.screen_song then
    missing[#missing + 1] = 'the Usdx.ScreenSong module'
  elseif type(M.screen_song.GetSelectedSong) ~= 'function' then
    missing[#missing + 1] = 'ScreenSong.GetSelectedSong()'
  end

  return #missing == 0, missing
end

--------------------------------------------------------------------------
-- logging
--------------------------------------------------------------------------

local function log_at(level, message)
  if M.log and type(M.log[level]) == 'function' then
    M.log[level]('usdx-tagger: ' .. message, 'usdx-tagger')
  end
end

function adapter.log_info(message)  log_at('LogInfo', message) end
function adapter.log_warn(message)  log_at('LogWarn', message) end
function adapter.log_error(message) log_at('LogError', message) end

--------------------------------------------------------------------------
-- the current song
--------------------------------------------------------------------------

local function clean_song(song)
  if type(song) ~= 'table' then
    return nil
  end
  if type(song.Path) ~= 'string' or song.Path == '' then
    return nil
  end
  return {
    -- Path is in the platform's native encoding, which is what Lua's io
    -- library needs; PathUTF8 is only for showing to a human
    path = song.Path,
    filename = song.FileName,
    path_utf8 = song.PathUTF8 or song.Path,
    artist = song.Artist or '',
    title = song.Title or '',
  }
end

--- The song the user is pointing at, wherever they are.
-- Prefers the song selection screen, then the song being sung, so the same
-- action works on the select screen and during gameplay.
-- @return {path=, filename=, artist=, title=} or nil
function adapter.current_song()
  if M.screen_song and type(M.screen_song.GetSelectedSong) == 'function' then
    local ok, song = pcall(M.screen_song.GetSelectedSong)
    if ok then
      local cleaned = clean_song(song)
      if cleaned then
        return cleaned
      end
    end
  end

  if M.screen_sing and type(M.screen_sing.GetSongInfo) == 'function' then
    local ok, song = pcall(M.screen_sing.GetSongInfo)
    if ok then
      local cleaned = clean_song(song)
      if cleaned then
        return cleaned
      end
    end
  end

  return nil
end

--- A human-readable name for notifications.
function adapter.song_label(song)
  if not song then
    return '?'
  end
  if song.artist ~= '' and song.title ~= '' then
    return song.artist .. ' - ' .. song.title
  end
  if song.title ~= '' then
    return song.title
  end
  return song.path_utf8 or song.path
end

--------------------------------------------------------------------------
-- misc host services
--------------------------------------------------------------------------

--- The writable user directory, or nil.
function adapter.user_path()
  if M.usdx and type(M.usdx.GetUserPath) == 'function' then
    local ok, path = pcall(M.usdx.GetUserPath)
    if ok and type(path) == 'string' and path ~= '' then
      return path
    end
  end
  return nil
end

--- Milliseconds on the same clock UltraStar uses.
function adapter.time()
  if M.usdx and type(M.usdx.Time) == 'function' then
    local ok, t = pcall(M.usdx.Time)
    if ok and type(t) == 'number' then
      return t
    end
  end
  return 0
end

--- Registers `func_name` (a global function) for `event`.
-- @return true, or false plus an error message
function adapter.hook(event, func_name)
  if not (M.usdx and type(M.usdx.Hook) == 'function') then
    return false, 'Usdx.Hook is unavailable'
  end
  local ok, err = pcall(M.usdx.Hook, event, func_name)
  if not ok then
    return false, tostring(err)
  end
  return true
end

--------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------

--- Draws one line of text. Coordinates are in the same space UltraStar uses
-- for its own screens (800x600 virtual pixels).
function adapter.draw_text(x, y, size, r, g, b, a, message)
  local text = M.text
  if not text then
    return false
  end

  local ok = pcall(function()
    text.Pos(x, y)
    text.Size(size)
    text.Style(0)
    text.Color(r, g, b, a)
    text.Print(message)
  end)

  return ok
end

--- Width of `message` with the current font settings, or nil.
function adapter.text_width(message)
  if not (M.text and type(M.text.Width) == 'function') then
    return nil
  end
  local ok, w = pcall(M.text.Width, message)
  if ok and type(w) == 'number' then
    return w
  end
  return nil
end

adapter._modules = M

return adapter
