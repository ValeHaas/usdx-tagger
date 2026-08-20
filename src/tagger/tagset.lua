--[[
  tagset - tag name validation, normalisation and set operations.

  Knows nothing about files or about UltraStar Deluxe: it works on plain Lua
  arrays of strings, so it can be tested on its own.

  Portable across Lua 5.1 - 5.5.
]]

local tagset = {}

-- Longest accepted tag, in bytes. Generous for a label, short enough that a
-- corrupt file can not produce an absurd line.
local MAX_BYTES = 64

-- Characters that would stop a tag being writable as a plain YAML scalar.
-- Rejecting them up front means the writer never has to quote anything.
local FORBIDDEN_ANYWHERE = ':#[]{},"\''

-- Characters that carry meaning to YAML at the start of a scalar.
local FORBIDDEN_LEADING = '-?!&*%@`|>'

--- Lowercases A-Z and nothing else.
-- string.lower is locale dependent and would be unpredictable for bytes above
-- 127, so the mapping is done explicitly. Non-ASCII bytes pass through
-- untouched, which means Unicode tags are preserved but not case folded.
local function ascii_lower(s)
  return (s:gsub('[A-Z]', function(c)
    return string.char(c:byte() + 32)
  end))
end

--- Normalises a tag to its stored form.
-- Trims, collapses runs of whitespace to a single space and lowercases ASCII.
-- @return normalised tag, or nil plus an error message
function tagset.normalize(tag)
  if type(tag) ~= 'string' then
    return nil, 'tag must be a string, got ' .. type(tag)
  end

  -- collapse every run of whitespace (including tabs and newlines) to one
  -- space, then trim
  local out = tag:gsub('%s+', ' '):gsub('^ +', ''):gsub(' +$', '')

  if out == '' then
    return nil, 'tag must not be empty'
  end

  out = ascii_lower(out)

  if #out > MAX_BYTES then
    return nil, string.format('tag must be at most %d bytes, got %d', MAX_BYTES, #out)
  end

  -- control characters would break the line oriented file format
  if out:find('%c') then
    return nil, 'tag must not contain control characters'
  end

  local bad = out:find('[' .. FORBIDDEN_ANYWHERE:gsub('(%W)', '%%%1') .. ']')
  if bad then
    return nil, string.format('tag must not contain %q', out:sub(bad, bad))
  end

  local first = out:sub(1, 1)
  if FORBIDDEN_LEADING:find(first, 1, true) then
    return nil, string.format('tag must not start with %q', first)
  end

  return out
end

--- True if the tag can be stored as-is.
function tagset.is_valid(tag)
  local ok = tagset.normalize(tag)
  return ok ~= nil
end

--- Index of a tag within a list, comparing normalised forms. nil if absent.
local function index_of(tags, needle)
  for i = 1, #tags do
    if tags[i] == needle then
      return i
    end
  end
  return nil
end

--- Whether the list already holds the tag.
-- @return boolean, or nil plus an error message if the tag is invalid
function tagset.has(tags, tag)
  local norm, err = tagset.normalize(tag)
  if not norm then
    return nil, err
  end
  return index_of(tags, norm) ~= nil
end

--- Appends a tag unless it is already present.
-- Order is stable: existing entries keep their position and new tags go last.
-- @return the list, and true if it changed. nil plus a message if invalid.
function tagset.add(tags, tag)
  local norm, err = tagset.normalize(tag)
  if not norm then
    return nil, err
  end

  if index_of(tags, norm) then
    return tags, false
  end

  tags[#tags + 1] = norm
  return tags, true
end

--- Removes a tag if present.
-- @return the list, and true if it changed. nil plus a message if invalid.
function tagset.remove(tags, tag)
  local norm, err = tagset.normalize(tag)
  if not norm then
    return nil, err
  end

  local i = index_of(tags, norm)
  if not i then
    return tags, false
  end

  table.remove(tags, i)
  return tags, true
end

--- Normalises a list read from disk, dropping anything unusable.
-- Duplicates collapse to their first occurrence. Returns the clean list plus
-- an array of {value=, reason=} for everything rejected, so a caller can warn
-- about a hand-edited file without refusing to work.
function tagset.sanitize(raw)
  local out, rejected = {}, {}

  for i = 1, #raw do
    local norm, err = tagset.normalize(raw[i])
    if not norm then
      rejected[#rejected + 1] = { value = raw[i], reason = err }
    elseif index_of(out, norm) then
      rejected[#rejected + 1] = { value = raw[i], reason = 'duplicate tag' }
    else
      out[#out + 1] = norm
    end
  end

  return out, rejected
end

tagset.MAX_BYTES = MAX_BYTES

return tagset
