#!/usr/bin/env bash
# Run a literal command or script via codex's sandbox or gemini's agentic yolo mode.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run-via.sh --backend codex|gemini [--write] [--danger-full-access] --script <path> [-- extra args...]
  run-via.sh --backend codex|gemini [--write] [--danger-full-access] -- <command> [args...]

Options:
  --backend codex|gemini   required — which CLI executes the command
  --script <path>          run a script file instead of an inline command
  --write                  codex only: allow writes under the cwd (sandbox_mode=workspace-write)
  --danger-full-access     codex only: full filesystem + network access — confirm with the user first
EOF
}

backend=""
write=false
danger=false
script=""
args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend) backend="$2"; shift 2 ;;
    --write) write=true; shift ;;
    --danger-full-access) danger=true; shift ;;
    --script) script="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; args+=("$@"); break ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$backend" ]]; then
  echo "error: --backend codex|gemini is required" >&2
  exit 2
fi

if [[ -n "$script" ]]; then
  if [[ ! -f "$script" ]]; then
    echo "error: script not found: $script" >&2
    exit 2
  fi
  if [[ -x "$script" ]]; then
    cmd=("$script" "${args[@]}")
  else
    cmd=(bash "$script" "${args[@]}")
  fi
elif [[ ${#args[@]} -gt 0 ]]; then
  cmd=("${args[@]}")
else
  echo "error: provide --script <path> or -- <command...>" >&2
  exit 2
fi

case "$backend" in
  codex)
    codex_args=()
    if $danger; then
      codex_args+=(-c 'sandbox_mode="danger-full-access"')
    elif $write; then
      codex_args+=(-c 'sandbox_mode="workspace-write"')
    fi
    exec codex sandbox "${codex_args[@]}" -- "${cmd[@]}"
    ;;
  gemini)
    printf -v quoted '%q ' "${cmd[@]}"
    prompt="Run this exact shell command using the shell tool. Do not modify, split, retry, or reinterpret it. Do not summarize or explain the output. When it finishes, print exactly three labeled sections in this order: 'stdout:' followed by the raw stdout, 'stderr:' followed by the raw stderr, and 'exit code:' followed by the numeric exit code. Command: ${quoted}"
    exec gemini -p "$prompt" --approval-mode yolo
    ;;
  *)
    echo "error: --backend must be codex or gemini, got: $backend" >&2
    exit 2
    ;;
esac
