-- message catalogues, language resolution, and reading UltraStar's setting

return function(t)
  local i18n = require('tagger.i18n')

  local test, equal, is_nil, is_true = t.test, t.equal, t.is_nil, t.is_true
  local contains = t.contains

  -- Everything drawn goes straight to Usdx.Text.Print, which expects UTF-8
  -- bytes, so a mis-encoded literal would render as mojibake in the game.
  local function utf8_ok(str)
    local i, n = 1, #str
    while i <= n do
      local c = str:byte(i)
      local extra
      if c < 0x80 then extra = 0
      elseif c >= 0xC2 and c <= 0xDF then extra = 1
      elseif c >= 0xE0 and c <= 0xEF then extra = 2
      elseif c >= 0xF0 and c <= 0xF4 then extra = 3
      else return false end

      for k = 1, extra do
        local cc = str:byte(i + k)
        if not cc or cc < 0x80 or cc > 0xBF then return false end
      end
      i = i + extra + 1
    end
    return true
  end

  -- every test restores the default, since the active language is module state
  local function with_language(name, fn)
    local before = i18n.language()
    i18n.set_language(name)
    local ok, err = pcall(fn)
    i18n.set_language(before)
    if not ok then error(err, 0) end
  end

  ----------------------------------------------------------------
  -- interpolation
  ----------------------------------------------------------------

  test('named holes are filled from the variables table', function()
    equal(i18n._interpolate('a {x} b {y}', { x = 1, y = 'two' }), 'a 1 b two')
  end)

  test('a hole may appear more than once', function()
    equal(i18n._interpolate('{x}-{x}', { x = 'q' }), 'q-q')
  end)

  test('holes can be reordered, which is the point of naming them', function()
    equal(i18n._interpolate('{b} then {a}', { a = 'A', b = 'B' }), 'B then A')
  end)

  test('a hole with no value is left visible rather than erased', function()
    equal(i18n._interpolate('x {missing} y', { other = 1 }), 'x {missing} y')
  end)

  test('a template with no holes is returned unchanged', function()
    equal(i18n._interpolate('plain', { x = 1 }), 'plain')
    equal(i18n._interpolate('plain'), 'plain')
  end)

  test('interpolation does not treat values as patterns', function()
    -- a song title containing % would break string.format-style substitution
    equal(i18n._interpolate('{song}', { song = '100% Pure Love' }), '100% Pure Love')
    equal(i18n._interpolate('{tag}', { tag = 'a%1b' }), 'a%1b')
  end)

  ----------------------------------------------------------------
  -- catalogue integrity: the part that catches translation mistakes
  ----------------------------------------------------------------

  test('English defines every key', function()
    is_true(#i18n.keys() > 0, 'key count')
    for _, key in ipairs(i18n.keys()) do
      is_true(i18n.CATALOGUES.English[key] ~= nil, 'English.' .. key)
    end
  end)

  test('no translation invents a key English does not have', function()
    local known = {}
    for _, key in ipairs(i18n.keys()) do
      known[key] = true
    end

    for _, language in ipairs(i18n.languages()) do
      for key in pairs(i18n.CATALOGUES[language]) do
        is_true(known[key], language .. ' has unknown key ' .. tostring(key))
      end
    end
  end)

  test('every translated string uses exactly the holes English uses', function()
    local function holes(template)
      local found = {}
      for name in template:gmatch('{(%w+)}') do
        found[name] = true
      end
      return found
    end

    for _, key in ipairs(i18n.keys()) do
      local want = holes(i18n.CATALOGUES.English[key])

      for _, language in ipairs(i18n.languages()) do
        local template = i18n.CATALOGUES[language][key]
        if template then
          local got = holes(template)
          for name in pairs(want) do
            is_true(got[name], language .. '.' .. key .. ' is missing {' .. name .. '}')
          end
          for name in pairs(got) do
            is_true(want[name], language .. '.' .. key .. ' has extra {' .. name .. '}')
          end
        end
      end
    end
  end)

  test('no catalogue entry is empty or a leftover placeholder', function()
    for _, language in ipairs(i18n.languages()) do
      for key, template in pairs(i18n.CATALOGUES[language]) do
        is_true(type(template) == 'string' and template ~= '',
          language .. '.' .. key .. ' is empty')
        is_true(not template:find('TODO', 1, true),
          language .. '.' .. key .. ' still says TODO')
      end
    end
  end)

  test('English is not the only catalogue', function()
    is_true(#i18n.languages() > 1, 'language count')
    is_true(i18n.CATALOGUES.German ~= nil, 'German')
  end)

  ----------------------------------------------------------------
  -- known()
  ----------------------------------------------------------------

  test('known accepts UltraStar spelling exactly', function()
    equal(i18n.known('German'), 'German')
  end)

  test('known is case-insensitive but returns the canonical name', function()
    equal(i18n.known('german'), 'German')
    equal(i18n.known('GERMAN'), 'German')
  end)

  test('known rejects a language with no catalogue', function()
    is_nil(i18n.known('Klingon'))
    is_nil(i18n.known(''))
    is_nil(i18n.known(nil))
    is_nil(i18n.known(42))
  end)

  ----------------------------------------------------------------
  -- reading UltraStar's config.ini
  ----------------------------------------------------------------

  local CONFIG = table.concat({
    '[Game]',
    'Players=1',
    'Language=German',
    'Tabs=Off',
    '',
    '[Graphics]',
    'Language=ShouldBeIgnored',
  }, '\n')

  test('the language comes out of the [Game] section', function()
    equal(i18n.language_from_config(CONFIG), 'German')
  end)

  test('a Language key in another section is ignored', function()
    local other = '[Graphics]\nLanguage=Polish\n'
    is_nil(i18n.language_from_config(other))
  end)

  test('CRLF line endings are handled', function()
    equal(i18n.language_from_config('[Game]\r\nLanguage=Polish\r\n'), 'Polish')
  end)

  test('whitespace around the value is trimmed', function()
    equal(i18n.language_from_config('[Game]\n  Language  =  Polish  \n'), 'Polish')
  end)

  test('the section name is matched case-insensitively', function()
    equal(i18n.language_from_config('[GAME]\nLanguage=Polish'), 'Polish')
    equal(i18n.language_from_config('[game]\nlanguage=Polish'), 'Polish')
  end)

  test('a missing or empty setting reads as nil, not as an error', function()
    is_nil(i18n.language_from_config('[Game]\nPlayers=1\n'))
    is_nil(i18n.language_from_config('[Game]\nLanguage=\n'))
    is_nil(i18n.language_from_config(''))
    is_nil(i18n.language_from_config(nil))
    is_nil(i18n.language_from_config(false))
  end)

  test('a language with no catalogue still reads out of the file', function()
    -- resolve() decides what to do about it; the reader does not filter
    equal(i18n.language_from_config('[Game]\nLanguage=Icelandic'), 'Icelandic')
  end)

  ----------------------------------------------------------------
  -- resolve()
  ----------------------------------------------------------------

  test('auto follows the game', function()
    local name, why = i18n.resolve('auto', 'German')
    equal(name, 'German')
    equal(why, 'game')
  end)

  test('auto is recognised whatever its case', function()
    equal(i18n.resolve('AUTO', 'German'), 'German')
  end)

  test('an explicit setting wins over the game', function()
    local name, why = i18n.resolve('French', 'German')
    equal(name, 'French')
    equal(why, 'pinned')
  end)

  test('no game language falls back to English', function()
    local name, why = i18n.resolve('auto', nil)
    equal(name, 'English')
    equal(why, 'default')
  end)

  test('a game language with no catalogue falls back to English', function()
    local name, why = i18n.resolve('auto', 'Icelandic')
    equal(name, 'English')
    equal(why, 'default')
  end)

  test('an unknown pin does not override a usable game language', function()
    -- refusing to start over a typo would be worse than following the game
    equal(i18n.resolve('Klingon', 'German'), 'German')
  end)

  ----------------------------------------------------------------
  -- t() and en()
  ----------------------------------------------------------------

  test('t uses the active language', function()
    with_language('German', function()
      equal(i18n.language(), 'German')
      equal(i18n.t('tags_list', { tags = 'bad' }), 'Tags: bad')
      contains(i18n.t('no_song'), 'Kein Song')
    end)
  end)

  test('en stays English whatever is active', function()
    with_language('German', function()
      equal(i18n.en('no_song'), 'No song is selected.')
    end)
  end)

  test('t and en agree when English is active', function()
    with_language('English', function()
      local vars = { tag = 'bad', song = 'A - B' }
      equal(i18n.t('tag_added', vars), i18n.en('tag_added', vars))
    end)
  end)

  test('setting an unknown language falls back to English', function()
    with_language('Klingon', function()
      equal(i18n.language(), 'English')
    end)
  end)

  test('a key missing from a translation falls back per key', function()
    local saved = i18n.CATALOGUES.German.no_tags
    i18n.CATALOGUES.German.no_tags = nil
    with_language('German', function()
      equal(i18n.t('no_tags', { song = 'X' }), 'No tags on X')
      -- the rest of the catalogue still applies
      contains(i18n.t('no_song'), 'Kein Song')
    end)
    i18n.CATALOGUES.German.no_tags = saved
  end)

  test('an unknown key is identifiable rather than nil', function()
    equal(i18n.t('not_a_real_key'), '[not_a_real_key]')
    equal(i18n.en('not_a_real_key'), '[not_a_real_key]')
  end)

  test('every language renders every key without erroring', function()
    local vars = { tag = 'bad', song = 'A - B', tags = 'x, y',
                   file = '.usdx-user-tags.yaml', error = 'boom' }

    for _, language in ipairs(i18n.languages()) do
      with_language(language, function()
        for _, key in ipairs(i18n.keys()) do
          local out = i18n.t(key, vars)
          is_true(type(out) == 'string' and out ~= '', language .. '.' .. key)
          is_true(not out:find('{'), language .. '.' .. key .. ' left a hole: ' .. out)
        end
      end)
    end
  end)

  test('the UTF-8 validator rejects a bad sequence', function()
    -- guards the guard: a validator that accepts everything checks nothing
    is_true(utf8_ok('plain ascii'))
    is_true(utf8_ok('sch' .. string.char(195, 182) .. 'n'))
    equal(utf8_ok('latin-1 ' .. string.char(0xF6)), false, 'lone high byte')
    equal(utf8_ok(string.char(0xC3)), false, 'truncated sequence')
  end)

  test('translated text is valid UTF-8', function()
    for _, language in ipairs(i18n.languages()) do
      for key, template in pairs(i18n.CATALOGUES[language]) do
        is_true(utf8_ok(template), language .. '.' .. key .. ' is not valid UTF-8')
      end
    end
  end)

  ----------------------------------------------------------------
  -- tag labels: translated on screen, canonical on disk
  ----------------------------------------------------------------

  test('a tag is shown translated in the active language', function()
    with_language('German', function()
      equal(i18n.tag('bad'), 'schlecht')
    end)
    with_language('Polish', function()
      equal(i18n.tag('bad'), 'z' .. string.char(197, 130) .. 'y')
    end)
  end)

  test('English shows the canonical name, so the view mirrors the file', function()
    with_language('English', function()
      equal(i18n.tag('bad'), 'bad')
      equal(i18n.tag('bad-audio'), 'bad-audio')
    end)
    is_nil(i18n.TAG_LABELS.English, 'English has no label table')
  end)

  test('a language of false always gives the canonical name', function()
    with_language('German', function()
      equal(i18n.tag('bad', false), 'bad')
    end)
  end)

  test('a tag with no label shows its own name', function()
    with_language('German', function()
      equal(i18n.tag('my-own-tag'), 'my-own-tag')
      equal(i18n.tag('needs-a-re-record'), 'needs-a-re-record')
    end)
  end)

  test('tag() tolerates a non-string', function()
    equal(i18n.tag(nil), 'nil')
    equal(i18n.tag(7), '7')
  end)

  test('a menu entry keeps the canonical name alongside the translation', function()
    with_language('German', function()
      equal(i18n.tag_entry('bad'), 'schlecht (bad)')
    end)
  end)

  test('a menu entry is not doubled up when the two are the same', function()
    with_language('English', function()
      equal(i18n.tag_entry('bad'), 'bad')
    end)
    with_language('German', function()
      equal(i18n.tag_entry('made-up'), 'made-up')
    end)
  end)

  test('every label table belongs to a language with a catalogue', function()
    for language in pairs(i18n.TAG_LABELS) do
      is_true(i18n.CATALOGUES[language] ~= nil,
        'labels for ' .. language .. ' but no messages')
    end
  end)

  test('every label table covers all the suggested tags', function()
    -- a half-labelled menu reads as broken, so partial tables are not allowed
    local config = require('tagger.config')
    for language, labels in pairs(i18n.TAG_LABELS) do
      for _, tag in ipairs(config.SUGGESTED_TAGS) do
        is_true(labels[tag] ~= nil, language .. ' has no label for ' .. tag)
      end
    end
  end)

  test('labels are keyed by a canonical tag name', function()
    -- a key that does not survive normalisation could never be looked up
    local tagset = require('tagger.tagset')
    for language, labels in pairs(i18n.TAG_LABELS) do
      for tag in pairs(labels) do
        equal(tagset.normalize(tag), tag, language .. ' key ' .. tostring(tag))
      end
    end
  end)

  test('labels are non-empty and valid UTF-8', function()
    for language, labels in pairs(i18n.TAG_LABELS) do
      for tag, label in pairs(labels) do
        is_true(type(label) == 'string' and label ~= '',
          language .. '.' .. tag .. ' is empty')
        is_true(utf8_ok(label), language .. '.' .. tag .. ' is not valid UTF-8')
      end
    end
  end)

  test('a message shows the translated tag but logs the canonical one', function()
    with_language('German', function()
      local vars = { tag = 'bad', song = 'A - B' }
      contains(i18n.t('tag_added', vars), 'schlecht', 'screen')
      contains(i18n.en('tag_added', vars), '"bad"', 'log')
      is_true(not i18n.en('tag_added', vars):find('schlecht', 1, true),
        'the log has no translation in it')
    end)
  end)

  test('a tag list is translated for the screen and canonical for the log', function()
    with_language('German', function()
      local vars = { tags = { 'bad', 'review' } }
      equal(i18n.t('tags_list', vars), 'Tags: schlecht, pr' ..
        string.char(195, 188) .. 'fen')
      equal(i18n.en('tags_list', vars), 'Tags: bad, review')
    end)
  end)

  test('an already-labelled list keeps unknown tags as they are', function()
    with_language('German', function()
      equal(i18n.t('tags_list', { tags = { 'bad', 'mine' } }), 'Tags: schlecht, mine')
    end)
  end)

  test('a plain string tags value is still accepted', function()
    -- callers that pre-joined the list should not break
    with_language('German', function()
      equal(i18n.t('tags_list', { tags = 'already, joined' }), 'Tags: already, joined')
    end)
  end)

  test('localising vars does not mutate the caller table', function()
    local vars = { tag = 'bad', tags = { 'bad' } }
    with_language('German', function()
      i18n.t('tag_added', vars)
    end)
    equal(vars.tag, 'bad', 'tag untouched')
    equal(type(vars.tags), 'table', 'tags still a table')
    equal(vars.tags[1], 'bad', 'list untouched')
  end)

  ----------------------------------------------------------------
  -- the config setting
  ----------------------------------------------------------------

  test('config defaults the language to auto', function()
    local config = require('tagger.config')
    equal(config.defaults().language, 'auto')
  end)

  test('config accepts a known language and canonicalises it', function()
    local config = require('tagger.config')
    local path = os.tmpname()
    local fh = assert(io.open(path, 'wb'))
    fh:write('language=german\n')
    fh:close()

    local cfg, warnings = config.load(path)
    equal(cfg.language, 'German')
    equal(#warnings, 0, 'warnings')
    os.remove(path)
  end)

  test('config warns about a language it has no catalogue for', function()
    local config = require('tagger.config')
    local path = os.tmpname()
    local fh = assert(io.open(path, 'wb'))
    fh:write('language=Klingon\n')
    fh:close()

    local cfg, warnings = config.load(path)
    equal(cfg.language, 'auto', 'falls back to the default')
    equal(#warnings, 1, 'warnings')
    contains(warnings[1], 'no translation')
    os.remove(path)
  end)
end
