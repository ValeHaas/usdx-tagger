--[[
  tagfile - reads and writes .ultrastar-tags.yaml.

  Lua ships no YAML parser, so this handles a deliberately narrow subset: the
  shape this module itself emits, which is also the shape docs/FORMAT.md
  specifies. Anything richer is reported as unsupported and the file is left
  strictly alone rather than rewritten into something lossy.

  Recognised:
    blank lines, "#" comments, top-level "key: value" scalars at zero indent,
    and "- item" sequence entries.

  Refused (the file becomes read-only to us):
    flow sequences, nested maps under tags, quoted or multi-line scalars, tabs.

  Every line this module does not claim is preserved verbatim and in order, so
  unknown keys such as "metadata:" or "song:" survive a rewrite untouched.

  Knows nothing about UltraStar Deluxe. Portable across Lua 5.1 - 5.5.
]]

local tagfile = {}

tagfile.FILENAME = '.ultrastar-tags.yaml'
tagfile.VERSION = 1

local HEADER = '# UltraStar Deluxe song tags'
local ITEM_INDENT = '  '

local BACKSLASH = string.char(92)

--------------------------------------------------------------------------
-- paths
--------------------------------------------------------------------------

--- Joins a directory and a name, tolerating a trailing separator on the
-- directory (UltraStar hands out paths that already end in one).
function tagfile.join(dir, name)
  local sep = dir:find(BACKSLASH, 1, true) and BACKSLASH or '/'
  local base = dir:gsub('[/' .. BACKSLASH .. ']+$', '')
  return base .. sep .. name
end

--- Absolute path of the tag file for a song directory.
function tagfile.path_for(dir)
  return tagfile.join(dir, tagfile.FILENAME)
end

--------------------------------------------------------------------------
-- reading
--------------------------------------------------------------------------

local CR = string.char(13)
local LF = string.char(10)
local CRLF = CR .. LF

