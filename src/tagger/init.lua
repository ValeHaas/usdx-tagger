--[[
  init - the plugin itself: configuration, key handling and the tag menu.

  This is the only module that knows about both halves. It talks to UltraStar
  through the adapter and to the filesystem through tagfile/tagset, so neither
  side depends on the other.

  Portable Lua 5.1 - 5.5.
]]

local adapter = require('tagger.adapter')
local config  = require('tagger.config')
local i18n    = require('tagger.i18n')
local keys    = require('tagger.keys')
local notify  = require('tagger.notify')
local tagfile = require('tagger.tagfile')
local tagset  = require('tagger.tagset')

local tagger = {}

tagger.VERSION = require('tagger.version')

--- Reports a problem to the user and to the plugin log. Every user-visible
-- failure goes through here, so nothing is only ever shown on screen and then
-- lost (the requirements ask for diagnostics in a log).
--
-- The screen gets the user's language; the log always gets English, because
-- log lines end up in bug reports read by people who do not share it.
local function problem(key, vars, detail)
  notify.warn(i18n.t(key, vars))
  local logged = i18n.en(key, vars)
  adapter.log_warn(detail and (logged .. ' (' .. tostring(detail) .. ')') or logged)
end

--- A message to show later: a catalogue key plus its placeholder values.
local function msg(key, vars)
  return { key = key, vars = vars }
end

local state = {
  ready = false,
  cfg = nil,
  unknown_cfg = nil,
  bindings = {},
  menu = nil, -- {tags = {...}, index = n} while the tag menu is open
  game_language = nil,
  language_checked_at = nil,
}

-- How often the game's language setting is re-read. It only changes when the
-- user leaves the options screen, so this is about not reading a file on every
-- step of a roulette spin, not about catching a fast-moving value.
local LANGUAGE_RECHECK_MS = 3000

tagger._state = state

--------------------------------------------------------------------------
-- tag operations
--------------------------------------------------------------------------

