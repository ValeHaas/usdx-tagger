--[[
  i18n - the plugin's own message catalogues.

  UltraStar Deluxe is translated into 29 languages and reports which one is
  active (see docs/i18n.md). This module holds our strings for the same set of
  language names, so the plugin can follow that setting.

  Catalogues are keyed by UltraStar's own language name - `German`, `Russian` -
  because that is exactly what the game writes into config.ini. They are not
  locale codes and there is no region or fallback chain to interpret.

  Two rules that matter more than they look:

  * Placeholders are named, `{tag}` and `{song}`, not positional. Lua's
    string.format has no `%1$s`, so a language that needs the song before the
    tag would be stuck with English word order. Named holes let each
    translation put them wherever the language wants them, or leave one out.

  * Only the interface is translated. Tag names, and the keys inside the tag
    file, are payload: they get searched for with grep and they travel between
    machines, so `bad` stays `bad` in every language. See docs/i18n.md.

  Log messages also stay English on purpose - they end up in bug reports - so
  every string exists in two forms: t() in the user's language, en() always in
  English.

  Translation status: English is the source. German, French, Spanish, Italian,
  Dutch, Portuguese, Polish, Russian and Swedish are written but have not been
  reviewed by a native speaker. Adding a language is a data-only change; the
  renderer already handles every script UltraStar ships a font for, Cyrillic,
  Greek and CJK included.

  Portable Lua 5.1 - 5.5.
]]

local i18n = {}

i18n.DEFAULT = 'English'

-- the active language. Declared up here so every function below closes over
-- it; when this sat further down, i18n.tag() saw a nil global instead.
local current = i18n.DEFAULT

--------------------------------------------------------------------------
-- catalogues
--------------------------------------------------------------------------

local CATALOGUES = {}

CATALOGUES.English = {
  no_song         = 'No song is selected.',
  read_failed     = 'Cannot read {file}: the file is not valid.',
  save_failed     = 'Cannot save tags: {error}',
  bad_tag         = 'Not a usable tag name: {error}',
  tag_added       = 'Added tag "{tag}" to {song}',
  tag_removed     = 'Removed tag "{tag}" from {song}',
  tag_already_set = 'Tag "{tag}" is already set on {song}',
  tag_not_set     = 'Tag "{tag}" was not set on {song}',
  no_tags         = 'No tags on {song}',
  tags_list       = 'Tags: {tags}',
  menu_title      = 'Tags  (up/down, Enter toggles, Esc closes)',
}

CATALOGUES.German = {
  no_song         = 'Kein Song ausgewählt.',
  read_failed     = '{file} kann nicht gelesen werden: Datei ist ungültig.',
  save_failed     = 'Tags können nicht gespeichert werden: {error}',
  bad_tag         = 'Kein gültiger Tag-Name: {error}',
  tag_added       = 'Tag "{tag}" zu {song} hinzugefügt',
  tag_removed     = 'Tag "{tag}" von {song} entfernt',
  tag_already_set = 'Tag "{tag}" ist bei {song} bereits gesetzt',
  tag_not_set     = 'Tag "{tag}" war bei {song} nicht gesetzt',
  no_tags         = 'Keine Tags bei {song}',
  tags_list       = 'Tags: {tags}',
  menu_title      = 'Tags  (auf/ab, Enter schaltet um, Esc schließt)',
}

CATALOGUES.French = {
  no_song         = 'Aucune chanson sélectionnée.',
  read_failed     = 'Lecture de {file} impossible : fichier invalide.',
  save_failed     = 'Enregistrement des tags impossible : {error}',
  bad_tag         = 'Nom de tag invalide : {error}',
  tag_added       = 'Tag « {tag} » ajouté à {song}',
  tag_removed     = 'Tag « {tag} » retiré de {song}',
  tag_already_set = 'Le tag « {tag} » est déjà présent sur {song}',
  tag_not_set     = 'Le tag « {tag} » n\'était pas présent sur {song}',
  no_tags         = 'Aucun tag sur {song}',
  tags_list       = 'Tags : {tags}',
  menu_title      = 'Tags  (haut/bas, Entrée pour basculer, Échap pour fermer)',
}

