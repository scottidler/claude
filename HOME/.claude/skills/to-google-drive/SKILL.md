---
name: to-google-drive
description: >-
  Upload a local file to a Google shared drive (via Scott's `gws` CLI),
  dashifying the name, archiving byte-identical duplicate copies, and optionally
  granting people editor access. Use whenever Scott wants to put, upload, stash,
  drop, deposit, or share a local document/file into Google Drive or a shared
  drive -- e.g. "upload this docx to the eng drive", "stick this in google
  drive", "put this in the Security folder and give Greg edit access", "send this
  to drive". Defaults to the Engineering shared drive, folder `to-google-drive`,
  and keeps the file in its native format (preserving .docx redlines etc.).
  Trigger even when Scott names a destination folder or person but not "gws" or
  "skill", and even when he just says "get this onto drive".
---

# to-google-drive

Thin shim over `scripts/upload.py`, which does all the work through the `gws`
CLI. Your job is to locate the file Scott means, then call the script.

## Locate the file first

If Scott gives an explicit path, use it. If he says "this doc" / "the one I
downloaded" / names it loosely, find it and confirm the path before uploading.
Check both `~/Downloads` and `~/Documents`: a `kondo` cron runs every 15 minutes
and relocates downloaded files into `~/Documents` (and other dirs) by extension,
so a "just downloaded" file may already have moved. Search both, pick by
recency/name, and don't guess between similarly-named files.

## Run the script

```bash
python3 ~/.claude/skills/to-google-drive/scripts/upload.py "<file>" [flags]
```

Flags (all optional):

- `--drive NAME` -- shared drive name. Default `Engineering`.
- `--folder PATH` -- destination folder under the drive; nested `a/b/c` is
  created segment by segment if missing. Default `to-google-drive`. Map Scott's
  words to this: "the Security folder" -> `--folder Security`.
- `--convert` -- convert Office files to native Google format (.docx -> Google
  Doc, .xlsx -> Sheet, .pptx -> Slides). Omitted by default because native
  preserves tracked changes / redlines / exact formatting, which matters for
  contracts and anything round-tripping with Word/Excel. Only pass `--convert`
  when Scott explicitly wants a Google Doc/Sheet/Slides.
- `--editor EMAIL...` -- grant editor (writer) access. Space-separated, never
  comma-separated. Resolve names to `@tatari.tv` emails (use the persona skill
  if unsure).
- `--no-dedup` -- skip duplicate archival.
- `--dedup-dir DIR...` -- dirs to scan for byte-identical copies. Default: the
  file's own dir plus `~/Downloads` and `~/Documents`. Advanced override; rarely
  needed.

The script prints a JSON summary including `webViewLink`. Relay that link and
who got editor access. For dedup the script runs `rkvr rmrf <dup>` on each
byte-identical copy it finds in the scanned dirs (it archives before deleting,
so it's recoverable via `rkvr rcvr` -- never a hard `rm`). If it removed copies,
mention which.

## Examples

**"upload this docx to the eng drive's Security folder and give Greg edit"**
```bash
python3 ~/.claude/skills/to-google-drive/scripts/upload.py \
  ~/Downloads/schedule-1-addendum.docx --folder Security --editor greg.schwartz@tatari.tv
```

**"convert this spreadsheet to a Google Sheet and drop it in drive"**
```bash
python3 ~/.claude/skills/to-google-drive/scripts/upload.py ~/Downloads/q4-numbers.xlsx --convert
```

## Notes

- Bare `gws` = the work account (`scott.idler@tatari.tv`), which owns the
  Tatari shared drives. The script relies on that default.
- `gws` requires the upload path to sit inside the working directory; the script
  handles this by running the upload from the file's own directory.