--- Reads the tags of a song directory.
-- @return tags array, and the loaded file state (for a later save)
local function read_tags(dir)
  local st = tagfile.load(dir)

  if st.present and not st.supported then
    return nil, st
  end

  local clean, rejected = tagset.sanitize(st.tags)
  if #rejected > 0 then
    adapter.log_warn(string.format('%s: ignored %d unusable tag entries',
      st.path, #rejected))
  end

  return clean, st
end

--- Applies `change` to the current song's tags and saves.
-- `change(tags)` must return a message on success, or nil to report no change.
local function update_current(change)
  local song = adapter.current_song()
  if not song then
    problem('no_song')
    return
  end

  local tags, st = read_tags(song.path)
  if not tags then
    problem('read_failed', { file = tagfile.FILENAME }, st.err)
    return
  end

  local message, failure = change(tags, song)
  if not message then
    if failure then
      problem(failure.key, failure.vars)
    end
    return
  end

  local ok, save_err = tagfile.save(st, tags, {
    delete_when_empty = state.cfg.delete_empty_tag_file,
  })

  if not ok then
    problem('save_failed', { error = tostring(save_err) }, st.path)
    return
  end

  notify.info(i18n.t(message.key, message.vars))
  adapter.log_info(i18n.en(message.key, message.vars))
end

--- Adds one tag to the current song.
function tagger.add_tag(tag)
  update_current(function(tags, song)
    local out, changed = tagset.add(tags, tag)
    if not out then
      return nil, msg('bad_tag', { error = tostring(changed) })
    end
    local vars = { tag = tag, song = adapter.song_label(song) }
    if not changed then
      return msg('tag_already_set', vars)
    end
    return msg('tag_added', vars)
  end)
end

--- Removes one tag from the current song.
function tagger.remove_tag(tag)
  update_current(function(tags, song)
    local out, changed = tagset.remove(tags, tag)
    if not out then
      return nil, msg('bad_tag', { error = tostring(changed) })
    end
    local vars = { tag = tag, song = adapter.song_label(song) }
    if not changed then
      return msg('tag_not_set', vars)
    end
    return msg('tag_removed', vars)
  end)
end

--- Shows the current song's tags.
function tagger.show_tags()
  local song = adapter.current_song()
  if not song then
    problem('no_song')
    return
  end

  local tags, st = read_tags(song.path)
  if not tags then
    problem('read_failed', { file = tagfile.FILENAME }, st.err)
    return
  end

  if #tags == 0 then
    notify.info(i18n.t('no_tags', { song = adapter.song_label(song) }))
  else
    -- the list goes in as canonical names; i18n renders the display ones
    notify.info(i18n.t('tags_list', { tags = tags }))
  end
end

--------------------------------------------------------------------------
-- the tag menu
--------------------------------------------------------------------------

--- Builds the menu list: recently used tags first, then the suggestions.
local function menu_tags()
  local out = {}
  local seen = {}

  local function append(tag)
    local norm = tagset.normalize(tag)
    if norm and not seen[norm] then
      seen[norm] = true
      out[#out + 1] = norm
    end
  end

  -- the quick tag is the most likely choice, so it leads
  append(state.cfg.quick_tag)
  for i = 1, #config.SUGGESTED_TAGS do
    append(config.SUGGESTED_TAGS[i])
  end

  return out
end

function tagger.open_menu()
  local song = adapter.current_song()
  if not song then
    problem('no_song')
    return
  end

  local current = read_tags(song.path)
  if not current then
    problem('read_failed', { file = tagfile.FILENAME })
    return
  end

  state.menu = { tags = menu_tags(), index = 1, current = current }
end

--- Re-reads the current song's tags so the menu keeps showing the truth after
-- a toggle.
local function refresh_menu()
  if not state.menu then
    return
  end

  local song = adapter.current_song()
  if not song then
    tagger.close_menu()
    return
  end

  state.menu.current = read_tags(song.path) or {}
end

function tagger.close_menu()
  state.menu = nil
end

function tagger.menu_is_open()
  return state.menu ~= nil
end

--- Handles a key while the menu is open.
-- @return true when the key was consumed
local function menu_key(event)
  local menu = state.menu
  local key = event.Key

  if key == keys.NAMED.escape then
    tagger.close_menu()
    return true
  end

  if key == keys.NAMED.up then
    menu.index = menu.index - 1
    if menu.index < 1 then menu.index = #menu.tags end
    return true
  end

  if key == keys.NAMED.down then
    menu.index = menu.index + 1
    if menu.index > #menu.tags then menu.index = 1 end
    return true
  end

  if key == keys.NAMED['return'] then
    local tag = menu.tags[menu.index]
    if tag then
      -- toggle: the menu is the only way in and out, so selecting a tag the
      -- song already carries removes it again
      if tagset.has(menu.current, tag) then
        tagger.remove_tag(tag)
      else
        tagger.add_tag(tag)
      end
      -- stay open so several tags can be set in one visit
      refresh_menu()
    end
    return true
  end

  -- swallow everything else so the song screen does not act on keys aimed at
  -- the menu
  return true
end

--- Draws the menu. Called from the same Display.Draw hook as notifications.
local function draw_menu()
  local menu = state.menu
  if not menu then
    return
  end

  adapter.draw_text(20, 120, 22, 1, 1, 1, 1, i18n.t('menu_title'))

  for i = 1, #menu.tags do
    local tag = menu.tags[i]
    local y = 120 + i * 24
    local mark = tagset.has(menu.current, tag) and '[x] ' or '[ ] '
    -- translated for reading, canonical name kept alongside for grepping later
    local label = i18n.tag_entry(tag)

    if i == menu.index then
      adapter.draw_text(30, y, 20, 1, 0.85, 0.25, 1, '> ' .. mark .. label)
    else
      adapter.draw_text(30, y, 20, 0.8, 0.8, 0.8, 1, '  ' .. mark .. label)
    end
  end
end

--------------------------------------------------------------------------
-- hooks
--------------------------------------------------------------------------

--- ScreenSong.ParseInput. Returning any value consumes the key, so this
-- returns true only for keys it actually handled and nothing otherwise.
function tagger.on_parse_input(_breakable, event)
  if not state.ready or type(event) ~= 'table' then
    return
  end

  if state.menu then
    if event.Down ~= true then
      return -- let key releases through while the menu is open
    end
    if menu_key(event) then
      return true
    end
    return
  end

  local b = state.bindings

  if keys.matches(b.tag_menu, event) then
    tagger.open_menu()
    return true
  end

  if keys.matches(b.show_tags, event) then
    tagger.show_tags()
    return true
  end

  -- not ours: fall through so the song screen behaves normally
end

--- Re-reads the language if it has not been checked recently, so switching
-- UltraStar's language takes effect without restarting the game.
local function maybe_refresh_language()
  if state.cfg.language ~= 'auto' then
    return -- pinned; the game's setting is irrelevant
  end

  local now = adapter.time()
  if state.language_checked_at and (now - state.language_checked_at) < LANGUAGE_RECHECK_MS then
    return
  end
  state.language_checked_at = now

  adapter.forget_game_language()
  local found = adapter.game_language()
  if found == state.game_language then
    return
  end

  state.game_language = found
  local chosen = i18n.set_language(i18n.resolve('auto', found))
  adapter.log_info('language is now ' .. chosen .. ' (UltraStar reports '
    .. tostring(found) .. ')')
end

--- ScreenSong.SongSelected. Shows the tags a song already carries.
function tagger.on_song_selected()
  if not state.ready then
    return
  end

  maybe_refresh_language()

  if not state.cfg.show_existing_tags then
    return
  end

  local song = adapter.current_song()
  if not song then
    return
  end

  local tags = read_tags(song.path)
  if tags and #tags > 0 then
    notify.info(i18n.t('tags_list', { tags = tags }))
  end
end

--- Display.Draw, every frame.
function tagger.on_draw()
  if not state.ready then
    return
  end
  draw_menu()
  notify.draw()
end

--------------------------------------------------------------------------
-- startup
--------------------------------------------------------------------------

local function load_config()
  local dir = adapter.user_path()
  if not dir then
    adapter.log_warn('no user path available, using default settings')
    return config.defaults(), {}
  end

  local path = config.path_in(dir)
  local cfg, warnings, unknown = config.load(path)

  for i = 1, #warnings do
    adapter.log_warn(path .. ': ' .. warnings[i])
  end

  return cfg, unknown
end

local function parse_bindings(cfg)
  local out, problems = {}, {}

  local wanted = {
    tag_menu = cfg.tag_menu_key,
    show_tags = cfg.show_tags_key,
  }

  for name, spec in pairs(wanted) do
    local binding, err = keys.parse(spec)
    if binding then
      out[name] = binding
    else
      problems[#problems + 1] = string.format('%s: %s', name, err)
    end
  end

  return out, problems
end

--- Sets the plugin up. Returns true when it is running.
function tagger.start()
  adapter.init()

  local ok, missing = adapter.probe()
  if not ok then
    adapter.log_error('disabled, this UltraStar build is missing: '
      .. table.concat(missing, ', '))
    return false
  end

  -- Follow the game before anything can produce a user-visible message. The
  -- config may override this a few lines down, but it cannot be read yet.
  state.game_language = adapter.game_language()
  i18n.set_language(i18n.resolve('auto', state.game_language))

  state.cfg, state.unknown_cfg = load_config()

  if not state.cfg.enabled then
    adapter.log_info('disabled by configuration')
    return false
  end

  local chosen, why = i18n.resolve(state.cfg.language, state.game_language)
  i18n.set_language(chosen)
  state.language_checked_at = adapter.time()
  if why == 'game' then
    adapter.log_info('language ' .. chosen .. ', following UltraStar')
  elseif why == 'pinned' then
    adapter.log_info('language ' .. chosen .. ', pinned by configuration')
  else
    adapter.log_info('language ' .. chosen .. ' (UltraStar reports '
      .. tostring(state.game_language) .. ', no catalogue for it)')
  end

  local bindings, problems = parse_bindings(state.cfg)
  for i = 1, #problems do
    adapter.log_warn('ignoring binding, ' .. problems[i])
  end
  state.bindings = bindings

  notify.configure({
    enabled = state.cfg.show_notifications,
    duration_ms = state.cfg.notification_ms,
    clock = adapter.time,
    draw_text = adapter.draw_text,
  })

  local hooks = {
    { 'ScreenSong.ParseInput',   'usdx_tagger_on_parse_input' },
    { 'ScreenSong.SongSelected', 'usdx_tagger_on_song_selected' },
    { 'Display.Draw',            'usdx_tagger_on_draw' },
  }

  for i = 1, #hooks do
    local hooked, err = adapter.hook(hooks[i][1], hooks[i][2])
    if not hooked then
      adapter.log_error(string.format('cannot hook %s: %s', hooks[i][1], tostring(err)))
      return false
    end
  end

  state.ready = true
  adapter.log_info('ready, tag menu on "' .. tostring(state.cfg.tag_menu_key) .. '"')
  return true
end

return tagger