CATALOGUES.Spanish = {
  no_song         = 'No hay ninguna canción seleccionada.',
  read_failed     = 'No se puede leer {file}: el archivo no es válido.',
  save_failed     = 'No se pueden guardar las etiquetas: {error}',
  bad_tag         = 'Nombre de etiqueta no válido: {error}',
  tag_added       = 'Etiqueta «{tag}» añadida a {song}',
  tag_removed     = 'Etiqueta «{tag}» eliminada de {song}',
  tag_already_set = 'La etiqueta «{tag}» ya está en {song}',
  tag_not_set     = 'La etiqueta «{tag}» no estaba en {song}',
  no_tags         = 'Sin etiquetas en {song}',
  tags_list       = 'Etiquetas: {tags}',
  menu_title      = 'Etiquetas  (arriba/abajo, Enter alterna, Esc cierra)',
}

CATALOGUES.Italian = {
  no_song         = 'Nessun brano selezionato.',
  read_failed     = 'Impossibile leggere {file}: file non valido.',
  save_failed     = 'Impossibile salvare i tag: {error}',
  bad_tag         = 'Nome tag non valido: {error}',
  tag_added       = 'Tag "{tag}" aggiunto a {song}',
  tag_removed     = 'Tag "{tag}" rimosso da {song}',
  tag_already_set = 'Il tag "{tag}" è già presente su {song}',
  tag_not_set     = 'Il tag "{tag}" non era presente su {song}',
  no_tags         = 'Nessun tag su {song}',
  tags_list       = 'Tag: {tags}',
  menu_title      = 'Tag  (su/giù, Invio per attivare, Esc per chiudere)',
}

CATALOGUES.Dutch = {
  no_song         = 'Geen nummer geselecteerd.',
  read_failed     = 'Kan {file} niet lezen: bestand is ongeldig.',
  save_failed     = 'Kan tags niet opslaan: {error}',
  bad_tag         = 'Ongeldige tagnaam: {error}',
  tag_added       = 'Tag "{tag}" toegevoegd aan {song}',
  tag_removed     = 'Tag "{tag}" verwijderd van {song}',
  tag_already_set = 'Tag "{tag}" staat al op {song}',
  tag_not_set     = 'Tag "{tag}" stond niet op {song}',
  no_tags         = 'Geen tags op {song}',
  tags_list       = 'Tags: {tags}',
  menu_title      = 'Tags  (omhoog/omlaag, Enter wisselt, Esc sluit)',
}

CATALOGUES.Portuguese = {
  no_song         = 'Nenhuma música selecionada.',
  read_failed     = 'Não é possível ler {file}: ficheiro inválido.',
  save_failed     = 'Não é possível guardar as etiquetas: {error}',
  bad_tag         = 'Nome de etiqueta inválido: {error}',
  tag_added       = 'Etiqueta "{tag}" adicionada a {song}',
  tag_removed     = 'Etiqueta "{tag}" removida de {song}',
  tag_already_set = 'A etiqueta "{tag}" já está em {song}',
  tag_not_set     = 'A etiqueta "{tag}" não estava em {song}',
  no_tags         = 'Sem etiquetas em {song}',
  tags_list       = 'Etiquetas: {tags}',
  menu_title      = 'Etiquetas  (cima/baixo, Enter alterna, Esc fecha)',
}

CATALOGUES.Polish = {
  no_song         = 'Nie wybrano utworu.',
  read_failed     = 'Nie można odczytać {file}: plik jest nieprawidłowy.',
  save_failed     = 'Nie można zapisać tagów: {error}',
  bad_tag         = 'Nieprawidłowa nazwa tagu: {error}',
  tag_added       = 'Dodano tag "{tag}" do {song}',
  tag_removed     = 'Usunięto tag "{tag}" z {song}',
  tag_already_set = 'Tag "{tag}" jest już ustawiony dla {song}',
  tag_not_set     = 'Tag "{tag}" nie był ustawiony dla {song}',
  no_tags         = 'Brak tagów dla {song}',
  tags_list       = 'Tagi: {tags}',
  menu_title      = 'Tagi  (góra/dół, Enter przełącza, Esc zamyka)',
}

