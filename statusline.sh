#!/usr/bin/env bash
# Claude Code custom status line - powerline style
set -euo pipefail

DATA=$(cat)

# Parse all fields in one jq call
eval "$(echo "$DATA" | jq -r '
  @sh "VERSION=\(.version // "?")",
  @sh "MODEL=\(.model.display_name // .model.id // "?")",
  @sh "USED_PCT=\(.context_window.used_percentage // "")",
  @sh "CTX_SIZE=\(.context_window.context_window_size // 0)",
  @sh "SESSION_COST=\(.cost.total_cost_usd // 0)",
  @sh "DURATION_MS=\(.cost.total_duration_ms // 0)",
  @sh "LINES_ADDED=\(.cost.total_lines_added // 0)",
  @sh "LINES_REMOVED=\(.cost.total_lines_removed // 0)",
  @sh "SESSION_ID=\(.session_id // "unknown")",
  @sh "CWD=\(.workspace.current_dir // .cwd // "")"
')"

# Shorten model name: strip version, strip "context" noise, lowercase
# "Opus 4.6" -> "opus", "opus (1M context)" -> "opus"
MODEL=$(echo "$MODEL" | sed -e 's/ ([^)]*context[^)]*)//g' -e 's/Opus [0-9.]*/opus/' -e 's/Sonnet [0-9.]*/sonnet/' -e 's/Haiku [0-9.]*/haiku/')

# Format context window size
if [[ "$CTX_SIZE" -ge 1000000 ]]; then
    CTX_WIN="$(awk "BEGIN{printf \"%.0fM\",$CTX_SIZE/1000000}")"
elif [[ "$CTX_SIZE" -ge 1000 ]]; then
    CTX_WIN="$(awk "BEGIN{printf \"%.0fK\",$CTX_SIZE/1000}")"
else
    CTX_WIN="$CTX_SIZE"
fi

# --- ANSI helpers ---
RST=$'\033[0m'
BOLD=$'\033[1m'
fg()  { printf '\033[38;5;%sm' "$1"; }
bg()  { printf '\033[48;5;%sm' "$1"; }
fgr() { printf '\033[38;2;%s;%s;%sm' "$1" "$2" "$3"; }
bgr() { printf '\033[48;2;%s;%s;%sm' "$1" "$2" "$3"; }

# --- Load color scheme ---
SCHEME="${CLAUDE_COLORSCHEME:-catppuccin-mocha}"
SCHEME_DIR="${CLAUDE_COLORSCHEME_DIR:-$HOME/.claude/statusline.d}"
SCHEME_FILE="${SCHEME_DIR}/${SCHEME}.sh"

# Validate scheme name: alphanumeric, hyphens, underscores only
if [[ "$SCHEME" =~ ^[a-zA-Z0-9_-]+$ ]] && [[ -f "$SCHEME_FILE" ]]; then
    source "$SCHEME_FILE"
else
    # Inline fallback (catppuccin-mocha) so statusline never breaks
    S0="30;30;46"; S1="49;50;68"; S2="69;71;90"; S3="88;91;112"
    ACCENT_PRIMARY="137;180;250"; ACCENT_OK="166;227;161"
    ACCENT_WARN="249;226;175"; ACCENT_CAUTION="250;179;135"
    ACCENT_ERROR="243;139;168"; ACCENT_COST="148;226;213"
    ACCENT_COST_SECONDARY="249;226;175"; ACCENT_MUTED="147;153;178"
    TEXT="205;214;244"; SUBTEXT="186;194;222"
fi

PL=$'\ue0b0'
PREV_BG=""
OUT=""

# seg <text> <bg_rgb> <fg_rgb>
seg() {
    local text="$1" sbg="$2" sfg="$3"
    IFS=';' read -r br bg_ bb <<< "$sbg"
    if [[ -n "$PREV_BG" ]]; then
        IFS=';' read -r pr pg pb <<< "$PREV_BG"
        OUT+="$(bgr "$br" "$bg_" "$bb")$(fgr "$pr" "$pg" "$pb")${PL}${RST}"
    fi
    IFS=';' read -r fr fg_ fb <<< "$sfg"
    OUT+="$(bgr "$br" "$bg_" "$bb")$(fgr "$fr" "$fg_" "$fb") ${text}${RST}"
    PREV_BG="$sbg"
}

