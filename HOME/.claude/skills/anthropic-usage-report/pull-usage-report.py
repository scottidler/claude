#!/usr/bin/env python3
"""Pull Claude Enterprise Analytics API usage/cost data to JSON or CSV.

Stdlib only — no venv or pip install needed. Run with `python3` or `uv run`.
"""
import argparse
import csv
import http.client
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

API_HOST = "https://api.anthropic.com"
ANTHROPIC_VERSION = "2023-06-01"

ENDPOINTS = {
    "user-usage": "/v1/organizations/analytics/user_usage_report",
    "usage": "/v1/organizations/analytics/usage_report",
    "user-cost": "/v1/organizations/analytics/user_cost_report",
    "cost": "/v1/organizations/analytics/cost_report",
}

DEFAULT_API_KEY_ENV = "ANTHROPIC_ENTERPRISE_SPEND_REPORTING_API_KEY"

# Org-wide time-series reports ("usage", "cost") hard-cap the page `limit` to
# these values per bucket_width -- confirmed by live 400s, not documented.
# Per-user reports ("user-usage", "user-cost") return one row per user for
# the whole window rather than per-bucket rows and aren't subject to this cap.
BUCKET_LIMIT_CAPS = {"1m": 1440, "1h": 168, "1d": 31}
BUCKETED_REPORTS = {"usage", "cost"}


def parse_args():
    p = argparse.ArgumentParser(
        description="Pull Claude Enterprise Analytics usage/cost data to JSON or CSV."
    )
    p.add_argument(
        "--report",
        choices=sorted(ENDPOINTS) + ["all"],
        default="user-usage",
        help=(
            "Which analytics report to pull (default: user-usage — per-user "
            "token usage). 'all' pulls every report into one JSON object keyed "
            "by report name (json only; each report has a different row shape)."
        ),
    )
    p.add_argument("--start", help="ISO 8601 starting_at (e.g. 2026-06-01T00:00:00Z).")
    p.add_argument("--end", help="ISO 8601 ending_at (default: now).")
    p.add_argument(
        "--days",
        type=int,
        default=30,
        help="If --start is omitted, pull the last N days (default: 30).",
    )
    p.add_argument(
        "--chunk-days",
        type=int,
        default=30,
        help="Split the range into windows of at most this many days per request (default: 30).",
    )
    p.add_argument(
        "--bucket-width",
        default="1d",
        choices=["1m", "1h", "1d"],
        help="Time bucket granularity (default: 1d). Ignored by report types that don't accept it.",
    )
    p.add_argument(
        "--group-by",
        action="append",
        default=None,
        help="Dimension to group by (repeatable). Default: model.",
    )
    p.add_argument(
        "--product",
        action="append",
        dest="products",
        default=None,
        help="Filter to a product, e.g. chat, claude_code (repeatable).",
    )
    p.add_argument(
        "--format",
        choices=["json", "csv"],
        default="json",
        help="Output format (default: json).",
    )
    p.add_argument(
        "--output",
        help="Output file path. Default: enterprise-<report>-<start>-<end>.<ext> in the cwd.",
    )
    p.add_argument(
        "--api-key-env",
        default=DEFAULT_API_KEY_ENV,
        help=f"Env var holding the Analytics API key (default: {DEFAULT_API_KEY_ENV}).",
    )
    p.add_argument(
        "--limit",
        type=int,
        default=None,
        help=(
            "Page size for pagination (default: 1000, or the bucket-width cap "
            "for --report usage/cost -- 31 for 1d, 168 for 1h, 1440 for 1m)."
        ),
    )
    return p.parse_args()


def resolve_window(args):
    end = (
        datetime.fromisoformat(args.end.replace("Z", "+00:00"))
        if args.end
        else datetime.now(timezone.utc)
    )
    start = (
        datetime.fromisoformat(args.start.replace("Z", "+00:00"))
        if args.start
        else end - timedelta(days=args.days)
    )
    return start, end


def chunk_window(start, end, chunk_days):
    windows = []
    cursor = start
    step = timedelta(days=chunk_days)
    while cursor < end:
        window_end = min(cursor + step, end)
        windows.append((cursor, window_end))
        cursor = window_end
    return windows


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


TRANSIENT_ERRORS = (
    http.client.IncompleteRead,
    ConnectionError,
    TimeoutError,
    urllib.error.URLError,
)
MAX_RETRIES = 5


def fetch_page(path, params, api_key):
    query = urllib.parse.urlencode(params, doseq=True)
    url = f"{API_HOST}{path}?{query}"
    req = urllib.request.Request(
        url,
        headers={
            "anthropic-version": ANTHROPIC_VERSION,
            "x-api-key": api_key,
        },
    )
    last_err = None
    for attempt in range(MAX_RETRIES):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            raise SystemExit(f"HTTP {e.code} from {path}: {body}")
        except TRANSIENT_ERRORS as e:
            last_err = e
            delay = 2**attempt
            print(
                f"Transient error on {path} (attempt {attempt + 1}/{MAX_RETRIES}): "
                f"{e!r} -- retrying in {delay}s",
                file=sys.stderr,
            )
            time.sleep(delay)
    raise SystemExit(f"Giving up on {path} after {MAX_RETRIES} attempts: {last_err!r}")


