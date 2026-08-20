# `.usdx-user-tags.yaml`

The on-disk format this plugin reads and writes. One file per song directory, sitting
next to the song it describes.

The file is meant to be read by anything, not just this plugin. It is valid YAML, so
`yq` and Python's `yaml.safe_load` handle it, and it is line-oriented enough that `grep`
does too.

## Location and name

Exactly `.usdx-user-tags.yaml`, inside the song's own directory:

```text
Songs/
└── Artist - Song Title/
    ├── Artist - Song Title.txt
    ├── Artist - Song Title.mp3
    └── .usdx-user-tags.yaml
```

The song's directory as reported by UltraStar Deluxe is the authoritative identity. The
path is never reconstructed from artist and title, so two songs with the same title, or a
library spread over several roots, still resolve correctly.

## Shape

```yaml
# UltraStar Deluxe song tags set by the user
# Created by plugin https://github.com/ValeHaas/usdx-tagger
version: 0.1.0
tags:
  - bad-audio
  - review
```

### `version`

The [semantic version](https://semver.org) of the plugin that last wrote the file.

- **MAJOR** — a change that makes an existing file unreadable to this plugin, or changes
  the meaning of what is already written.
- **MINOR** — new capability that older files and older readers still cope with.
- **PATCH** — fixes only; no format or behaviour change.

A rewrite always stamps the version of the plugin doing the writing. Reading is
deliberately permissive: the field may be absent, may be the bare `1` that the earliest
files carry, and may be a version newer than the plugin reading it. None of those is an
error, because refusing to read would cost the user their tags for no benefit.

### `tags`

A block sequence of plain scalars. Order is stable: existing entries keep their position
and new tags are appended, so a diff shows only what changed.

Tag names are arbitrary. They are trimmed, internal whitespace is collapsed, and ASCII is
lowercased, so `Bad-Audio`, `bad-audio` and ` bad-audio ` are one tag. Non-ASCII
characters are preserved but **not** case folded — Lua has no Unicode case mapping, so
`Ärger` and `ärger` stay distinct.

Rejected as tag names: the empty string, control characters, anything over 64 bytes, the
characters `: # [ ] { } , " '`, and a leading `- ? ! & * % @ ` | >`. All of those would
need quoting to stay valid YAML; forbidding them keeps every tag a plain scalar.

### Anything else

Other top-level keys are none of the plugin's business and are preserved verbatim,
including their indented children. A file like this survives a rewrite with only the
`tags` block touched:

```yaml
version: 0.1.0
tags:
  - bad-audio
metadata:
  marked_at: "2026-08-20T18:42:00Z"
  source: "some other tool"
song:
  title: Example Song
```

Comments and blank lines are preserved the same way, wherever they sit.

## What the plugin accepts

The plugin has no YAML library — UltraStar Deluxe embeds plain Lua — so it reads a
deliberately narrow subset:

- blank lines
- `#` comments
- top-level `key: value` scalars at zero indent
- `- item` sequence entries, indented or not
- `tags: []` for an explicitly empty list

## What it refuses

On anything below, the plugin reports the file as unreadable, warns on screen, logs the
line number — and **does not write to the file**. Failing safe beats rewriting a
hand-edited file into something lossy.

| Refused | Why |
|---|---|
| `tags: bad` | `tags` must be a list, not a scalar |
| `tags: [bad, review]` | flow sequences are not parsed |
| `- "bad"` | quoted scalars are not parsed |
| `- name: bad` | nested maps under `tags` are not parsed |
| a tab anywhere | not valid YAML indentation, and a likely mistake |
| two `tags:` keys | ambiguous |
| `version: {a: b}` | not a version string |
| a line that is none of the above | unrecognised |

If you hand-edit a file into one of those shapes, the plugin stops writing to it but
never destroys it. Put it back into the accepted subset and the plugin picks it up again.

## Writing

1. Read and parse the existing file, if any.
2. Modify only the `tags` block, keeping every other line verbatim and in order.
3. Write a temporary file in the same directory, flush it, close it.
4. Move it over the original.

Step 4 is atomic on POSIX. On Windows `rename` fails when the target exists, so the
original is removed first, leaving a brief window in which neither name resolves. If the
write itself fails, the temporary file is deliberately left behind rather than discarded.

The file's existing line endings are preserved, as is the indentation style of its
sequence entries. New files are written with LF and two-space indentation.

When the last tag is removed the file is deleted, which keeps filesystem searches
meaningful. Set `delete_empty_tag_file=false` to keep `tags: []` instead.

## Finding tagged songs

```bash
# every tagged song
find Songs -name '.usdx-user-tags.yaml'

# directories tagged "bad" (anchored, so bad-audio does not match)
grep -rl --include='.usdx-user-tags.yaml' -e '- bad$' Songs | xargs -n1 dirname
```

```powershell
Get-ChildItem -Recurse -Force -Filter '.usdx-user-tags.yaml' |
  Where-Object { $_ | Select-String -Pattern '- bad$' -Quiet } |
  ForEach-Object { $_.Directory.FullName }
```

Because the file is real YAML, a script can also read it properly:

```python
import yaml, pathlib

for f in pathlib.Path('Songs').rglob('.usdx-user-tags.yaml'):
    tags = yaml.safe_load(f.read_text(encoding='utf-8')).get('tags') or []
    if 'bad' in tags:
        print(f.parent)
```

## Files the plugin never touches

The song `.txt`, audio, video, cover and MIDI files are never read for writing, renamed
or deleted. UltraStar Deluxe already parses arbitrary `#TAG:` headers out of the `.txt`
into `TSong.CustomTags`; that route is deliberately unused, because writing there would
modify UltraStar's own song metadata.
