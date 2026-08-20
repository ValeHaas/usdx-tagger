## Requirements: UltraStar Deluxe Song Tagging Plugin

### 1. Goal

Create a platform-agnostic UltraStar Deluxe plugin that allows users to tag the currently selected or played song directly from within UltraStar Deluxe.

The plugin must store tags in a file named:

```text
.ultrastar-tags.yaml
```

The file must be created inside the song’s directory so that tags remain associated with the song and can be found or processed independently of UltraStar Deluxe.

The primary use case is quickly tagging problematic songs during a karaoke session for later review.

---

## 2. Core functionality

### 2.1 Tag the current song

The plugin must provide an action such as:

```text
Add tag to current song
```

A recommended default keyboard shortcut is:

```text
T
```

The action should work whenever UltraStar Deluxe can identify the current song, including:

- Song-selection screen
- Song preview
- Active gameplay
- Results screen, where supported

The plugin must determine the song’s actual filesystem directory from UltraStar Deluxe rather than reconstructing the path from the artist and title.

### 2.2 Remove a tag

The plugin must provide an action such as:

```text
Remove tag from current song
```

Recommended shortcut:

```text
Shift+T
```

Removing a tag must update only `.ultrastar-tags.yaml`. It must not modify or delete:

- The UltraStar `.txt` file
- Audio files
- Video files
- Cover images
- MIDI files
- Other unrelated files

### 2.3 View tags

The plugin should provide an action such as:

```text
Show tags for current song
```

Recommended shortcut:

```text
Ctrl+T
```

The current song’s tags may be displayed in a notification or small overlay:

```text
Tags: bad-audio, review
```

This feature is optional for the minimum viable release but should be supported by the underlying design.

---

## 3. Tag model

### 3.1 Initial tags

The minimum implementation must support arbitrary user-defined tags. It should include these suggested defaults:

```text
bad
review
bad-audio
bad-video
bad-lyrics
bad-timing
duplicate
favorite
```

The plugin must not hard-code the tag list into the storage format. New tags should be usable without changing the file schema.

### 3.2 Tag names

Tag names must:

- Be case-insensitive for comparison
- Be stored in a consistent form, preferably lowercase
- Contain only safe characters by default
- Allow letters, numbers, hyphens, underscores, and spaces if supported
- Be trimmed of leading and trailing whitespace
- Reject empty tag names
- Reject YAML-unsafe or invalid values where necessary

For example:

```text
bad-audio
incorrect lyrics
duplicate
```

The plugin should normalize equivalent tags consistently. For example:

```text
Bad-Audio
bad-audio
 bad-audio
```

should resolve to the same stored tag.

---

## 4. YAML file format

### 4.1 Required filename

The filename must be exactly:

```text
.ultrastar-tags.yaml
```

It must be placed in the song directory:

```text
Songs/
└── Artist - Song Title/
    ├── Artist - Song Title.txt
    ├── Artist - Song Title.mp3
    └── .ultrastar-tags.yaml
```

### 4.2 Recommended schema

A basic file should look like this:

```yaml
version: 1
tags:
  - bad
```

A file with multiple tags could be:

```yaml
version: 1
tags:
  - bad-audio
  - bad-lyrics
  - review
```

### 4.3 Extended metadata

The format should support optional metadata without requiring it:

```yaml
version: 1
tags:
  - bad-audio
  - review

metadata:
  marked_at: "2026-08-20T18:42:00Z"
  updated_at: "2026-08-20T18:42:00Z"
  source: "ultrastar-tags-plugin"
```

The plugin may also store identifying information for diagnostics:

```yaml
version: 1
song:
  title: "Example Song"
  artist: "Example Artist"

tags:
  - bad
```

Song metadata must be informational only. The plugin must use the actual filesystem path as the authoritative song identity.

### 4.4 Minimal valid file

The following must be accepted:

```yaml
tags:
  - bad
```

If `version` is omitted, the plugin should assume version `1`.

### 4.5 Empty tag file

If the last tag is removed, the plugin should either:

- Delete `.ultrastar-tags.yaml`, or
- Preserve the file with an empty list:

```yaml
version: 1
tags: []
```

The preferred behavior is to delete the file when no tags remain, because this makes filesystem searches more useful.

This behavior should be configurable if practical.

---

## 5. Tagging workflow

### 5.1 Quick-tag workflow

