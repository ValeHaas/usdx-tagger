-- tag name validation, normalisation and set operations

return function(t)
  local tagset = require('tagger.tagset')

  local test, equal, same, is_nil, is_true =
    t.test, t.equal, t.same, t.is_nil, t.is_true

  ----------------------------------------------------------------
  -- normalisation (spec 3.2)
  ----------------------------------------------------------------

  test('normalize lowercases ASCII', function()
    equal(tagset.normalize('Bad-Audio'), 'bad-audio')
    equal(tagset.normalize('REVIEW'), 'review')
  end)

  test('normalize trims surrounding whitespace', function()
    equal(tagset.normalize('  bad-audio  '), 'bad-audio')
    equal(tagset.normalize('\tbad\t'), 'bad')
  end)

  test('normalize collapses internal whitespace', function()
    equal(tagset.normalize('incorrect   lyrics'), 'incorrect lyrics')
  end)

  test('the three spec 3.2 spellings normalise to one tag', function()
    local a = tagset.normalize('Bad-Audio')
    local b = tagset.normalize('bad-audio')
    local c = tagset.normalize(' bad-audio')
    equal(a, b, 'Bad-Audio vs bad-audio')
    equal(b, c, 'bad-audio vs " bad-audio"')
  end)

  test('normalize keeps underscores, digits and spaces', function()
    equal(tagset.normalize('bad_audio'), 'bad_audio')
    equal(tagset.normalize('take 2'), 'take 2')
    equal(tagset.normalize('mp3-320'), 'mp3-320')
  end)

  test('normalize rejects an empty or whitespace-only tag', function()
    is_nil(tagset.normalize(''))
    is_nil(tagset.normalize('   '))
    is_nil((tagset.normalize('\t\t')))
  end)

  test('normalize rejects non-string values', function()
    is_nil(tagset.normalize(nil))
    is_nil(tagset.normalize(42))
    is_nil(tagset.normalize({}))
    is_nil(tagset.normalize(true))
  end)

  test('normalize rejects YAML-unsafe characters', function()
    for _, bad in ipairs({ 'a:b', 'a#b', 'a[b', 'a]b', 'a{b', 'a}b', 'a,b',
                           'a"b', "a'b" }) do
      is_nil(tagset.normalize(bad), 'should reject ' .. bad)
    end
  end)

  test('normalize rejects YAML-significant leading characters', function()
    for _, bad in ipairs({ '-bad', '?bad', '!bad', '&bad', '*bad', '%bad',
                           '@bad', '`bad', '|bad', '>bad' }) do
      is_nil(tagset.normalize(bad), 'should reject ' .. bad)
    end
  end)

  test('normalize rejects control characters', function()
    is_nil(tagset.normalize('bad' .. string.char(7)))
    is_nil(tagset.normalize('bad' .. string.char(0)))
  end)

  test('normalize enforces a length limit', function()
    local long = string.rep('a', tagset.MAX_BYTES)
    equal(tagset.normalize(long), long, 'at the limit')
    is_nil(tagset.normalize(long .. 'a'), 'one over the limit')
  end)

  ----------------------------------------------------------------
  -- Unicode (spec 14)
  ----------------------------------------------------------------

  -- byte escapes rather than \u{...}: that syntax is Lua 5.3+, and these tests
  -- must run on every version the plugin targets
  local U_UUML  = '\195\188'   -- U+00FC small u with diaeresis
  local U_AUML  = '\195\164'   -- U+00E4 small a with diaeresis
  local U_AUMLC = '\195\132'   -- U+00C4 capital A with diaeresis
  local U_CJK   = '\230\151\165\230\156\172\232\170\158'

  test('normalize keeps Unicode tags intact', function()
    equal(tagset.normalize('f' .. U_UUML .. 'r-elise'), 'f' .. U_UUML .. 'r-elise')
    equal(tagset.normalize('  ' .. U_CJK .. '  '), U_CJK)
  end)

  test('normalize case folds ASCII only, leaving Unicode alone', function()
    -- documented limitation: string.lower is not Unicode aware, so these stay
    -- distinct rather than being silently mangled
    equal(tagset.normalize(U_AUMLC .. 'rger'), U_AUMLC .. 'rger')
    is_true(tagset.normalize(U_AUMLC .. 'rger') ~= tagset.normalize(U_AUML .. 'rger'))
  end)

  ----------------------------------------------------------------
  -- set operations (spec 5.3)
  ----------------------------------------------------------------

  test('add appends one tag', function()
    local tags = {}
    local out, changed = tagset.add(tags, 'bad')
    same(out, { 'bad' })
    equal(changed, true, 'changed')
  end)

  test('add appends several tags in order', function()
    local tags = {}
    tagset.add(tags, 'bad-audio')
    tagset.add(tags, 'bad-lyrics')
    tagset.add(tags, 'review')
    same(tags, { 'bad-audio', 'bad-lyrics', 'review' })
  end)

  test('add is idempotent and creates no duplicate', function()
    local tags = { 'bad' }
    local out, changed = tagset.add(tags, 'bad')
    same(out, { 'bad' })
    equal(changed, false, 'changed')
  end)

  test('add treats differing spellings as the same tag', function()
    local tags = {}
    tagset.add(tags, 'Bad-Audio')
    local _, changed = tagset.add(tags, ' bad-audio ')
    same(tags, { 'bad-audio' })
    equal(changed, false, 'changed')
  end)

  test('add preserves the position of existing tags', function()
    local tags = { 'review', 'bad' }
    tagset.add(tags, 'duplicate')
    same(tags, { 'review', 'bad', 'duplicate' })
  end)

  test('add rejects an invalid tag without touching the list', function()
    local tags = { 'bad' }
    local out, err = tagset.add(tags, '')
    is_nil(out)
    is_true(type(err) == 'string' and #err > 0, 'error message')
    same(tags, { 'bad' }, 'list untouched')
  end)

  test('remove drops one tag', function()
    local tags = { 'bad', 'review' }
    local out, changed = tagset.remove(tags, 'bad')
    same(out, { 'review' })
    equal(changed, true, 'changed')
  end)

  test('remove of the final tag empties the list', function()
    local tags = { 'bad' }
    tagset.remove(tags, 'bad')
    same(tags, {})
  end)

  test('remove of an absent tag is a no-op', function()
    local tags = { 'bad' }
    local out, changed = tagset.remove(tags, 'review')
    same(out, { 'bad' })
    equal(changed, false, 'changed')
  end)

  test('has compares normalised forms', function()
    local tags = { 'bad-audio' }
    equal(tagset.has(tags, 'BAD-AUDIO'), true)
    equal(tagset.has(tags, '  bad-audio '), true)
    equal(tagset.has(tags, 'review'), false)
  end)

  ----------------------------------------------------------------
  -- sanitising what was read from disk
  ----------------------------------------------------------------

  test('sanitize normalises, dedupes and reports rejects', function()
    local clean, rejected = tagset.sanitize({ 'Bad', 'bad', '', 'review' })
    same(clean, { 'bad', 'review' })
    equal(#rejected, 2, 'rejected count')
  end)

  test('sanitize drops non-string entries', function()
    -- a hand-edited file could hold "- 42" or a nested map
    local clean, rejected = tagset.sanitize({ 'bad', 42, {}, 'review' })
    same(clean, { 'bad', 'review' })
    equal(#rejected, 2, 'rejected count')
  end)

  test('sanitize of an empty list yields an empty list', function()
    local clean, rejected = tagset.sanitize({})
    same(clean, {})
    equal(#rejected, 0, 'rejected count')
  end)
end
