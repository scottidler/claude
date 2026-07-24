#!/usr/bin/env python3
"""Harvest the Enterprise Analytics reports for a trailing window and post the
raw JSON files to a Slack channel with a short note.

Two steps, one command:
  1. Invoke the sibling pull-usage-report.py once per report (cost, usage,
     user-cost, user-usage) for a trailing window (default 3 months), writing
     one JSON file per report -- the 4 files leadership gets, each in its
     native shape.
  2. Upload all files to a Slack channel as a single message (one initial
     comment / note, N attachments) via Slack's external-upload flow.

Stdlib only -- no venv or pip. Uploads with a token that carries `files:write`
(default TATARI_SLACK_TOOLKIT_API_TOKEN, which posts as the token's owner).
The token value is never printed or logged.

Use --dry-run to harvest the files and print the plan WITHOUT posting to Slack.
"""
import argparse
import glob
import json
import logging
import mimetypes
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

log = logging.getLogger("harvest-and-post")

SLACK_API = "https://slack.com/api"

# The four token/cost reports pull-usage-report.py knows about. The 5th
# analytics endpoint (`.../users`, per-user activity/adoption -- not tokens)
# is not wired into the puller; add it there first if leadership wants it.
DEFAULT_REPORTS = ["cost", "usage", "user-cost", "user-usage"]

# #engineering-leadership in the Tatari workspace.
DEFAULT_CHANNEL = "C089C6Y41ND"

# The Analytics API retains no data before this instant (confirmed by a live
# 400: "data prior to 2026-01-01 is not available"). Clamp the window start.
EARLIEST = datetime(2026, 1, 1, tzinfo=timezone.utc)

# Token with files:write. Owner-scoped -- uploads post AS this user.
DEFAULT_TOKEN_ENV = "TATARI_SLACK_TOOLKIT_API_TOKEN"


def parse_args():
    p = argparse.ArgumentParser(
        description=(
            "Harvest the Enterprise Analytics reports for a trailing window "
            "and post the JSON files to Slack with a note."
        )
    )
    p.add_argument(
        "--days",
        type=int,
        default=90,
        help="Trailing window length in days (default: 90 -- ~3 months).",
    )
    p.add_argument(
        "--report",
        action="append",
        dest="reports",
        default=None,
        help=(
            "Report to harvest (repeatable). Default: all four -- "
            f"{', '.join(DEFAULT_REPORTS)}."
        ),
    )
    p.add_argument(
        "--group-by",
        action="append",
        default=None,
        help="Dimension passed through to the puller (repeatable). Default: model.",
    )
    p.add_argument(
        "--channel",
        default=DEFAULT_CHANNEL,
        help=f"Slack channel id to post to (default: {DEFAULT_CHANNEL} = #engineering-leadership).",
    )
    p.add_argument(
        "--note",
        default=None,
        help="Message body / initial comment posted with the files. Default: a generated summary.",
    )
    p.add_argument(
        "--out-dir",
        default=None,
        help="Directory for the harvested JSON files. Default: ./enterprise-usage-<end-date>.",
    )
    p.add_argument(
        "--post-dir",
        default=None,
        help=(
            "Skip harvesting; post the existing enterprise-*.json files already "
            "in this directory. Avoids re-hitting the API to re-post."
        ),
    )
    p.add_argument(
        "--thread",
        action="store_true",
        help=(
            "Fallback layout: post the note as a top-level message, then attach "
            "the files as replies in its thread. Default (off) posts one message "
            "with the note and all files attached together."
        ),
    )
    p.add_argument(
        "--token-env",
        default=DEFAULT_TOKEN_ENV,
        help=f"Env var holding a Slack token with files:write (default: {DEFAULT_TOKEN_ENV}).",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Harvest the files and print the plan, but do NOT post to Slack.",
    )
    p.add_argument(
        "--log-level",
        default="info",
        choices=["trace", "debug", "info", "warn", "error"],
        help="Log verbosity (default: info). 'trace' maps to DEBUG with per-request detail.",
    )
    return p.parse_args()


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def resolve_window(days):
    """Return (start, end) for a trailing `days` window, clamped to EARLIEST."""
    log.debug("resolve_window(days=%s)", days)
    end = datetime.now(timezone.utc)
    start = end - timedelta(days=days)
    if start < EARLIEST:
        log.warning(
            "window start %s precedes the API's earliest retained data %s; clamping",
            iso(start),
            iso(EARLIEST),
        )
        start = EARLIEST
    log.debug("resolve_window -> start=%s end=%s", iso(start), iso(end))
    return start, end


