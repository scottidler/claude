#!/usr/bin/env python3
"""Upload a local file to a Google shared drive via Scott's `gws` CLI.

The heavy lifting for the `to-google-drive` skill lives here so each invocation
doesn't re-derive the gws request bodies by hand. It:

  1. dashifies the local filename (lowercase, spaces/underscores/commas -> dashes)
  2. archives byte-identical duplicate copies (OS "(1)" re-downloads) via rkvr
  3. resolves the target shared drive by name (default: Engineering)
  4. resolves/creates the destination folder PATH under that drive (default: the
     skill name, "to-google-drive"); nested "a/b/c" paths are walked + created
  5. uploads the file -- native by default (preserves .docx redlines etc.),
     or converted to a native Google format with --convert
  6. optionally grants editor (writer) access to one or more people

Everything that removes a file uses `rkvr rmrf` (recoverable), never `rm`.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# Office mimetype -> the native Google format it converts into with --convert.
CONVERT_MAP = {
    ".docx": "application/vnd.google-apps.document",
    ".doc": "application/vnd.google-apps.document",
    ".xlsx": "application/vnd.google-apps.spreadsheet",
    ".xls": "application/vnd.google-apps.spreadsheet",
    ".pptx": "application/vnd.google-apps.presentation",
    ".ppt": "application/vnd.google-apps.presentation",
    ".csv": "application/vnd.google-apps.spreadsheet",
    ".txt": "application/vnd.google-apps.document",
}
FOLDER_MIME = "application/vnd.google-apps.folder"


def log(msg):
    print(f"[to-google-drive] {msg}", file=sys.stderr)


def run(cmd, cwd=None):
    """Run a command, return stdout. Raise with stderr on failure."""
    log("$ " + " ".join(cmd[:2]) + (" ..." if len(cmd) > 2 else ""))
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"command failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stderr}")
    return proc.stdout


def gws(args, cwd=None):
    """Call gws and parse the JSON object it prints (skipping the keyring banner)."""
    out = run(["gws", *args], cwd=cwd)
    start = out.find("{")
    if start == -1:
        return {}
    obj = json.loads(out[start:])
    if isinstance(obj, dict) and "error" in obj:
        raise RuntimeError(f"gws API error: {json.dumps(obj['error'])}")
    return obj


def dashify_name(name):
    """Mirror the `dashify` tool's rules so we can predict the renamed file."""
    stem, ext = os.path.splitext(name)
    s = stem.lower()
    s = re.sub(r"[ _,]+", "-", s)
    s = re.sub(r"-{2,}", "-", s).strip("-")
    return s + ext.lower()


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def dashify(path):
    """Rename the file in place via the real `dashify` tool; return the new path."""
    path = Path(path)
    target = dashify_name(path.name)
    if target == path.name:
        log(f"already dashified: {path.name}")
        return path
    run(["dashify", path.name], cwd=str(path.parent))
    new_path = path.parent / target
    if not new_path.exists():
        raise RuntimeError(f"dashify did not produce expected file: {new_path}")
    log(f"dashified -> {target}")
    return new_path


def dedup(target, dirs):
    """Archive byte-identical copies of `target` found in `dirs` (keeping target)."""
    target = Path(target).resolve()
    digest = md5(target)
    removed = []
    seen = {str(target)}
    for d in dirs:
        d = Path(d).expanduser()
        if not d.is_dir():
            continue
        for f in d.iterdir():
            rf = f.resolve()
            if not f.is_file() or str(rf) in seen:
                continue
            if f.stat().st_size == target.stat().st_size and md5(f) == digest:
                run(["rkvr", "rmrf", f.name], cwd=str(d))
                removed.append(str(f))
                seen.add(str(rf))
    if removed:
        log(f"archived {len(removed)} duplicate(s) via rkvr (recover with `rkvr rcvr`)")
    return removed


def find_drive(name):
    res = gws(["drive", "drives", "list", "--params", json.dumps({"pageSize": 100})])
    for d in res.get("drives", []):
        if d["name"] == name:
            return d["id"]
    have = ", ".join(d["name"] for d in res.get("drives", []))
    raise SystemExit(f"shared drive {name!r} not found. available: {have}")