end_seg() {
    if [[ -n "$PREV_BG" ]]; then
        IFS=';' read -r pr pg pb <<< "$PREV_BG"
        OUT+="$(fgr "$pr" "$pg" "$pb")${PL}${RST}"
    fi
}

# --- Cost via ccu ---
TODAY_COST=$(timeout 1s ccu today --json 2>/dev/null | jq -r '.today // 0' 2>/dev/null || echo "0")
WEEK_COST=$(timeout 1s ccu daily --json -d 7 2>/dev/null | jq -r '[.days[].cost] | add // 0' 2>/dev/null || echo "0")
MONTH_COST=$(timeout 1s ccu monthly --json 2>/dev/null | jq -r '.months[0].cost // 0' 2>/dev/null || echo "0")


# --- Format duration ---
DS=$((DURATION_MS/1000)); DM=$((DS/60)); DH=$((DM/60)); DM=$((DM%60))
[[ $DH -gt 0 ]] && DUR="${DH}h${DM}m" || DUR="${DM}m"

# --- Context color (bg/fg) ---
CTX_BG=$S1; CTX_FG=$ACCENT_OK
if [[ -n "$USED_PCT" && "$USED_PCT" != "null" ]]; then
    case $(awk -v p="$USED_PCT" 'BEGIN{if(p>=70)print 4;else if(p>=60)print 3;else if(p>=50)print 2;else print 1}') in
        4) CTX_FG=$ACCENT_ERROR ;;
        3) CTX_FG=$ACCENT_CAUTION ;;
        2) CTX_FG=$ACCENT_WARN ;;
    esac
    CTX="${USED_PCT}%"
else
    CTX="..."
fi

# --- Format costs ---
fc() { awk -v c="$1" 'BEGIN{if(c<10)printf"%.2f",c;else if(c<100)printf"%.1f",c;else printf"%.0f",c}'; }
S_COST=$(echo | fc "$SESSION_COST")
T_COST=$(echo | fc "$TODAY_COST")
W_COST=$(echo | fc "$WEEK_COST")
M_COST=$(echo | fc "$MONTH_COST")

# --- Git branch ---
GIT_BRANCH=""
if [[ -n "$CWD" ]] && git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null; then
    GIT_BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ -n "$GIT_BRANCH" ]]; then
        [[ -n "$(git -C "$CWD" status --porcelain 2>/dev/null | head -1)" ]] && GIT_BRANCH+="*"
    fi
fi

# --- Inline color helpers ---
bgr_split() { IFS=';' read -r r g b <<< "$1"; bgr "$r" "$g" "$b"; }
fgr_split() { IFS=';' read -r r g b <<< "$1"; fgr "$r" "$g" "$b"; }

# --- Build segments ---
#  git |  version |  model(ctx) |  used% | month/week/today/session |  duration | +/-
[[ -n "$GIT_BRANCH" ]] && seg " ${GIT_BRANCH} " "$S2" "$ACCENT_OK"
seg "${VERSION} " "$S1" "$ACCENT_OK"
seg "${MODEL}(${CTX_WIN}) " "$S2" "$ACCENT_PRIMARY"
seg "${CTX} " "$CTX_BG" "$CTX_FG"
seg "\$${M_COST}$(fgr_split $TEXT)|$(fgr_split $ACCENT_COST)\$${W_COST}$(fgr_split $TEXT)|$(fgr_split $ACCENT_COST)\$${T_COST}$(fgr_split $TEXT)|$(fgr_split $ACCENT_COST)\$${S_COST} " "$S2" "$ACCENT_COST"
seg "${DUR} " "$S1" "$SUBTEXT"

if [[ "$LINES_ADDED" != "0" || "$LINES_REMOVED" != "0" ]]; then
    IFS=';' read -r br bg_ bb <<< "$S0"
    IFS=';' read -r pr pg pb <<< "$PREV_BG"
    OUT+="$(bgr "$br" "$bg_" "$bb")$(fgr "$pr" "$pg" "$pb")${PL}${RST}"
    IFS=';' read -r gr gg gb <<< "$ACCENT_OK"
    IFS=';' read -r rr rg rb <<< "$ACCENT_ERROR"
    OUT+="$(bgr "$br" "$bg_" "$bb")$(fgr "$gr" "$gg" "$gb") +${LINES_ADDED}$(fgr "$rr" "$rg" "$rb")-${LINES_REMOVED} ${RST}"
    PREV_BG="$S0"
fi

end_seg
echo -e "$OUT"