def harvest(report, start, end, group_by, out_dir):
    """Run pull-usage-report.py for one report; return the output file path."""
    log.debug(
        "harvest(report=%s, start=%s, end=%s, group_by=%s, out_dir=%s)",
        report,
        iso(start),
        iso(end),
        group_by,
        out_dir,
    )
    here = os.path.dirname(os.path.abspath(__file__))
    puller = os.path.join(here, "pull-usage-report.py")
    out_path = os.path.join(
        out_dir, f"enterprise-{report}-{iso(start)[:10]}-{iso(end)[:10]}.json"
    )
    cmd = [
        sys.executable,
        puller,
        "--report",
        report,
        "--start",
        iso(start),
        "--end",
        iso(end),
        "--output",
        out_path,
    ]
    for g in group_by:
        cmd += ["--group-by", g]

    env = dict(os.environ)
    env["PYTHONDONTWRITEBYTECODE"] = "1"  # skill dir is read-only under sandbox
    log.debug("harvest running: %s", " ".join(cmd))
    proc = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if proc.stderr.strip():
        log.debug("puller[%s] stderr: %s", report, proc.stderr.strip())
    if proc.returncode != 0:
        log.error("puller failed for report=%s (rc=%s): %s", report, proc.returncode, proc.stderr.strip())
        raise SystemExit(f"pull-usage-report.py failed for --report {report}")

    size = os.path.getsize(out_path)
    log.info("harvested %s -> %s (%.1f KB)", report, out_path, size / 1024)
    return out_path