CATALOGUES.Russian = {
  no_song         = 'Песня не выбрана.',
  read_failed     = 'Не удалось прочитать {file}: файл повреждён.',
  save_failed     = 'Не удалось сохранить теги: {error}',
  bad_tag         = 'Недопустимое имя тега: {error}',
  tag_added       = 'Тег «{tag}» добавлен к {song}',
  tag_removed     = 'Тег «{tag}» удалён у {song}',
  tag_already_set = 'Тег «{tag}» уже стоит у {song}',
  tag_not_set     = 'Тега «{tag}» не было у {song}',
  no_tags         = 'Нет тегов у {song}',
  tags_list       = 'Теги: {tags}',
  menu_title      = 'Теги  (вверх/вниз, Enter переключает, Esc закрывает)',
}

CATALOGUES.Swedish = {
  no_song         = 'Ingen låt är vald.',
  read_failed     = 'Kan inte läsa {file}: filen är ogiltig.',
  save_failed     = 'Kan inte spara taggar: {error}',
  bad_tag         = 'Ogiltigt taggnamn: {error}',
  tag_added       = 'Taggen "{tag}" lades till på {song}',
  tag_removed     = 'Taggen "{tag}" togs bort från {song}',
  tag_already_set = 'Taggen "{tag}" finns redan på {song}',
  tag_not_set     = 'Taggen "{tag}" fanns inte på {song}',
  no_tags         = 'Inga taggar på {song}',
  tags_list       = 'Taggar: {tags}',
  menu_title      = 'Taggar  (upp/ner, Enter växlar, Esc stänger)',
}

i18n.CATALOGUES = CATALOGUES

--- The language names this plugin has a catalogue for, sorted.
function i18n.languages()
  local out = {}
  for name in pairs(CATALOGUES) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

--- Whether a catalogue exists. Case-insensitive, returns the canonical name.
function i18n.known(name)
  if type(name) ~= 'string' then
    return nil
  end
  if CATALOGUES[name] then
    return name
  end
  local want = name:lower()
  for candidate in pairs(CATALOGUES) do
    if candidate:lower() == want then
      return candidate
    end
  end
  return nil
end

--------------------------------------------------------------------------
-- reading the game's setting
--------------------------------------------------------------------------

--- Extracts `[Game] Language` from the text of UltraStar's config.ini.
-- Kept here, and pure, so it can be tested without the game: the adapter only
-- supplies the file contents.
-- @return the language name, or nil when the file does not state one
function i18n.language_from_config(text)
  if type(text) ~= 'string' then
    return nil
  end

  local section = ''
  for line in (text:gsub('\r\n', '\n') .. '\n'):gmatch('([^\n]*)\n') do
    local header = line:match('^%s*%[([^%]]+)%]')
    if header then
      section = header:lower()
    elseif section == 'game' then
      local key, value = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
      if key and key:lower() == 'language' and value ~= '' then
        return value
      end
    end
  end

  return nil
end

--- Decides which catalogue to use.
-- @param requested the `language` setting: 'auto', or a language name
-- @param game_language what UltraStar reports, or nil
-- @return the catalogue name, and the reason ('pinned', 'game', 'default')
function i18n.resolve(requested, game_language)
  if requested and requested ~= '' and requested:lower() ~= 'auto' then
    local pinned = i18n.known(requested)
    if pinned then
      return pinned, 'pinned'
    end
    -- an unknown pin is not worth refusing to start over; fall through to auto
  end

  local from_game = i18n.known(game_language)
  if from_game then
    return from_game, 'game'
  end

  return i18n.DEFAULT, 'default'
