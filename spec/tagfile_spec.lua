-- reading and writing .ultrastar-tags.yaml

return function(t)
  local tagfile = require('tagger.tagfile')
  local tagset = require('tagger.tagset')

  local test, equal, same, is_nil, is_true, contains =
    t.test, t.equal, t.same, t.is_nil, t.is_true, t.contains

  local LF = string.char(10)
  local CRLF = string.char(13) .. LF

  -- non-ASCII directory and tag names, written as byte escapes so the file
  -- parses on Lua 5.1 as well
  local U_BJORK = 'Bj' .. string.char(195, 182) .. 'rk'   -- Bjoerk
  local U_UUML  = string.char(195, 188)                    -- u with diaeresis

  --- Fresh song directory for one test.
  local function songdir(suffix)
    return t.tmpdir(suffix)
  end

  --- Convenience: load, apply `fn` to the tag list, save.
  local function edit(dir, fn, opts)
    local st = tagfile.load(dir)
    local tags = tagset.sanitize(st.tags)
    fn(tags)
    return tagfile.save(st, tags, opts)
  end

  ----------------------------------------------------------------
  -- creating and reading (spec 14: create, add one, read back)
  ----------------------------------------------------------------

  test('load on a directory with no tag file reports absence, not an error', function()
    local dir = songdir()
    local st = tagfile.load(dir)
    equal(st.present, false, 'present')
    equal(st.supported, true, 'supported')
    same(st.tags, {})
    equal(st.version, 1, 'version defaults to 1')
    t.rmdir(dir)
  end)

  test('saving one tag creates the file with the documented shape', function()
    local dir = songdir()
    local ok, err = edit(dir, function(tags) tagset.add(tags, 'bad') end)
    is_true(ok, 'save ok: ' .. tostring(err))

    local text = t.read_file(tagfile.path_for(dir))
    equal(text,
      '# UltraStar Deluxe song tags' .. LF ..
      'version: 1' .. LF ..
      'tags:' .. LF ..
      '  - bad' .. LF)
    t.rmdir(dir)
  end)

  test('the created file lands in the song directory', function()
    local dir = songdir()
    edit(dir, function(tags) tagset.add(tags, 'bad') end)
    is_true(t.file_exists(dir .. '/.ultrastar-tags.yaml'), 'file in song dir')
    t.rmdir(dir)
  end)

  test('adding several tags writes them all, in order', function()
    local dir = songdir()
    edit(dir, function(tags)
      tagset.add(tags, 'bad-audio')
      tagset.add(tags, 'bad-lyrics')
      tagset.add(tags, 'review')
    end)

    local st = tagfile.load(dir)
    same(st.tags, { 'bad-audio', 'bad-lyrics', 'review' })
    t.rmdir(dir)
  end)

  test('tag order survives a round trip and new tags append', function()
    local dir = songdir()
    edit(dir, function(tags)
      tagset.add(tags, 'review')
      tagset.add(tags, 'bad')
    end)
    edit(dir, function(tags) tagset.add(tags, 'duplicate') end)

    same(tagfile.load(dir).tags, { 'review', 'bad', 'duplicate' })
    t.rmdir(dir)
  end)

  test('adding a duplicate tag creates no second entry', function()
    local dir = songdir()
    edit(dir, function(tags) tagset.add(tags, 'bad') end)
    edit(dir, function(tags) tagset.add(tags, 'BAD') end)

    same(tagfile.load(dir).tags, { 'bad' })
    t.rmdir(dir)
  end)

  test('exists reflects the file', function()
    local dir = songdir()
    equal(tagfile.exists(dir), false, 'before')
    edit(dir, function(tags) tagset.add(tags, 'bad') end)
    equal(tagfile.exists(dir), true, 'after')
    t.rmdir(dir)
  end)

  ----------------------------------------------------------------
  -- removing (spec 14: remove one, remove the last, delete empty)
  ----------------------------------------------------------------

  test('removing one tag leaves the others', function()
    local dir = songdir()
    edit(dir, function(tags)
      tagset.add(tags, 'bad')
      tagset.add(tags, 'review')
    end)
    edit(dir, function(tags) tagset.remove(tags, 'bad') end)

    same(tagfile.load(dir).tags, { 'review' })
    t.rmdir(dir)
  end)

  test('removing the final tag deletes the file by default', function()
    local dir = songdir()
    edit(dir, function(tags) tagset.add(tags, 'bad') end)
    edit(dir, function(tags) tagset.remove(tags, 'bad') end)

    equal(t.file_exists(tagfile.path_for(dir)), false, 'file removed')
    t.rmdir(dir)
  end)

  test('removing the final tag can keep an empty list instead', function()
    local dir = songdir()
    edit(dir, function(tags) tagset.add(tags, 'bad') end)
    edit(dir, function(tags) tagset.remove(tags, 'bad') end,
         { delete_when_empty = false })

    is_true(t.file_exists(tagfile.path_for(dir)), 'file kept')
    contains(t.read_file(tagfile.path_for(dir)), 'tags: []')
    same(tagfile.load(dir).tags, {})
    t.rmdir(dir)
  end)

  test('saving no tags for an untagged song is a harmless no-op', function()
    local dir = songdir()
    local ok = edit(dir, function() end)
    is_true(ok, 'save ok')
    equal(t.file_exists(tagfile.path_for(dir)), false, 'no file created')
    t.rmdir(dir)
  end)

  ----------------------------------------------------------------
  -- accepted input shapes (spec 4.2, 4.4)
  ----------------------------------------------------------------

  test('a minimal file without version is accepted and assumed version 1', function()
    local dir = songdir()
    t.write_file(tagfile.path_for(dir), 'tags:' .. LF .. '  - bad' .. LF)

    local st = tagfile.load(dir)
    equal(st.supported, true, 'supported')
    equal(st.version, 1, 'version')
    same(st.tags, { 'bad' })
    t.rmdir(dir)
  end)

  test('unindented sequence entries are accepted', function()
    local dir = songdir()
    t.write_file(tagfile.path_for(dir),
      'version: 1' .. LF .. 'tags:' .. LF .. '- bad' .. LF .. '- review' .. LF)

    same(tagfile.load(dir).tags, { 'bad', 'review' })
    t.rmdir(dir)
  end)

  test('an explicit empty list is accepted', function()
    local dir = songdir()
    t.write_file(tagfile.path_for(dir), 'version: 1' .. LF .. 'tags: []' .. LF)

    local st = tagfile.load(dir)
    equal(st.supported, true, 'supported')
    same(st.tags, {})
    t.rmdir(dir)
  end)

  test('comments and blank lines do not confuse the reader', function()
    local dir = songdir()
    t.write_file(tagfile.path_for(dir),
      '# hand written' .. LF .. LF .. 'version: 1' .. LF ..
      '# the tags' .. LF .. 'tags:' .. LF .. '  - bad' .. LF)

    same(tagfile.load(dir).tags, { 'bad' })
    t.rmdir(dir)
  end)

  ----------------------------------------------------------------
  -- refused input shapes (spec 8, 12)
  ----------------------------------------------------------------

  local function refuses(name, body, expect_in_error)
    test(name, function()
      local dir = songdir()
      t.write_file(tagfile.path_for(dir), body)

      local st = tagfile.load(dir)
      equal(st.supported, false, 'supported')
      is_true(type(st.err) == 'string' and #st.err > 0, 'error message')
      if expect_in_error then
        contains(st.err, expect_in_error, 'error text')
      end

      -- and it must refuse to write, leaving the file untouched
      local before = t.read_file(tagfile.path_for(dir))
      local ok, err = tagfile.save(st, { 'bad' })
      is_nil(ok, 'save refused')
      is_true(type(err) == 'string', 'save error message')
      equal(t.read_file(tagfile.path_for(dir)), before, 'file untouched')

      t.rmdir(dir)
    end)
  end

  refuses('a scalar tags value is reported as needing a list',
    'version: 1' .. LF .. 'tags: bad' .. LF, 'must be a list')

  refuses('a flow sequence is refused',
    'version: 1' .. LF .. 'tags: [bad, review]' .. LF, 'flow sequence')

  refuses('tabs are refused',
    'version: 1' .. LF .. 'tags:' .. LF .. '\t- bad' .. LF, 'tab')

  refuses('quoted scalars are refused',
    'tags:' .. LF .. '  - "bad"' .. LF, 'quoted')

  refuses('a nested map under tags is refused',
    'tags:' .. LF .. '  - name: bad' .. LF, 'nested map')

  refuses('a duplicate tags key is refused',
    'tags:' .. LF .. '  - bad' .. LF .. 'tags:' .. LF .. '  - review' .. LF,
    'duplicate')

  refuses('a non-numeric version is refused',
    'version: one' .. LF .. 'tags:' .. LF .. '  - bad' .. LF, 'version')

  refuses('a line that is neither key, item nor comment is refused',
    'this is not yaml at all' .. LF, 'unrecognised')

  test('a file with no tags key at all reads as untagged', function()
    local dir = songdir()
    t.write_file(tagfile.path_for(dir), 'version: 1' .. LF)

    local st = tagfile.load(dir)
    equal(st.supported, true, 'supported')
    same(st.tags, {})
    t.rmdir(dir)
  end)

  test('a tags block is appended to a file that lacks one', function()
    local dir = songdir()
    t.write_file(tagfile.path_for(dir),
      'version: 1' .. LF .. 'song:' .. LF .. '  title: Example' .. LF)

    edit(dir, function(tags) tagset.add(tags, 'bad') end)

    local text = t.read_file(tagfile.path_for(dir))
    contains(text, 'title: Example', 'existing content kept')
    contains(text, '  - bad', 'tags appended')
    same(tagfile.load(dir).tags, { 'bad' })
    t.rmdir(dir)
  end)

  ----------------------------------------------------------------
  -- preserving what we do not own (spec 7.2)
  ----------------------------------------------------------------

  test('unknown keys and their nested blocks survive a rewrite', function()
    local dir = songdir()
    t.write_file(tagfile.path_for(dir),
      '# keep me' .. LF ..
      'version: 1' .. LF ..
      'tags:' .. LF ..
      '  - bad' .. LF ..
      'metadata:' .. LF ..
      '  marked_at: "2026-08-20T18:42:00Z"' .. LF ..
      '  source: "somewhere else"' .. LF ..
      'song:' .. LF ..
      '  title: Example Song' .. LF)

    edit(dir, function(tags) tagset.add(tags, 'review') end)

    local text = t.read_file(tagfile.path_for(dir))
    contains(text, '# keep me', 'comment')
    contains(text, 'marked_at: "2026-08-20T18:42:00Z"', 'metadata child')
    contains(text, 'source: "somewhere else"', 'metadata child 2')
    contains(text, 'title: Example Song', 'song child')
    contains(text, '  - bad', 'original tag')
    contains(text, '  - review', 'new tag')
    t.rmdir(dir)
  end)

  test('content after the tags block keeps its position', function()
    local dir = songdir()
    t.write_file(tagfile.path_for(dir),
      'tags:' .. LF .. '  - bad' .. LF .. 'trailing: value' .. LF)

    edit(dir, function(tags) tagset.remove(tags, 'bad') end,
         { delete_when_empty = false })

    local text = t.read_file(tagfile.path_for(dir))
    contains(text, 'trailing: value', 'trailing key kept')
    t.rmdir(dir)
  end)

  test('CRLF line endings are preserved', function()
    local dir = songdir()
    t.write_file(tagfile.path_for(dir),
      'version: 1' .. CRLF .. 'tags:' .. CRLF .. '  - bad' .. CRLF)

    edit(dir, function(tags) tagset.add(tags, 'review') end)

    local text = t.read_file(tagfile.path_for(dir))
    is_true(text:find(CRLF, 1, true) ~= nil, 'still CRLF')
    is_true(text:find('[^' .. string.char(13) .. ']' .. LF) == nil,
      'no bare LF introduced')
    t.rmdir(dir)
  end)

  test('the existing item indentation is reused', function()
    local dir = songdir()
    t.write_file(tagfile.path_for(dir),
      'tags:' .. LF .. '- bad' .. LF)

    edit(dir, function(tags) tagset.add(tags, 'review') end)

    contains(t.read_file(tagfile.path_for(dir)), LF .. '- review', 'no indent added')
    t.rmdir(dir)
  end)

  ----------------------------------------------------------------
  -- Unicode (spec 7.1, 14)
  ----------------------------------------------------------------

  test('a Unicode song directory works', function()
    local dir = songdir(U_BJORK .. ' - Its Oh So Quiet (Test!)')
    local ok, err = edit(dir, function(tags) tagset.add(tags, 'bad') end)
    is_true(ok, 'save ok: ' .. tostring(err))
    same(tagfile.load(dir).tags, { 'bad' })
    t.rmdir(dir)
  end)

  test('Unicode tag values round trip', function()
    local dir = songdir()
    local tag = 'f' .. U_UUML .. 'r-elise'
    edit(dir, function(tags) tagset.add(tags, tag) end)
    same(tagfile.load(dir).tags, { tag })
    t.rmdir(dir)
  end)

  test('a directory path with a trailing separator is handled', function()
    local dir = songdir()
    -- UltraStar hands out paths that already end in a separator
    local st = tagfile.load(dir .. '/')
    equal(st.path, tagfile.path_for(dir), 'same resolved path')
    t.rmdir(dir)
  end)

  ----------------------------------------------------------------
  -- failure paths (spec 12, 14)
  ----------------------------------------------------------------

  test('saving into a missing song directory reports an error', function()
    local dir = songdir()
    t.rmdir(dir) -- gone before we write

    local st = tagfile.load(dir)
    equal(st.present, false, 'present')

    local ok, err = tagfile.save(st, { 'bad' })
    is_nil(ok, 'save failed')
    contains(err, 'temporary file', 'error mentions the temporary file')
  end)

  test('a failed write leaves no tag file behind', function()
    local dir = songdir()
    t.rmdir(dir)

    local st = tagfile.load(dir)
    tagfile.save(st, { 'bad' })
    equal(t.file_exists(tagfile.path_for(dir)), false, 'no file')
  end)

  test('a successful write leaves no temporary file behind', function()
    local dir = songdir()
    edit(dir, function(tags) tagset.add(tags, 'bad') end)
    equal(t.file_exists(tagfile.path_for(dir) .. '.tmp'), false, 'no .tmp')
    t.rmdir(dir)
  end)

  test('removing the last tag of an already absent file is a no-op', function()
    local dir = songdir()
    local st = tagfile.load(dir)
    local ok = tagfile.save(st, {})
    is_true(ok, 'save ok')
    equal(t.file_exists(tagfile.path_for(dir)), false, 'still no file')
    t.rmdir(dir)
  end)

  ----------------------------------------------------------------
  -- concurrent modification
  ----------------------------------------------------------------

  test('a reload sees a change made behind our back', function()
    local dir = songdir()
    edit(dir, function(tags) tagset.add(tags, 'bad') end)

    -- somebody else edits the file
    t.write_file(tagfile.path_for(dir),
      'version: 1' .. LF .. 'tags:' .. LF .. '  - review' .. LF)

    same(tagfile.load(dir).tags, { 'review' }, 'reload sees the new content')
    t.rmdir(dir)
  end)

  test('a save is based on the snapshot it loaded, and does not corrupt', function()
    local dir = songdir()
    edit(dir, function(tags) tagset.add(tags, 'bad') end)

    -- load a snapshot, then let somebody else write
    local st = tagfile.load(dir)
    t.write_file(tagfile.path_for(dir),
      'version: 1' .. LF .. 'tags:' .. LF .. '  - review' .. LF)

    -- writing our snapshot wins, and the result is still a valid file
    local tags = tagset.sanitize(st.tags)
    tagset.add(tags, 'duplicate')
    is_true(tagfile.save(st, tags), 'save ok')

    local reread = tagfile.load(dir)
    equal(reread.supported, true, 'still parseable')
    same(reread.tags, { 'bad', 'duplicate' })
    t.rmdir(dir)
  end)

  ----------------------------------------------------------------
  -- what an external tool sees (spec 13)
  ----------------------------------------------------------------

  test('a tagged file is greppable for the tag', function()
    local dir = songdir()
    edit(dir, function(tags)
      tagset.add(tags, 'bad')
      tagset.add(tags, 'review')
    end)

    local text = t.read_file(tagfile.path_for(dir))
    is_true(text:find(LF .. '  - bad' .. LF, 1, true) ~= nil,
      'a whole-line match for "  - bad" exists')
    t.rmdir(dir)
  end)
end
