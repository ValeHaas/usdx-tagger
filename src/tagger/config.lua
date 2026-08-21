--[[
  config - plugin settings, stored as key=value lines.

  Lives in the writable user directory, never in the song library. The path is
  passed in rather than discovered, so this module stays testable without
  UltraStar Deluxe.

  Missing file, missing keys and malformed values are all non-fatal: the
  affected setting falls back to its default and a warning is collected.
  Unknown keys are preserved on save, so a newer plugin version's settings
  survive being loaded by an older one.

  Portable Lua 5.1 - 5.5.
]]

local config = {}

config.FILENAME = 'usdx-tagger.ini'

-- Every setting, its default, and how to read it. Keeping the type here means
-- load() can validate without a separate schema.
local SETTINGS = {
  { key = 'enabled',               default = true,     kind = 'boolean' },
  { key = 'quick_tag',             default = 'bad',    kind = 'tag' },
  { key = 'tag_menu_key',          default = 'T',      kind = 'key' },
  { key = 'show_tags_key',         default = 'Ctrl+T', kind = 'key' },
  { key = 'show_notifications',    default = true,     kind = 'boolean' },
  { key = 'show_existing_tags',    default = true,     kind = 'boolean' },
  { key = 'delete_empty_tag_file', default = true,     kind = 'boolean' },
  { key = 'notification_ms',       default = 2500,     kind = 'number' },
  { key = 'language',              default = 'auto',   kind = 'language' },
}

config.SETTINGS = SETTINGS

--- Tags offered in the tag menu, in order. Purely a convenience list: any tag
-- name is accepted, and this list is not part of the file format.
config.SUGGESTED_TAGS = {
  'good',
  'duplicate',
  'bad-audio',
  'bad-video',
  'bad-lyrics',
  'bad-timing',
  'bad-notes',
  'bad',
}

--- A fresh table of defaults.
function config.defaults()
  local out = {}
  for i = 1, #SETTINGS do
    out[SETTINGS[i].key] = SETTINGS[i].default
  end
  return out
end

local function find_setting(key)
  for i = 1, #SETTINGS do
    if SETTINGS[i].key == key then
      return SETTINGS[i]
    end
  end
  return nil
end

--------------------------------------------------------------------------
-- parsing
--------------------------------------------------------------------------

local function parse_boolean(value)
  local v = value:lower()
  if v == 'true' or v == '1' or v == 'yes' or v == 'on' then
    return true
  end
  if v == 'false' or v == '0' or v == 'no' or v == 'off' then
    return false
  end
  return nil
end

--- Coerces a raw string to the declared kind.
-- Key bindings and tag names are validated by their own modules, so a bad
-- value is caught here rather than at the moment the user presses something.
local function coerce(setting, raw)
  if setting.kind == 'boolean' then
    local v = parse_boolean(raw)
    if v == nil then
      return nil, string.format('%s: expected true or false, got %q', setting.key, raw)
    end
    return v
  end

  if setting.kind == 'number' then
    local n = tonumber(raw)
    if not n then
      return nil, string.format('%s: expected a number, got %q', setting.key, raw)
    end
    return n
  end

  if setting.kind == 'key' then
    local keys = require('tagger.keys')
    local ok, err = keys.parse(raw)
    if not ok then
      return nil, string.format('%s: %s', setting.key, err)
    end
    return raw
  end

  if setting.kind == 'language' then
    if raw:lower() == 'auto' then
      return 'auto'
    end
    local i18n = require('tagger.i18n')
    local known = i18n.known(raw)
    if not known then
      -- pinning to a language with no catalogue would silently show English,
      -- which looks like the setting was ignored. Say so instead.
      return nil, string.format('%s: no translation for %q, known: %s',
        setting.key, raw, table.concat(i18n.languages(), ', '))
    end
    return known
  end

  if setting.kind == 'tag' then
    local tagset = require('tagger.tagset')
    local norm, err = tagset.normalize(raw)
    if not norm then
      return nil, string.format('%s: %s', setting.key, err)
    end
    return norm
  end

  return raw
end

--- Reads settings from `path`.
-- @return settings table (always complete), array of warning strings,
--         and the table of unknown key/value pairs that were preserved
function config.load(path)
  local cfg = config.defaults()
  local warnings, unknown = {}, {}

  local fh = io.open(path, 'rb')
  if not fh then
    -- no file yet: defaults are correct, and this is not worth warning about
    return cfg, warnings, unknown
  end

  local text = fh:read('*a') or ''
  fh:close()

  local lineno = 0
  for line in (text:gsub('\r\n', '\n') .. '\n'):gmatch('([^\n]*)\n') do
    lineno = lineno + 1

    if line:match('^%s*$') or line:match('^%s*[#;]') then
      -- blank or comment
    else
      local key, raw = line:match('^%s*([%w_%-]+)%s*=%s*(.-)%s*$')
      if not key then
        warnings[#warnings + 1] = string.format('line %d: ignoring %q', lineno, line)
      else
        key = key:lower()
        local setting = find_setting(key)
        if not setting then
          unknown[key] = raw
        else
          local value, err = coerce(setting, raw)
          if err then
            warnings[#warnings + 1] = string.format('line %d: %s (using default)', lineno, err)
          else
            cfg[key] = value
          end
        end
      end
    end
  end

  return cfg, warnings, unknown
end

--------------------------------------------------------------------------
-- writing
--------------------------------------------------------------------------

local function serialize(cfg, unknown)
  local out = {
    '# usdx-tagger settings',
    '# key bindings accept modifiers, for example: G, Shift+G, Ctrl+T',
    '# language is auto (follow UltraStar) or one of: '
      .. table.concat(require('tagger.i18n').languages(), ', '),
    '',
  }

  for i = 1, #SETTINGS do
    local key = SETTINGS[i].key
    local value = cfg[key]
    if value == nil then
      value = SETTINGS[i].default
    end
    out[#out + 1] = key .. '=' .. tostring(value)
  end

  if unknown and next(unknown) then
    -- keep settings we did not recognise so a downgrade does not lose them
    local names = {}
    for key in pairs(unknown) do
      names[#names + 1] = key
    end
    table.sort(names)

    out[#out + 1] = ''
    out[#out + 1] = '# settings this version does not know about, kept as-is'
    for i = 1, #names do
      out[#out + 1] = names[i] .. '=' .. tostring(unknown[names[i]])
    end
  end

  return table.concat(out, '\n') .. '\n'
end

config._serialize = serialize

--- Writes settings to `path`. Uses the same temporary-file dance as the tag
-- file, so an interrupted write cannot leave a half-written config behind.
function config.save(path, cfg, unknown)
  local tagfile = require('tagger.tagfile')
  return tagfile._atomic_write(path, serialize(cfg, unknown))
end

--- Full path of the config file inside a user directory.
function config.path_in(dir)
  local tagfile = require('tagger.tagfile')
  return tagfile.join(dir, config.FILENAME)
end

return config
