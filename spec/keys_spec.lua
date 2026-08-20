-- key binding parsing and matching

return function(t)
  local keys = require('tagger.keys')

  local test, equal, is_nil, is_true = t.test, t.equal, t.is_nil, t.is_true

  local function ev(key, mod, down)
    return { Key = key, Char = 0, Mod = mod or 0, Down = down ~= false }
  end

  ----------------------------------------------------------------
  -- the bitwise helper, which has to work without bit operators
  ----------------------------------------------------------------

  test('band computes a bitwise and', function()
    equal(keys._band(0, 0), 0)
    equal(keys._band(1, 1), 1)
    equal(keys._band(1, 2), 0)
    equal(keys._band(0x0041, 0x0040), 0x0040)
    equal(keys._band(0x0300, keys.KMOD_ALT), 0x0300)
    equal(keys._band(0x1000, keys.KMOD_SHIFT), 0, 'numlock is not shift')
  end)

  ----------------------------------------------------------------
  -- parsing
  ----------------------------------------------------------------

  test('a single letter parses to its lowercase ASCII code', function()
    local b = keys.parse('G')
    equal(b.key, 103, 'SDLK_g')
    equal(b.shift, false, 'shift')
    equal(b.ctrl, false, 'ctrl')
    equal(b.alt, false, 'alt')
  end)

  test('lowercase and uppercase spell the same key', function()
    equal(keys.parse('g').key, keys.parse('G').key)
  end)

  test('digits parse to their ASCII code', function()
    equal(keys.parse('1').key, 49)
  end)

  test('modifier prefixes are recognised', function()
    local b = keys.parse('Shift+G')
    equal(b.key, 103, 'key')
    equal(b.shift, true, 'shift')

    b = keys.parse('Ctrl+T')
    equal(b.key, 116, 'key')
    equal(b.ctrl, true, 'ctrl')

    b = keys.parse('Alt+X')
    equal(b.alt, true, 'alt')
  end)

  test('modifiers are case insensitive and combinable', function()
    local b = keys.parse('ctrl+SHIFT+g')
    equal(b.ctrl, true, 'ctrl')
    equal(b.shift, true, 'shift')
    equal(b.key, 103, 'key')
  end)

  test('control is accepted as a spelling of ctrl', function()
    is_true(keys.parse('Control+G').ctrl, 'ctrl')
  end)

  test('surrounding whitespace is ignored', function()
    equal(keys.parse('  Shift + G ').key, 103)
    is_true(keys.parse('  Shift + G ').shift, 'shift')
  end)

  test('named keys parse', function()
    equal(keys.parse('Space').key, 32)
    equal(keys.parse('Escape').key, 27)
    equal(keys.parse('Return').key, 13)
    equal(keys.parse('F5').key, keys.SCANCODE_MASK + 61)
    equal(keys.parse('Up').key, keys.SCANCODE_MASK + 82)
  end)

  test('invalid bindings are rejected', function()
    is_nil(keys.parse(''))
    is_nil(keys.parse('   '))
    is_nil(keys.parse(nil))
    is_nil(keys.parse(42))
    is_nil(keys.parse('Hyper+G'), 'unknown modifier')
    is_nil(keys.parse('NotAKey'), 'unknown key name')
  end)

  ----------------------------------------------------------------
  -- matching
  ----------------------------------------------------------------

  test('a plain binding matches its key with no modifiers', function()
    local b = keys.parse('G')
    is_true(keys.matches(b, ev(103)), 'g')
    equal(keys.matches(b, ev(104)), false, 'a different key')
  end)

  test('key up never matches', function()
    local b = keys.parse('G')
    equal(keys.matches(b, ev(103, 0, false)), false)
  end)

  test('a plain binding does not fire while shift is held', function()
    -- otherwise "G" and "Shift+G" would both trigger on Shift+G
    local b = keys.parse('G')
    equal(keys.matches(b, ev(103, keys.KMOD_SHIFT)), false)
  end)

  test('a shift binding requires shift', function()
    local b = keys.parse('Shift+G')
    is_true(keys.matches(b, ev(103, 0x0001)), 'left shift')
    is_true(keys.matches(b, ev(103, 0x0002)), 'right shift')
    equal(keys.matches(b, ev(103, 0)), false, 'no modifier')
  end)

  test('a ctrl binding requires ctrl and rejects extra modifiers', function()
    local b = keys.parse('Ctrl+T')
    is_true(keys.matches(b, ev(116, 0x0040)), 'left ctrl')
    equal(keys.matches(b, ev(116, 0x0040 + 0x0001)), false, 'ctrl+shift')
    equal(keys.matches(b, ev(116, 0)), false, 'no modifier')
  end)

  test('shift and ctrl bindings on the same key stay distinct', function()
    local plain = keys.parse('G')
    local shifted = keys.parse('Shift+G')

    is_true(keys.matches(plain, ev(103, 0)), 'plain fires unmodified')
    equal(keys.matches(shifted, ev(103, 0)), false, 'shifted does not')

    is_true(keys.matches(shifted, ev(103, keys.KMOD_SHIFT)), 'shifted fires with shift')
    equal(keys.matches(plain, ev(103, keys.KMOD_SHIFT)), false, 'plain does not')
  end)

  test('lock keys in the modifier mask are ignored', function()
    -- numlock and capslock are reported by SDL but must not block a binding
    local b = keys.parse('G')
    is_true(keys.matches(b, ev(103, 0x1000)), 'numlock')
    is_true(keys.matches(b, ev(103, 0x2000)), 'capslock')
  end)

  test('matching tolerates rubbish input', function()
    equal(keys.matches(nil, ev(103)), false)
    equal(keys.matches(keys.parse('G'), nil), false)
    equal(keys.matches(keys.parse('G'), {}), false)
  end)

  test('a missing Mod field is treated as no modifiers', function()
    equal(keys.matches(keys.parse('G'), { Key = 103, Down = true }), true)
  end)
end