The plugin should support a fast workflow suitable for live parties:

1. User presses the tag shortcut.
2. Plugin opens a small tag-selection menu.
3. User selects a tag such as `bad`.
4. Plugin updates `.ultrastar-tags.yaml`.
5. Plugin displays confirmation.

Example:

```text
Added tag "bad" to Artist - Song Title
```

The menu should remember recently used tags and place common tags near the top.

### 5.2 Fast default tag

The plugin should support a direct shortcut for the most common action:

```text
G = add the "bad" tag
```

This avoids opening a menu during gameplay.

Recommended actions:

```text
G       Add "bad" tag
Shift+G Remove "bad" tag
T       Open tag menu
```

The shortcuts must be configurable to avoid conflicts with UltraStar Deluxe controls.

### 5.3 Multiple tags

Adding a tag that already exists must be idempotent:

- It must not create duplicates.
- It should report that the tag was already present or silently succeed.

Example:

```yaml
tags:
  - bad
  - review
```

The order of tags should be stable. New tags may be appended to the end.

---

## 6. Reading and displaying existing tags

When a song is selected, the plugin should detect `.ultrastar-tags.yaml` in the song directory.

If the file contains tags, the plugin may display an unobtrusive indicator:

```text
[bad] [review]
```

The plugin should optionally support filtering songs based on tags:

- Hide songs with the `bad` tag
- Show only songs with the `favorite` tag
- Show songs tagged `review`
- Exclude songs tagged `duplicate`

Filtering is optional for the first version, but the tag-reading API must support it.

Malformed tag files must not crash the application. The plugin should show a warning and log the parsing error.

---

## 7. Filesystem requirements

### 7.1 Correct directory resolution

The plugin must place `.ultrastar-tags.yaml` in the actual song directory associated with the current song.

It must correctly support:

- Nested song directories
- Unicode filenames
- Spaces and punctuation
- Multiple songs with the same title
- Different capitalization
- Multiple song libraries
- Relative and absolute library paths
- Network-mounted folders, where writable

The plugin must not infer the path solely from:

```text
artist + title
```

### 7.2 Safe writes

Updates to `.ultrastar-tags.yaml` must be atomic:

1. Read the existing file, if present.
2. Parse and validate its contents.
3. Modify only the plugin-owned data.
4. Write a temporary file in the same directory.
5. Flush and close the temporary file.
6. Replace the original file atomically where supported.

The plugin must preserve existing tags and unknown YAML fields whenever possible.

If preserving unknown fields is not possible, this limitation must be documented.

### 7.3 No destructive behavior

The plugin must never:

- Delete the song directory
- Delete song media
- Rename song directories
- Modify UltraStar song metadata by default
- Overwrite unrelated files
- Execute shell commands
- Require a database
- Require network access

---

## 8. YAML handling

The plugin must use a proper YAML parser and serializer rather than manually editing YAML text.

The YAML implementation must:

- Support UTF-8
- Reject unsafe YAML features
- Avoid executing arbitrary YAML content
- Handle missing fields gracefully
- Validate that `tags` is a list of strings
- Ignore or preserve unknown fields according to the selected implementation
- Provide useful parse errors

Example invalid data:

```yaml
tags: bad
```

The plugin should report that `tags` must be a list, rather than crashing.

The plugin should use safe YAML loading and must not support YAML object deserialization or other code-execution features.

---

## 9. Plugin architecture

Separate UltraStar Deluxe integration from tag-file management.

Recommended architecture:

```text
UltraStarTagsPlugin
├── UltraStarAdapter
│   ├── getCurrentSong()
│   ├── getCurrentSongDirectory()
│   ├── registerActions()
│   └── showNotification()
│
├── TagService
│   ├── addTag()
│   ├── removeTag()
│   ├── listTags()
│   ├── hasTag()
│   └── clearTags()
│
├── TagFileRepository
│   ├── load()
│   ├── save()
│   ├── exists()
│   └── deleteIfEmpty()
│
├── TagValidator
└── PluginConfig
```

The `TagService` and `TagFileRepository` must not depend directly on UltraStar Deluxe. This allows them to be tested independently and reused by future tools.

---

## 10. Platform-agnostic requirements

The plugin must support, where permitted by UltraStar Deluxe’s plugin API:

- Windows
- Linux
- macOS

The implementation must:

- Use cross-platform filesystem APIs
- Use platform-neutral path objects
- Avoid hard-coded path separators
- Avoid shell commands
- Avoid drive-letter assumptions
- Support UTF-8 paths
- Avoid platform-specific configuration paths in application logic
- Avoid requiring a separate service
- Avoid requiring network access
- Avoid requiring administrator privileges

Platform-specific code should be isolated to:

- Plugin loading
- Keyboard registration
- Configuration directory resolution
- User notifications
- UltraStar Deluxe API integration

---

## 11. Configuration

The plugin should support configuration similar to:

```ini
enabled=true
quick_tag=bad
tag_menu_key=T
quick_add_key=G
quick_remove_key=Shift+G
show_notifications=true
show_existing_tags=true
delete_empty_tag_file=true
hide_marked_songs=false
```

The configuration must be stored in the platform-appropriate user configuration directory, not in the song library.

The plugin must:

- Provide sensible defaults
- Handle missing configuration
- Recover from malformed configuration
- Allow keyboard shortcuts to be changed
- Allow the quick tag to be changed
- Preserve unknown configuration options where possible

---

## 12. Error handling

The plugin must handle:

- No current song
- Song path unavailable
- Song stored in a read-only directory
- Missing song directory
- Permission denied
- Invalid YAML
- Missing `tags` field
- Invalid tag values
- Unsupported song source, such as an archive
- Concurrent file changes
- Network filesystem failures
- Unicode and long paths

Failure must never crash UltraStar Deluxe.

Example notifications:

```text
No current song is available.
```

```text
Cannot update tags: the song directory is not writable.
```

```text
Cannot read .ultrastar-tags.yaml: invalid YAML.
```

Detailed diagnostics should be written to a plugin log.

---

## 13. External usability

The tag file must be usable without UltraStar Deluxe.

A user should be able to find all songs marked `bad` using ordinary tools.

The plugin documentation should include examples for:

- Finding all `.ultrastar-tags.yaml` files
- Finding files containing the `bad` tag
- Listing songs marked `review`
- Moving tagged song directories to a quarantine folder
- Removing a tag with an external script

The plugin should not require the external tool to understand UltraStar Deluxe’s internal database.

---

## 14. Testing requirements

Automated tests must cover:

- Creating a new `.ultrastar-tags.yaml`
- Adding one tag
- Adding multiple tags
- Adding a duplicate tag
- Removing one tag
- Removing the final tag
- Deleting an empty tag file
- Reading existing tags
- Preserving tag order
- Unicode paths and tag values
- Invalid YAML
- Missing `tags`
- Non-string tag values
- Read-only directories
- Atomic write failures
- Concurrent modification handling
- Missing song directories

Integration tests should verify:

- The plugin identifies the correct song
- Keyboard actions invoke the correct operation
- Notifications appear correctly
- The plugin does not interrupt gameplay
- Existing song files remain unchanged

---

## 15. Acceptance criteria

The plugin is complete when:

1. It loads on every supported platform.
2. The user can add a tag to the current song from within UltraStar Deluxe.
3. The plugin creates `.ultrastar-tags.yaml` in the correct song directory.
4. Tags are stored as valid YAML.
5. The user can add and remove multiple tags.
6. Duplicate tags are not created.
7. The user can quickly apply a default tag such as `bad`.
8. Existing tags survive later modifications.
9. The user can find tagged songs using filesystem tools.
10. The plugin never modifies song media or UltraStar metadata files.
11. The plugin handles read-only and malformed files without crashing.
12. Unicode paths work correctly.
13. The plugin requires no network connection or external database.
14. Tag-file logic is tested independently of UltraStar Deluxe.
15. UltraStar-specific and platform-specific code is isolated behind adapters.
16. The file format is documented and versioned.

---

## 16. Recommended minimum viable release

The first version should implement:

- A configurable quick-tag shortcut
- A configurable tag-menu shortcut
- Add and remove operations
- Arbitrary tag names
- `.ultrastar-tags.yaml`
- The schema:

```yaml
version: 1
tags:
  - bad
```

- Atomic writes
- Safe YAML parsing
- Notifications
- UTF-8 and cross-platform filesystem support
- Error handling for unavailable or unwritable songs
- Independent unit tests for the tag-file system

Tag filtering, tag reasons, recently used tags, result-screen tagging, and external cleanup tools can be added later without changing the basic file format.