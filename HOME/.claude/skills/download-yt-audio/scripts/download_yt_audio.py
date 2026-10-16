#!/usr/bin/env python3
"""Download the audio only of YouTube videos with yt-dlp. Stdlib only.

  download_yt_audio.py check
      Report each dependency; for a missing or stale one, print how to install it.
      Exit 0 when everything required is present, 1 otherwise.

  download_yt_audio.py get <url> [<url> ...] [--format native|opus|m4a|mp3] [--out-dir DIR]
      Run `check`, then download each URL as a single video (never its playlist).
      Retry once after 10s on HTTP 403. Print one `ok <size> <path>` or `fail <url> <reason>`
      line per URL. Exit 0 only if every URL succeeded.

--debug logs this script's own steps to stderr. It never passes -v to yt-dlp: verbose
yt-dlp runs go through Scott's signed-in cookies and need his explicit permission.
"""

import argparse
import logging
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import date
from pathlib import Path

log = logging.getLogger("download_yt_audio")

DEFAULT_OUT_DIR = Path.home() / "Downloads" / "yt-audio"
OUTPUT_TEMPLATE = "%(title)s [%(id)s].%(ext)s"
FORMATS = ("native", "opus", "m4a", "mp3")
RETRY_DELAY_SECONDS = 10
STALE_YT_DLP_DAYS = 90
MIN_DENO = (2, 3, 0)
YT_DLP_CONFIG = Path.home() / ".config" / "yt-dlp" / "config"


@dataclass
class Dep:
    name: str
    install: str
    required: bool = True


DEPS = (
    Dep("yt-dlp", "uv tool install yt-dlp"),
    Dep("ffmpeg", "sudo apt install ffmpeg"),
    Dep("ffprobe", "sudo apt install ffmpeg  (ffprobe ships with ffmpeg)"),
    Dep("deno", "curl -fsSL https://deno.land/install.sh | sh  (or: cargo binstall deno)"),
)


@dataclass
class Finding:
    name: str
    ok: bool
    detail: str
    fix: str = ""


def version_output(binary: str, flag: str) -> str:
    result = subprocess.run([binary, flag], capture_output=True, text=True, timeout=30)
    return (result.stdout or result.stderr).strip().splitlines()[0] if (result.stdout or result.stderr) else ""


def check_yt_dlp_age(version: str) -> Finding:
    log.debug("check_yt_dlp_age: version=%s", version)
    match = re.match(r"(\d{4})\.(\d{1,2})\.(\d{1,2})", version)
    if not match:
        return Finding("yt-dlp age", True, f"unparsed version {version!r}, age not checked")
    released = date(*(int(part) for part in match.groups()))
    age = (date.today() - released).days
    if age > STALE_YT_DLP_DAYS:
        log.warning("yt-dlp is %d days old", age)
        return Finding(
            "yt-dlp age",
            False,
            f"{version} is {age} days old; stale builds cause YouTube 403s",
            "uv tool upgrade yt-dlp  (ask Scott before upgrading)",
        )
    return Finding("yt-dlp age", True, f"{version} is {age} days old")


def check_deno_version(version_line: str) -> Finding:
    log.debug("check_deno_version: version_line=%s", version_line)
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", version_line)
    if not match:
        return Finding("deno version", True, f"unparsed version {version_line!r}, minimum not checked")
    version = tuple(int(part) for part in match.groups())
    minimum = ".".join(map(str, MIN_DENO))
    if version < MIN_DENO:
        return Finding(
            "deno version",
            False,
            f"{match.group(0)} is below {minimum}, yt-dlp's EJS solver minimum",
            "deno upgrade",
        )
    return Finding("deno version", True, f"{match.group(0)} >= {minimum}")


def check_config() -> Finding:
    log.debug("check_config: path=%s", YT_DLP_CONFIG)
    if not YT_DLP_CONFIG.is_file():
        return Finding(
            "yt-dlp config",
            False,
            f"{YT_DLP_CONFIG} missing; YouTube bot-checks this IP without browser cookies",
            f"add `--cookies-from-browser firefox` and `--remote-components ejs:github` to {YT_DLP_CONFIG}",
        )
    text = YT_DLP_CONFIG.read_text()
    missing = [flag for flag in ("--cookies-from-browser", "--remote-components") if flag not in text]
    if missing:
        return Finding(
            "yt-dlp config",
            False,
            f"{YT_DLP_CONFIG} lacks {' '.join(missing)}",
            f"add `--cookies-from-browser firefox` and `--remote-components ejs:github` to {YT_DLP_CONFIG}",
        )
    return Finding("yt-dlp config", True, f"{YT_DLP_CONFIG} sets cookies and EJS components")


