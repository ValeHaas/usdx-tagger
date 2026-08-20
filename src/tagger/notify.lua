--[[
  notify - transient on-screen messages.

  Messages are queued with an expiry and drawn from the Display.Draw hook, so
  nothing blocks and gameplay is never interrupted. The clock and the drawing
  function are injected, which keeps the queueing logic testable without
  UltraStar Deluxe.

  Portable Lua 5.1 - 5.5.
]]

local notify = {}

local DEFAULT_MS = 2500
local MAX_VISIBLE = 4

-- UltraStar screens are laid out in an 800x600 virtual space
local ORIGIN_X = 20
local ORIGIN_Y = 520
local LINE_HEIGHT = 22
local FONT_SIZE = 18

local state = {
  enabled = true,
  duration_ms = DEFAULT_MS,
  clock = function() return 0 end,
  draw_text = nil,
  queue = {},
}

--- @param opts enabled, duration_ms, clock (-> ms), draw_text (x,y,size,r,g,b,a,text)
function notify.configure(opts)
  opts = opts or {}

  if opts.enabled ~= nil then state.enabled = opts.enabled end
  if opts.duration_ms then state.duration_ms = opts.duration_ms end
  if opts.clock then state.clock = opts.clock end
  if opts.draw_text then state.draw_text = opts.draw_text end

  return notify
end

--- Drops everything queued. Used by tests and on reload.
function notify.reset()
  state.queue = {}
end

local function push(text, colour)
  if not state.enabled or type(text) ~= 'string' or text == '' then
    return
  end

  state.queue[#state.queue + 1] = {
    text = text,
    colour = colour,
    expires_at = state.clock() + state.duration_ms,
  }

  -- never let a stuck queue grow without bound
  while #state.queue > MAX_VISIBLE do
    table.remove(state.queue, 1)
  end
end

--- A confirmation, in white.
function notify.info(text)
  push(text, { 1, 1, 1, 1 })
end

--- A problem, in amber. Deliberately not red: nothing here is fatal.
function notify.warn(text)
  push(text, { 1, 0.75, 0.2, 1 })
end

--- Removes expired messages. Called by draw(), exposed for tests.
function notify.prune()
  local now = state.clock()
  local i = 1
  while i <= #state.queue do
    if state.queue[i].expires_at <= now then
      table.remove(state.queue, i)
    else
      i = i + 1
    end
  end
end

--- Number of messages still visible.
function notify.count()
  notify.prune()
  return #state.queue
end

--- The visible message texts, oldest first.
function notify.visible()
  notify.prune()
  local out = {}
  for i = 1, #state.queue do
    out[i] = state.queue[i].text
  end
  return out
end

--- Draws the queue. Safe to call every frame; does nothing when empty.
function notify.draw()
  notify.prune()

  if #state.queue == 0 or not state.draw_text then
    return
  end

  for i = 1, #state.queue do
    local msg = state.queue[i]
    local c = msg.colour or { 1, 1, 1, 1 }
    -- newest at the bottom, older lines stacked above it
    local y = ORIGIN_Y - (#state.queue - i) * LINE_HEIGHT
    state.draw_text(ORIGIN_X, y, FONT_SIZE, c[1], c[2], c[3], c[4], msg.text)
  end
end

notify.DEFAULT_MS = DEFAULT_MS
notify.MAX_VISIBLE = MAX_VISIBLE
notify._state = state

return notify