local function split_lines(text)
  -- keep the terminator style of the file we are editing
  local crlf = text:find(CRLF, 1, true) ~= nil
  local lines = {}

  text = text:gsub(CRLF, LF)
  for line in (text .. LF):gmatch('([^' .. LF .. ']*)' .. LF) do
    lines[#lines + 1] = line
  end
  -- a trailing newline produces one empty entry we do not want
  if #lines > 0 and lines[#lines] == '' then
    table.remove(lines)
  end

  return lines, crlf
end

--- Reads and parses the tag file in `dir`. Always returns a table:
--   present   - false when there is no file (tags is empty, we may create one)
--   supported - false when the file exists but uses YAML we refuse to rewrite
--   err       - why it is unsupported
--   tags      - raw tag strings, in file order
--   lines     - every raw line, for verbatim preservation
function tagfile.load(dir)
  local path = tagfile.path_for(dir)

  local fh, ioerr = io.open(path, 'rb')
  if not fh then
    -- no file is the normal case for an untagged song, not an error
    return {
      path = path, present = false, supported = true,
      version = tagfile.VERSION, tags = {}, lines = {}, crlf = false,
      io_error = ioerr,
    }
  end

  local text = fh:read('*a')
  fh:close()

  if not text then
    return { path = path, present = true, supported = false,
             err = 'could not read file', tags = {}, lines = {} }
  end

  local lines, crlf = split_lines(text)
  local st = {
    path = path, present = true, supported = true,
    version = nil, tags = {}, lines = lines, crlf = crlf,
    tags_start = nil, tags_end = nil, indent = ITEM_INDENT,
  }

  local function refuse(i, why)
    st.supported = false
    st.err = string.format('%s:%d: %s', tagfile.FILENAME, i, why)
    return st
  end

  local current_key = nil

  for i = 1, #lines do
    local line = lines[i]

    if line:find('\t', 1, true) then
      return refuse(i, 'tabs are not supported')
    end

    if line:match('^%s*$') or line:match('^%s*#') then
      -- blank or comment: preserved, and does not change the current key
    else
      local item_indent, item = line:match('^(%s*)%-%s+(.*)$')
      if not item then
        -- "-" alone, which YAML reads as an empty entry
        item_indent = line:match('^(%s*)%-%s*$')
        if item_indent then item = '' end
      end

      if item then
        if current_key == 'tags' then
          local first = item:sub(1, 1)
          if first == '"' or first == "'" then
            return refuse(i, 'quoted scalars are not supported')
          end
          if item:find('#', 1, true) then
            return refuse(i, 'inline comments in tag entries are not supported')
          end
          if item:find(':', 1, true) then
            return refuse(i, 'nested maps under tags are not supported')
          end
          st.tags[#st.tags + 1] = (item:gsub('%s+$', ''))
          st.tags_end = i
          st.indent = item_indent
        end
        -- items under any other key are opaque and simply preserved
      else
        local key, value = line:match('^([%w_%-]+):%s*(.-)%s*$')

        if key then
          current_key = key:lower()

          if current_key == 'tags' then
            if st.tags_start then
              return refuse(i, 'duplicate "tags" key')
            end
            st.tags_start = i
            st.tags_end = i

            if value ~= '' then
              if value == '[]' then
                -- explicit empty list, nothing to collect
              elseif value:sub(1, 1) == '[' then
                return refuse(i, 'flow sequences are not supported')
              else
                return refuse(i, 'tags must be a list, got a plain scalar')
              end
            end

          elseif current_key == 'version' then
            local n = tonumber(value)
            if value ~= '' and not n then
              return refuse(i, 'version must be a number')
            end
            st.version = n
          end

        elseif line:match('^%s+') then
          -- an indented line under some unknown key: opaque, preserved
        else
          return refuse(i, 'unrecognised line')
        end
      end
    end
  end

  -- an absent version means version 1
  st.version = st.version or tagfile.VERSION

  return st
end

--- Whether a tag file exists for this song directory.
function tagfile.exists(dir)
  local fh = io.open(tagfile.path_for(dir), 'rb')
  if fh then
    fh:close()
    return true
  end
  return false
end

--------------------------------------------------------------------------
-- writing
--------------------------------------------------------------------------

local function render_tags_block(tags, indent)
  if #tags == 0 then
    return { 'tags: []' }
  end

  local out = { 'tags:' }
  for i = 1, #tags do
    out[#out + 1] = indent .. '- ' .. tags[i]
  end
  return out
end

--- Builds the full text to write, preserving everything we did not claim.
local function render(st, tags)
  local nl = st.crlf and CRLF or LF
  local block = render_tags_block(tags, st.indent or ITEM_INDENT)
  local out = {}

  if not st.present or #st.lines == 0 then
    -- a fresh file
    out[#out + 1] = HEADER
    out[#out + 1] = 'version: ' .. tostring(st.version or tagfile.VERSION)
    for i = 1, #block do out[#out + 1] = block[i] end

  elseif st.tags_start then
    -- splice the new block over the old one, keeping the rest verbatim
    for i = 1, st.tags_start - 1 do out[#out + 1] = st.lines[i] end
    for i = 1, #block do out[#out + 1] = block[i] end
    for i = st.tags_end + 1, #st.lines do out[#out + 1] = st.lines[i] end

  else
    -- an existing file with no tags key: append one
    for i = 1, #st.lines do out[#out + 1] = st.lines[i] end
    for i = 1, #block do out[#out + 1] = block[i] end
  end

  return table.concat(out, nl) .. nl
end

--- Writes `text` to `path` as atomically as the platform allows.
-- A temporary file in the same directory is flushed and closed first, then
-- moved into place. POSIX rename replaces atomically; Windows rename fails
-- when the target exists, so the original is removed first, leaving a brief
-- window in which neither name resolves. The temporary file is deliberately
-- left behind on a write failure so nothing is lost.
local function atomic_write(path, text)
  local tmp = path .. '.tmp'

  local fh, err = io.open(tmp, 'wb')
  if not fh then
    return nil, 'cannot create temporary file: ' .. tostring(err)
  end

  local ok, werr = fh:write(text)
  if ok then
    ok, werr = fh:flush()
  end
  fh:close()

  if not ok then
    os.remove(tmp)
    return nil, 'cannot write temporary file: ' .. tostring(werr)
  end

  local moved, moveerr = os.rename(tmp, path)
  if not moved then
    -- Windows: the destination must not exist
    os.remove(path)
    moved, moveerr = os.rename(tmp, path)
  end

  if not moved then
    return nil, 'cannot replace tag file: ' .. tostring(moveerr)
  end

  return true
end

--- Persists `tags` for the song directory described by `st` (from load()).
-- opts.delete_when_empty (default true) removes the file rather than leaving
-- an empty list behind, which keeps filesystem searches meaningful.
-- @return true, or nil plus an error message
function tagfile.save(st, tags, opts)
  opts = opts or {}

  local delete_when_empty = opts.delete_when_empty
  if delete_when_empty == nil then
    delete_when_empty = true
  end

  if st.present and not st.supported then
    return nil, 'refusing to overwrite: ' .. tostring(st.err)
  end

  if #tags == 0 and delete_when_empty then
    if not st.present then
      return true -- nothing to do
    end
    local ok, err = os.remove(st.path)
    if not ok then
      return nil, 'cannot delete tag file: ' .. tostring(err)
    end
    return true
  end

  return atomic_write(st.path, render(st, tags))
end

tagfile._render = render
tagfile._atomic_write = atomic_write

return tagfile