def fetch_all(path, base_params, api_key, limit):
    records = []
    page = None
    while True:
        params = dict(base_params)
        params["limit"] = limit
        if page:
            params["page"] = page
        data = fetch_page(path, params, api_key)
        records.extend(data.get("data", []))
        if not data.get("has_more"):
            break
        page = data["next_page"]
        time.sleep(0.2)  # org-wide rate limit is 60 req/min
    return records


def normalize_records(records):
    """"usage"/"cost" (org-wide) return one record per time bucket, each
    holding a nested results[] list of per-group breakdown rows -- unlike
    "user-usage"/"user-cost", which are already flat, one row per user.
    Expand results[] into standalone rows carrying the bucket's
    starting_at/ending_at, so JSON and CSV output are uniform across all
    four report types."""
    normalized = []
    for r in records:
        results = r.get("results")
        if isinstance(results, list):
            for row in results:
                merged = dict(row)
                merged["starting_at"] = r.get("starting_at")
                merged["ending_at"] = r.get("ending_at")
                normalized.append(merged)
        else:
            normalized.append(r)
    return normalized


def flatten(record, prefix=""):
    """Flatten nested dicts with dot-joined keys for CSV columns."""
    out = {}
    for k, v in record.items():
        key = f"{prefix}{k}" if not prefix else f"{prefix}.{k}"
        if isinstance(v, dict):
            out.update(flatten(v, key))
        else:
            out[key] = v
    return out


def write_json(records, output_path):
    with open(output_path, "w") as f:
        json.dump(records, f, indent=2, default=str)


def write_csv(records, output_path):
    flattened = [flatten(r) for r in records]
    columns = []
    seen = set()
    for row in flattened:
        for k in row:
            if k not in seen:
                seen.add(k)
                columns.append(k)
    with open(output_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        writer.writerows(flattened)


def fetch_report(report, args, api_key, windows, group_by):
    """Pull one report across all windows and return its normalized records."""
    path = ENDPOINTS[report]

    # "usage"/"cost" bucket by time and hard-cap `limit` to the bucket-width's
    # max bucket count (server-enforced, e.g. 31 for bucket_width=1d) even
    # though "cost" never accepts bucket_width as a request param -- it
    # always buckets daily server-side. "user-usage"/"user-cost" return one
    # row per user for the whole window and aren't capped this way.
    effective_bucket_width = args.bucket_width if report == "usage" else "1d"
    if report in BUCKETED_REPORTS:
        cap = BUCKET_LIMIT_CAPS[effective_bucket_width]
        if args.limit is not None and args.limit > cap:
            print(
                f"--limit {args.limit} exceeds the API's cap of {cap} for "
                f"--report {report} at bucket_width={effective_bucket_width}; "
                f"using {cap} instead.",
                file=sys.stderr,
            )
        limit = min(args.limit, cap) if args.limit is not None else cap
    else:
        limit = args.limit if args.limit is not None else 1000

    all_records = []
    for w_start, w_end in windows:
        params = {
            "starting_at": iso(w_start),
            "ending_at": iso(w_end),
            "group_by[]": group_by,
        }
        if report in ("usage", "user-usage"):
            params["bucket_width"] = args.bucket_width
        if args.products:
            params["products[]"] = args.products
        all_records.extend(fetch_all(path, params, api_key, limit))

    return normalize_records(all_records)


def main():
    args = parse_args()

    api_key = os.environ.get(args.api_key_env)
    if not api_key:
        raise SystemExit(
            f"Env var {args.api_key_env} is not set. "
            "Export your Claude Enterprise Analytics API key first."
        )

    start, end = resolve_window(args)
    windows = chunk_window(start, end, args.chunk_days)
    group_by = args.group_by or ["model"]

    # "all": pull every report into one JSON object keyed by report name.
    # Each report has a different row shape, so they can't collapse into one
    # flat array without becoming lossy -- a keyed object keeps each intact.
    if args.report == "all":
        if args.format == "csv":
            raise SystemExit(
                "--report all supports --format json only (each report has a "
                "different row shape; they're combined into one keyed JSON "
                "object). Pull reports individually for CSV."
            )
        combined = {}
        total = 0
        for report in sorted(ENDPOINTS):
            recs = fetch_report(report, args, api_key, windows, group_by)
            combined[report] = recs
            total += len(recs)
            print(f"  {report}: {len(recs)} records", file=sys.stderr)
        output_path = args.output or (
            f"enterprise-all-{iso(start)[:10]}-{iso(end)[:10]}.json"
        )
        write_json(combined, output_path)
        print(
            f"Wrote {total} records across {len(combined)} reports to {output_path}",
            file=sys.stderr,
        )
        return

    all_records = fetch_report(args.report, args, api_key, windows, group_by)

    ext = "json" if args.format == "json" else "csv"
    output_path = args.output or (
        f"enterprise-{args.report}-{iso(start)[:10]}-{iso(end)[:10]}.{ext}"
    )

    if args.format == "json":
        write_json(all_records, output_path)
    else:
        write_csv(all_records, output_path)

    print(f"Wrote {len(all_records)} records to {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
