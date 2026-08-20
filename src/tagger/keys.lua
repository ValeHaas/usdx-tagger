--[[
  keys - parses key bindings from configuration and matches them against the
  events delivered by the ScreenSong.ParseInput hook.

  The hook hands over a table:
    Key   - the SDL keycode. Letters and digits are their ASCII codes
            (SDLK_a = 97), other keys carry SDLK_SCANCODE_MASK.
    Char  - the unicode code point, or 0. UltraStar reports 0 for plain key
            presses, so bindings are matched on Key, never on Char.
    Mod   - active shift/ctrl/alt modifiers as an SDL KMOD_* mask.
    Down  - true for key down.

  Knows nothing about files or about the tag format. Portable Lua 5.1 - 5.5.
]]

local keys = {}

-- from src/lib/SDL2/sdlscancode.inc
local KMOD_LSHIFT = 0x0001
local KMOD_RSHIFT = 0x0002
local KMOD_LCTRL  = 0x0040
local KMOD_RCTRL  = 0x0080
local KMOD_LALT   = 0x0100
local KMOD_RALT   = 0x0200

local SCANCODE_MASK = 1073741824 -- 1 << 30

keys.KMOD_SHIFT = KMOD_LSHIFT + KMOD_RSHIFT
keys.KMOD_CTRL  = KMOD_LCTRL + KMOD_RCTRL
keys.KMOD_ALT   = KMOD_LALT + KMOD_RALT

-- Named keys the user may bind. Values follow SDL: printable keys are their
-- ASCII code, the rest are a scancode with the mask applied.
local NAMED = {
  space     = 32,
  escape    = 27,
  ['return'] = 13,
  enter     = 13,
  tab       = 9,
  backspace = 8,
  delete    = SCANCODE_MASK + 76,
  insert    = SCANCODE_MASK + 73,
  home      = SCANCODE_MASK + 74,
  ['end']   = SCANCODE_MASK + 77,
  pageup    = SCANCODE_MASK + 75,
  pagedown  = SCANCODE_MASK + 78,
  right     = SCANCODE_MASK + 79,
  left      = SCANCODE_MASK + 80,
  down      = SCANCODE_MASK + 81,
  up        = SCANCODE_MASK + 82,
}

for i = 1, 12 do
  NAMED['f' .. i] = SCANCODE_MASK + 57 + (i - 1)
end

--- Bitwise AND, spelled without operators so this loads on Lua 5.1 too
-- (5.1/5.2 have no bit operators, 5.3+ would reject bit32).
local function band(a, b)
  local result, bit = 0, 1
  while a > 0 and b > 0 do
    local abit, bbit = a % 2, b % 2
    if abit == 1 and bbit == 1 then
      result = result + bit
    end
    a, b, bit = (a - abit) / 2, (b - bbit) / 2, bit * 2
  end
  return result
end

keys._band = band

--- Parses a binding such as "G", "Shift+G", "Ctrl+T" or "F5".
-- @return a binding table {key=, shift=, ctrl=, alt=, label=}, or nil + error
function keys.parse(spec)
  if type(spec) ~= 'string' then
    return nil, 'key binding must be a string, got ' .. type(spec)
  end

  local binding = { shift = false, ctrl = false, alt = false, label = spec }
  local rest = spec:gsub('%s', '')

  if rest == '' then
    return nil, 'key binding must not be empty'
  end

  -- strip modifier prefixes
  while true do
    local mod, tail = rest:match('^(%a+)%+(.+)$')
    if not mod then
      break
    end

    mod = mod:lower()
    if mod == 'shift' then
      binding.shift = true
    elseif mod == 'ctrl' or mod == 'control' then
      binding.ctrl = true
    elseif mod == 'alt' then
      binding.alt = true
    else
      return nil, 'unknown modifier "' .. mod .. '" in "' .. spec .. '"'
    end

    rest = tail
  end

  local lowered = rest:lower()

  if NAMED[lowered] then
    binding.key = NAMED[lowered]
  elseif #rest == 1 then
    local code = lowered:byte()
    -- letters, digits and the handful of printable ASCII keys share their code
    if code < 32 or code > 126 then
      return nil, 'unsupported key "' .. rest .. '"'
    end
    binding.key = code
  else
    return nil, 'unknown key "' .. rest .. '" in "' .. spec .. '"'
  end

  return binding
end

--- True when `event` (from the hook) triggers `binding`.
-- Only key-down events match, and the modifier state must agree exactly, so
-- "G" does not fire while shift is held and "Shift+G" does not fire without.
function keys.matches(binding, event)
  if type(binding) ~= 'table' or type(event) ~= 'table' then
    return false
  end
  if event.Down ~= true then
    return false
  end
  if event.Key ~= binding.key then
    return false
  end

  local mod = event.Mod or 0

  local shift = band(mod, keys.KMOD_SHIFT) ~= 0
  local ctrl  = band(mod, keys.KMOD_CTRL) ~= 0
  local alt   = band(mod, keys.KMOD_ALT) ~= 0

  return shift == binding.shift
     and ctrl == binding.ctrl
     and alt == binding.alt
end

keys.NAMED = NAMED
keys.SCANCODE_MASK = SCANCODE_MASK

return keys