def run_checks() -> list[Finding]:
    log.debug("run_checks: deps=%s", [dep.name for dep in DEPS])
    findings: list[Finding] = []
    for dep in DEPS:
        path = shutil.which(dep.name)
        if path is None:
            findings.append(Finding(dep.name, False, "not installed", dep.install))
            continue
        flag = "-version" if dep.name in ("ffmpeg", "ffprobe") else "--version"
        version = version_output(dep.name, flag)
        findings.append(Finding(dep.name, True, f"{path}  {version}"))
        if dep.name == "yt-dlp":
            findings.append(check_yt_dlp_age(version))
        elif dep.name == "deno":
            findings.append(check_deno_version(version))
    findings.append(check_config())
    log.debug("run_checks: failed=%s", [f.name for f in findings if not f.ok])
    return findings


def print_findings(findings: list[Finding]) -> bool:
    for finding in findings:
        print(f"{'ok  ' if finding.ok else 'MISS'} {finding.name}: {finding.detail}")
        if finding.fix:
            print(f"     fix: {finding.fix}")
    return all(finding.ok for finding in findings)


def yt_dlp_command(url: str, audio_format: str, out_dir: Path) -> list[str]:
    command = [
        "yt-dlp",
        "-x",
        "--no-playlist",
        "--no-simulate",
        "--print",
        "after_move:filepath",
        "-P",
        str(out_dir),
        "-o",
        OUTPUT_TEMPLATE,
    ]
    if audio_format != "native":
        command += ["--audio-format", audio_format]
    if audio_format == "mp3":
        command += ["--audio-quality", "0"]
    return [*command, url]


def download_one(url: str, audio_format: str, out_dir: Path) -> tuple[Path | None, str]:
    log.debug("download_one: url=%s format=%s out_dir=%s", url, audio_format, out_dir)
    command = yt_dlp_command(url, audio_format, out_dir)
    for attempt in (1, 2):
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode == 0:
            lines = [line for line in result.stdout.splitlines() if line.strip()]
            path = Path(lines[-1]) if lines else None
            if path is not None and path.is_file():
                log.debug("download_one: url=%s attempt=%d path=%s", url, attempt, path)
                return path, ""
            return None, f"yt-dlp exited 0 but printed no file (stdout: {result.stdout.strip()[:200]!r})"
        error_lines = [line for line in result.stderr.splitlines() if "ERROR" in line]
        reason = error_lines[-1] if error_lines else f"yt-dlp exit {result.returncode}"
        if attempt == 1 and "HTTP Error 403" in result.stderr:
            log.warning("download_one: url=%s 403, retrying in %ds", url, RETRY_DELAY_SECONDS)
            time.sleep(RETRY_DELAY_SECONDS)
            continue
        log.error("download_one: url=%s attempt=%d failed: %s", url, attempt, reason)
        return None, reason
    return None, "unreachable"


def human_size(num_bytes: int) -> str:
    size = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return f"{size:.1f}{unit}"
        size /= 1024
    return f"{size:.1f}GB"


def cmd_check(_args: argparse.Namespace) -> int:
    return 0 if print_findings(run_checks()) else 1


def cmd_get(args: argparse.Namespace) -> int:
    log.debug("cmd_get: urls=%s format=%s out_dir=%s", args.urls, args.format, args.out_dir)
    findings = run_checks()
    blocking = [f for f in findings if not f.ok and f.name in {dep.name for dep in DEPS if dep.required}]
    if blocking:
        print_findings(findings)
        print("not downloading: install the missing dependencies above first")
        return 1
    for finding in findings:
        if not finding.ok:
            print(f"warn {finding.name}: {finding.detail}")
            if finding.fix:
                print(f"     fix: {finding.fix}")
    out_dir: Path = args.out_dir.expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)
    failures = 0
    for url in args.urls:
        path, reason = download_one(url, args.format, out_dir)
        if path is None:
            failures += 1
            print(f"fail {url} {reason}")
        else:
            print(f"ok   {human_size(path.stat().st_size):>8} {path}")
    log.debug("cmd_get: done urls=%d failures=%d", len(args.urls), failures)
    return 1 if failures else 0


def audio_format_arg(value: str) -> str:
    lowered = value.lower()
    if lowered not in FORMATS:
        raise argparse.ArgumentTypeError(f"invalid format {value!r}, choose from {' '.join(FORMATS)}")
    return lowered


def main() -> int:
    parser = argparse.ArgumentParser(description="Download the audio only of YouTube videos with yt-dlp.")
    parser.add_argument("--debug", action="store_true", help="log this script's steps to stderr")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check", help="report dependencies and how to install missing ones").set_defaults(func=cmd_check)
    get = sub.add_parser("get", help="download audio for one or more URLs")
    get.add_argument("urls", nargs="+", metavar="url")
    get.add_argument("--format", type=audio_format_arg, default="native", help=f"one of: {' '.join(FORMATS)}")
    get.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    get.set_defaults(func=cmd_get)
    args = parser.parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.WARNING,
        format="%(levelname)s %(message)s",
        stream=sys.stderr,
    )
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