end

--------------------------------------------------------------------------
-- tag labels
--------------------------------------------------------------------------

--[[
  Display names for the suggested tags.

  The tag written to disk is always the canonical name - `bad` stays `bad` in
  every language, because that is what someone greps for and what travels with
  a song folder between machines. Only what is drawn on screen changes.

  English is deliberately absent: its label IS the canonical name, so the
  English interface is a direct mirror of the file. Any tag with no entry here,
  including one the user invented, shows its own name.
]]
local TAG_LABELS = {
  German = {
    ['bad']        = 'schlecht',
    ['review']     = 'prüfen',
    ['bad-audio']  = 'Ton fehlerhaft',
    ['bad-video']  = 'Video fehlerhaft',
    ['bad-lyrics'] = 'Text fehlerhaft',
    ['bad-timing'] = 'Timing fehlerhaft',
    ['duplicate']  = 'Duplikat',
    ['favorite']   = 'Favorit',
  },
  French = {
    ['bad']        = 'mauvais',
    ['review']     = 'à vérifier',
    ['bad-audio']  = 'audio défectueux',
    ['bad-video']  = 'vidéo défectueuse',
    ['bad-lyrics'] = 'paroles incorrectes',
    ['bad-timing'] = 'synchro incorrecte',
    ['duplicate']  = 'doublon',
    ['favorite']   = 'favori',
  },
  Spanish = {
    ['bad']        = 'mal',
    ['review']     = 'revisar',
    ['bad-audio']  = 'audio defectuoso',
    ['bad-video']  = 'vídeo defectuoso',
    ['bad-lyrics'] = 'letra incorrecta',
    ['bad-timing'] = 'sincronía incorrecta',
    ['duplicate']  = 'duplicado',
    ['favorite']   = 'favorito',
  },
  Italian = {
    ['bad']        = 'scadente',
    ['review']     = 'da rivedere',
    ['bad-audio']  = 'audio difettoso',
    ['bad-video']  = 'video difettoso',
    ['bad-lyrics'] = 'testo errato',
    ['bad-timing'] = 'sincronia errata',
    ['duplicate']  = 'duplicato',
    ['favorite']   = 'preferito',
  },
  Dutch = {
    ['bad']        = 'slecht',
    ['review']     = 'nakijken',
    ['bad-audio']  = 'audio slecht',
    ['bad-video']  = 'video slecht',
    ['bad-lyrics'] = 'tekst onjuist',
    ['bad-timing'] = 'timing onjuist',
    ['duplicate']  = 'duplicaat',
    ['favorite']   = 'favoriet',
  },
  Portuguese = {
    ['bad']        = 'má qualidade',
    ['review']     = 'revisar',
    ['bad-audio']  = 'áudio com problemas',
    ['bad-video']  = 'vídeo com problemas',
    ['bad-lyrics'] = 'letra incorreta',
    ['bad-timing'] = 'sincronia incorreta',
    ['duplicate']  = 'duplicado',
    ['favorite']   = 'favorito',
  },
  Polish = {
    ['bad']        = 'zły',
    ['review']     = 'do sprawdzenia',
    ['bad-audio']  = 'zły dźwięk',
    ['bad-video']  = 'zły obraz',
    ['bad-lyrics'] = 'zły tekst',
    ['bad-timing'] = 'złe dopasowanie',
    ['duplicate']  = 'duplikat',
    ['favorite']   = 'ulubiony',
  },
  Russian = {
    ['bad']        = 'плохой',
    ['review']     = 'проверить',
    ['bad-audio']  = 'плохой звук',
    ['bad-video']  = 'плохое видео',
    ['bad-lyrics'] = 'плохой текст',
    ['bad-timing'] = 'плохая синхронизация',
    ['duplicate']  = 'дубликат',
    ['favorite']   = 'избранное',
  },
  Swedish = {
    ['bad']        = 'dålig',
    ['review']     = 'granska',
    ['bad-audio']  = 'dåligt ljud',
    ['bad-video']  = 'dålig video',
    ['bad-lyrics'] = 'fel text',
    ['bad-timing'] = 'fel timing',
    ['duplicate']  = 'dubblett',
    ['favorite']   = 'favorit',
  },
}