def slack_post(method, token, fields):
    """POST form-encoded to a Slack Web API method; return the parsed JSON."""
    log.debug("slack_post(method=%s, fields=%s)", method, list(fields.keys()))
    data = urllib.parse.urlencode(fields).encode("utf-8")
    req = urllib.request.Request(
        f"{SLACK_API}/{method}",
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = json.loads(resp.read().decode("utf-8"))
    if not body.get("ok"):
        log.error("slack %s failed: %s", method, body.get("error"))
        raise SystemExit(f"Slack {method} error: {body.get('error')}")
    return body


def upload_bytes(upload_url, file_path):
    """PUT-equivalent: POST the file bytes to a Slack external upload URL."""
    log.debug("upload_bytes(file=%s)", file_path)
    with open(file_path, "rb") as f:
        payload = f.read()
    filename = os.path.basename(file_path)
    ctype = mimetypes.guess_type(filename)[0] or "application/octet-stream"

    boundary = f"----harvest{uuid.uuid4().hex}"
    body = b"".join(
        [
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'.encode(),
            f"Content-Type: {ctype}\r\n\r\n".encode(),
            payload,
            f"\r\n--{boundary}--\r\n".encode(),
        ]
    )
    req = urllib.request.Request(
        upload_url,
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        text = resp.read().decode("utf-8", errors="replace")
    log.debug("upload_bytes(%s) -> %s", filename, text.strip()[:200])


def upload_all(files, token):
    """Upload every file's bytes; return the [{id, title}] list for completion."""
    log.debug("upload_all(files=%s)", len(files))
    uploaded = []
    for path in files:
        length = os.path.getsize(path)
        name = os.path.basename(path)
        info = slack_post(
            "files.getUploadURLExternal",
            token,
            {"filename": name, "length": length},
        )
        upload_bytes(info["upload_url"], path)
        uploaded.append({"id": info["file_id"], "title": name})
        log.info("uploaded %s (file_id=%s)", name, info["file_id"])
    return uploaded


def message_ts(complete_result):
    """Pull the shared message ts out of a completeUploadExternal response."""
    for f in complete_result.get("files", []):
        shares = f.get("shares", {})
        for scope in ("public", "private"):
            for _chan, posts in shares.get(scope, {}).items():
                if posts:
                    return posts[0].get("ts")
    return None


def post_single(files, channel, note, token):
    """One message: the note plus all files attached together."""
    log.debug("post_single(files=%s, channel=%s, note_len=%s)", len(files), channel, len(note))
    uploaded = upload_all(files, token)
    result = slack_post(
        "files.completeUploadExternal",
        token,
        {
            "files": json.dumps(uploaded),
            "channel_id": channel,
            "initial_comment": note,
        },
    )
    ts = message_ts(result)
    n_shared = len(result.get("files", []))
    log.info("posted %s file(s) to channel %s in one message (ts=%s)", n_shared, channel, ts)
    if n_shared != len(files):
        log.warning(
            "expected %s files in the message, Slack reports %s -- "
            "consider --thread",
            len(files),
            n_shared,
        )
    return result


def post_threaded(files, channel, note, token):
    """Fallback: note as a top-level message, files as replies in its thread."""
    log.debug("post_threaded(files=%s, channel=%s, note_len=%s)", len(files), channel, len(note))
    parent = slack_post("chat.postMessage", token, {"channel": channel, "text": note})
    thread_ts = parent["ts"]
    log.info("posted note to channel %s (thread_ts=%s)", channel, thread_ts)
    uploaded = upload_all(files, token)
    result = slack_post(
        "files.completeUploadExternal",
        token,
        {
            "files": json.dumps(uploaded),
            "channel_id": channel,
            "thread_ts": thread_ts,
        },
    )
    log.info("attached %s file(s) as replies in thread %s", len(uploaded), thread_ts)
    return result


def post_files(files, channel, note, token, thread):
    """Post the note + files, either as one message or note-plus-threaded-files."""
    if thread:
        return post_threaded(files, channel, note, token)
    return post_single(files, channel, note, token)


def default_note(start, end, files):
    """A short, plain default note when the caller doesn't supply one."""
    return (
        f"Trailing pull of our enterprise Claude usage and cost, "
        f"{iso(start)[:10]} to {iso(end)[:10]} (data as of {iso(end)[:10]}), "
        "straight from Anthropic's Analytics API. Four files, one per report: "
        "org-wide cost, org-wide token usage (including 5m/1h cache), per-user "
        "cost, per-user token usage. All broken out by model. Cost fields are "
        "in cents, divide by 100 for dollars."
    )


LEVELS = {
    "trace": logging.DEBUG,
    "debug": logging.DEBUG,
    "info": logging.INFO,
    "warn": logging.WARNING,
    "error": logging.ERROR,
}


def main():
    args = parse_args()
    logging.basicConfig(
        level=LEVELS[args.log_level],
        format="%(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
    )
    log.debug("main(args=%s)", {k: v for k, v in vars(args).items()})

    reports = args.reports or DEFAULT_REPORTS
    group_by = args.group_by or ["model"]
    start, end = resolve_window(args.days)

    if args.post_dir:
        files = sorted(glob.glob(os.path.join(args.post_dir, "enterprise-*.json")))
        if not files:
            raise SystemExit(f"No enterprise-*.json files found in {args.post_dir}")
        log.info("post-dir: posting %s existing file(s) from %s", len(files), args.post_dir)
    else:
        out_dir = args.out_dir or os.path.join(
            os.getcwd(), f"enterprise-usage-{iso(end)[:10]}"
        )
        os.makedirs(out_dir, exist_ok=True)
        log.info("harvesting %s report(s) into %s", len(reports), out_dir)
        files = [harvest(r, start, end, group_by, out_dir) for r in reports]

    note = args.note or default_note(start, end, files)

    if args.dry_run:
        log.info("dry-run: %s file(s) ready, NOT posting to Slack", len(files))
        print("Files:")
        for f in files:
            print(f"  {f}  ({os.path.getsize(f) / 1024:.1f} KB)")
        print(f"\nWould post to channel: {args.channel}")
        print(f"Layout: {'note + threaded files' if args.thread else 'one message, note + all files'}")
        print(f"Note:\n{note}")
        return

    token = os.environ.get(args.token_env)
    if not token:
        raise SystemExit(
            f"Env var {args.token_env} is not set. It must hold a Slack token "
            "with the files:write scope."
        )

    post_files(files, args.channel, note, token, args.thread)
    log.info("done: %s file(s) posted to %s", len(files), args.channel)


if __name__ == "__main__":
    main()