def find_or_create_folder(drive_id, path):
    """Walk a slash-separated folder path under the drive root, creating as needed."""
    parent = drive_id
    for segment in [p for p in path.split("/") if p]:
        q = (
            f"mimeType = '{FOLDER_MIME}' and name = '{segment}' "
            f"and '{parent}' in parents and trashed = false"
        )
        res = gws([
            "drive", "files", "list", "--params",
            json.dumps({
                "driveId": drive_id, "corpora": "drive",
                "includeItemsFromAllDrives": True, "supportsAllDrives": True,
                "q": q, "fields": "files(id,name)", "pageSize": 10,
            }),
        ])
        files = res.get("files", [])
        if files:
            parent = files[0]["id"]
            log(f"folder exists: {segment}")
        else:
            created = gws([
                "drive", "files", "create",
                "--params", json.dumps({"supportsAllDrives": True, "fields": "id,name"}),
                "--json", json.dumps({"name": segment, "mimeType": FOLDER_MIME, "parents": [parent]}),
            ])
            parent = created["id"]
            log(f"created folder: {segment}")
    return parent


def upload(path, folder_id, convert):
    path = Path(path)
    ext = path.suffix.lower()
    meta = {"parents": [folder_id]}
    if convert and ext in CONVERT_MAP:
        meta["name"] = path.stem  # Google-native files carry no extension
        meta["mimeType"] = CONVERT_MAP[ext]
        log(f"uploading + converting to {CONVERT_MAP[ext]}")
    else:
        meta["name"] = path.name
        if convert:
            log(f"--convert ignored: no native Google format for {ext or 'this file'}")
        log("uploading native (format preserved)")
    cmd = [
        "drive", "files", "create",
        "--params", json.dumps({
            "supportsAllDrives": True, "uploadType": "multipart",
            "fields": "id,name,mimeType,webViewLink,parents",
        }),
        "--json", json.dumps(meta),
        "--upload", path.name,  # gws requires the upload path inside cwd
    ]
    # cwd = the file's directory so gws accepts the relative --upload path.
    # gws auto-detects the upload content-type from the extension, which is
    # enough for Drive to convert correctly when --convert is set.
    return gws(cmd, cwd=str(path.parent))


def grant_editor(file_id, email):
    res = gws([
        "drive", "permissions", "create",
        "--params", json.dumps({
            "fileId": file_id, "supportsAllDrives": True,
            "sendNotificationEmail": False, "fields": "id,role,emailAddress",
        }),
        "--json", json.dumps({"type": "user", "role": "writer", "emailAddress": email}),
    ])
    log(f"granted editor: {email}")
    return res


def main():
    ap = argparse.ArgumentParser(description="Upload a local file to a Google shared drive via gws.")
    ap.add_argument("file", help="local file to upload")
    ap.add_argument("--drive", default="Engineering", help="shared drive name (default: Engineering)")
    ap.add_argument("--folder", default="to-google-drive",
                    help="destination folder path under the drive; nested a/b/c is created as needed "
                         "(default: to-google-drive)")
    ap.add_argument("--convert", action="store_true",
                    help="convert Office files to native Google format (default: keep native)")
    # space-separated per Scott's CLI convention; never comma-separated
    ap.add_argument("--editor", nargs="*", default=[], metavar="EMAIL",
                    help="email(s) to grant editor/writer access (space-separated)")
    ap.add_argument("--no-dedup", action="store_true", help="skip byte-identical duplicate archival")
    ap.add_argument("--dedup-dir", nargs="*", default=None, metavar="DIR",
                    help="dirs to scan for duplicates (default: file's dir + ~/Downloads + ~/Documents)")
    args = ap.parse_args()

    path = Path(args.file).expanduser()
    if not path.is_file():
        raise SystemExit(f"not a file: {path}")

    path = dashify(path)

    if not args.no_dedup:
        dirs = args.dedup_dir or [str(path.parent), "~/Downloads", "~/Documents"]
        dedup(path, dirs)

    drive_id = find_drive(args.drive)
    folder_id = find_or_create_folder(drive_id, args.folder)
    result = upload(path, folder_id, args.convert)

    editors = [grant_editor(result["id"], e) for e in args.editor]

    summary = {
        "name": result["name"],
        "mimeType": result["mimeType"],
        "webViewLink": result.get("webViewLink"),
        "drive": args.drive,
        "folder": args.folder,
        "editors": [e.get("emailAddress") for e in editors],
        "local_file": str(path),
    }
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