i18n.TAG_LABELS = TAG_LABELS

--- Display name for a canonical tag, in `language` (default: the active one).
-- Pass a language of false to get the canonical name back untouched, which is
-- what the log wants.
function i18n.tag(name, language)
  if type(name) ~= 'string' then
    return tostring(name)
  end
  if language == false then
    return name
  end

  local labels = TAG_LABELS[language or current]
  if labels and labels[name] then
    return labels[name]
  end
  return name
end

--- Menu entry for a canonical tag.
-- Shows the canonical name next to the translation, because the point of the
-- tag file is being searchable afterwards: a player who only ever sees
-- `schlecht` has no way of knowing to grep for `bad`.
function i18n.tag_entry(name, language)
  local label = i18n.tag(name, language)
  if label == name then
    return name
  end
  return label .. ' (' .. name .. ')'
end

--------------------------------------------------------------------------
-- lookup
--------------------------------------------------------------------------

--- Selects the active catalogue. An unknown name falls back to English rather
-- than leaving the interface half-translated.
-- @return the name actually in use
function i18n.set_language(name)
  current = i18n.known(name) or i18n.DEFAULT
  return current
end

function i18n.language()
  return current
end

--- Fills `{name}` holes from `vars`.
-- A hole with no value is left as it is: visible in a screenshot, which is how
-- a broken translation gets noticed, and never an error at a keypress.
local function interpolate(template, vars)
  if not vars then
    return template
  end
  return (template:gsub('{(%w+)}', function(name)
    local value = vars[name]
    if value == nil then
      return '{' .. name .. '}'
    end
    return tostring(value)
  end))
end

i18n._interpolate = interpolate

--- Localises the tag-shaped values in `vars`.
-- Two placeholders carry canonical tag names by convention: `{tag}`, one name,
-- and `{tags}`, a list of them. Both are translated for the screen and left
-- alone for the log, which is the whole reason those two forms exist.
local function localize_vars(vars, language)
  if not vars then
    return nil
  end
  if vars.tag == nil and type(vars.tags) ~= 'table' then
    return vars
  end

  local out = {}
  for name, value in pairs(vars) do
    out[name] = value
  end

  if out.tag ~= nil then
    out.tag = i18n.tag(out.tag, language)
  end

  if type(out.tags) == 'table' then
    local parts = {}
    for i = 1, #out.tags do
      parts[i] = i18n.tag(out.tags[i], language)
    end
    out.tags = table.concat(parts, ', ')
  end

  return out
end

i18n._localize_vars = localize_vars

local function lookup(language, key)
  local catalogue = CATALOGUES[language]
  if catalogue and catalogue[key] then
    return catalogue[key]
  end
  -- a missing entry in a translation falls back per key, so a partial
  -- catalogue is still worth shipping
  local fallback = CATALOGUES[i18n.DEFAULT][key]
  if fallback then
    return fallback
  end
  -- an unknown key is a bug in this plugin, not in a translation; show
  -- something identifiable rather than nothing
  return '[' .. tostring(key) .. ']'
end

--- The message for `key` in the active language, with tag names translated.
function i18n.t(key, vars)
  return interpolate(lookup(current, key), localize_vars(vars, nil))
end

--- The message for `key` in English, with tag names left canonical.
-- Used for the log, so bug reports stay readable by everyone and the tag names
-- in them still match what is on disk.
function i18n.en(key, vars)
  return interpolate(lookup(i18n.DEFAULT, key), localize_vars(vars, false))
end

--- Every message key, sorted. English defines the set.
function i18n.keys()
  local out = {}
  for key in pairs(CATALOGUES[i18n.DEFAULT]) do
    out[#out + 1] = key
  end
  table.sort(out)
  return out
end

return i18n
