--[[
  A tiny test runner.

  busted is the usual choice, but the plugin has to run on whatever Lua
  UltraStar was linked against (5.1 through 5.5) and contributors should not
  need luarocks to check their work. This is small enough to read in one go.

  Usage: lua spec/run.lua
]]

local runner = {}

local passed, failed = 0, 0
local failures = {}

--------------------------------------------------------------------------
-- assertions
--------------------------------------------------------------------------

local function fail(msg, level)
  error({ tag = 'assertion', msg = msg }, (level or 2) + 1)
end

local function render(v)
  if type(v) == 'string' then
    return string.format('%q', v)
  end
  if type(v) == 'table' then
    local parts = {}
    for i = 1, #v do
      parts[i] = render(v[i])
    end
    return '{' .. table.concat(parts, ', ') .. '}'
  end
  return tostring(v)
end

runner.render = render

function runner.is_true(v, what)
  if not v then
    fail(string.format('%s: expected truthy, got %s', what or 'value', render(v)))
  end
end

function runner.is_nil(v, what)
  if v ~= nil then
    fail(string.format('%s: expected nil, got %s', what or 'value', render(v)))
  end
end

function runner.equal(got, want, what)
  if got ~= want then
    fail(string.format('%s: expected %s, got %s',
      what or 'value', render(want), render(got)))
  end
end

function runner.same(got, want, what)
  if type(got) ~= 'table' then
    fail(string.format('%s: expected a table, got %s', what or 'value', render(got)))
  end
  if #got ~= #want then
    fail(string.format('%s: expected %s, got %s',
      what or 'list', render(want), render(got)))
  end
  for i = 1, #want do
    if got[i] ~= want[i] then
      fail(string.format('%s: expected %s, got %s',
        what or 'list', render(want), render(got)))
    end
  end
end

--- Asserts that `haystack` contains `needle` literally.
function runner.contains(haystack, needle, what)
  if type(haystack) ~= 'string' or not haystack:find(needle, 1, true) then
    fail(string.format('%s: expected to contain %s, got %s',
      what or 'string', render(needle), render(haystack)))
  end
end

--------------------------------------------------------------------------
-- running
--------------------------------------------------------------------------

function runner.test(name, fn)
  local ok, err = pcall(fn)

  if ok then
    passed = passed + 1
    return
  end

  failed = failed + 1
  local msg
  if type(err) == 'table' and err.tag == 'assertion' then
    msg = err.msg
  else
    msg = 'error: ' .. tostring(err)
  end
  failures[#failures + 1] = { name = name, msg = msg }
  io.write('FAIL  ', name, '\n        ', msg, '\n')
end

function runner.report()
  io.write(string.format('\n%d passed, %d failed\n', passed, failed))
  if failed > 0 then
    io.write('\nfailures:\n')
    for i = 1, #failures do
      io.write(string.format('  %s\n    %s\n', failures[i].name, failures[i].msg))
    end
  end
  return failed == 0
end

--------------------------------------------------------------------------
-- filesystem helpers for tests
--------------------------------------------------------------------------

local BACKSLASH = string.char(92)
local is_windows = package.config:sub(1, 1) == BACKSLASH

runner.is_windows = is_windows

local function quote(path)
  if is_windows then
    return '"' .. path .. '"'
  end
  return "'" .. path:gsub("'", "'" .. BACKSLASH .. "''") .. "'"
end

runner.quote = quote

--- Lua has no mkdir, so tests shell out. The plugin itself never does.
function runner.mkdir(path)
  local cmd
  if is_windows then
    cmd = 'mkdir ' .. quote((path:gsub('/', BACKSLASH))) .. ' 2>nul'
  else
    cmd = 'mkdir -p ' .. quote(path)
  end
  os.execute(cmd)
end

function runner.rmdir(path)
  local cmd
  if is_windows then
    cmd = 'rmdir /s /q ' .. quote((path:gsub('/', BACKSLASH))) .. ' 2>nul'
  else
    cmd = 'rm -rf ' .. quote(path)
  end
  os.execute(cmd)
end

local tmp_counter = 0

--- A fresh directory under the system temp dir. `suffix` may contain Unicode
-- so tests can exercise non-ASCII paths.
function runner.tmpdir(suffix)
  tmp_counter = tmp_counter + 1

  local base = os.getenv('TMPDIR') or os.getenv('TMP') or os.getenv('TEMP') or '/tmp'
  base = base:gsub('[/' .. BACKSLASH .. ']+$', '')

  local path = string.format('%s/usdx-tagger-test-%d-%d%s',
    base, os.time(), tmp_counter, suffix and ('-' .. suffix) or '')

  runner.mkdir(path)
  return path
end

function runner.write_file(path, text)
  local fh = assert(io.open(path, 'wb'))
  fh:write(text)
  fh:close()
end

function runner.read_file(path)
  local fh = io.open(path, 'rb')
  if not fh then
    return nil
  end
  local text = fh:read('*a')
  fh:close()
  return text
end

function runner.file_exists(path)
  local fh = io.open(path, 'rb')
  if fh then
    fh:close()
    return true
  end
  return false
end

return runner
