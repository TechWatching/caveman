#!/bin/bash
# caveman — Copilot CLI userPromptSubmitted hook
#
# Detects /caveman commands and natural-language activation/deactivation.
# Writes mode to flag file at ~/.copilot/.caveman-active.
#
# NOTE: Copilot CLI does not yet inject userPromptSubmitted hook output into
# the conversation. The flag write keeps the statusline badge in sync.
# Per-turn reinforcement is stubbed here — upgrade to emit additionalContext
# JSON when Copilot adds output support for this hook event.

COPILOT_DIR="${HOME}/.copilot"
FLAG_PATH="${COPILOT_DIR}/.caveman-active"

# Read stdin JSON
INPUT=$(cat 2>/dev/null)
if [ -z "$INPUT" ]; then exit 0; fi

# Extract prompt field
PROMPT=""
if command -v python3 >/dev/null 2>&1; then
  PROMPT=$(python3 -c "import json,sys
try:
  d=json.loads(sys.argv[1])
  print((d.get('prompt','') or '').strip().lower())
except: print('')
" "$INPUT" 2>/dev/null)
elif command -v jq >/dev/null 2>&1; then
  PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]')
fi

if [ -z "$PROMPT" ]; then exit 0; fi

# Resolve default mode
DEFAULT_MODE="${CAVEMAN_DEFAULT_MODE:-}"
if [ -z "$DEFAULT_MODE" ]; then
  CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
  CONFIG_PATH="${CONFIG_HOME}/caveman/config.json"
  if [ -f "$CONFIG_PATH" ] && command -v python3 >/dev/null 2>&1; then
    DEFAULT_MODE=$(python3 -c "import json,sys
try:
  d=json.load(open(sys.argv[1]))
  print(d.get('defaultMode',''))
except: print('')
" "$CONFIG_PATH" 2>/dev/null)
  fi
fi
DEFAULT_MODE="${DEFAULT_MODE:-full}"
DEFAULT_MODE=$(printf '%s' "$DEFAULT_MODE" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
case "$DEFAULT_MODE" in
  off|lite|full|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress) ;;
  *) DEFAULT_MODE="full" ;;
esac

write_flag() {
  local mode="$1"
  mkdir -p "$COPILOT_DIR" 2>/dev/null || true
  [ -L "$FLAG_PATH" ] && return
  TEMP_FILE="${COPILOT_DIR}/.caveman-active.$$.$(date +%s 2>/dev/null || echo 0)"
  if printf '%s' "$mode" > "$TEMP_FILE" 2>/dev/null; then
    chmod 600 "$TEMP_FILE" 2>/dev/null || true
    mv "$TEMP_FILE" "$FLAG_PATH" 2>/dev/null || rm -f "$TEMP_FILE" 2>/dev/null || true
  fi
}

delete_flag() {
  rm -f "$FLAG_PATH" 2>/dev/null || true
}

# Natural-language activation
if echo "$PROMPT" | grep -qiE '(activate|enable|turn on|start|talk like).*caveman|caveman.*(mode|activate|enable|turn on|start)'; then
  if ! echo "$PROMPT" | grep -qiE '(stop|disable|turn off|deactivate)'; then
    if [ "$DEFAULT_MODE" != "off" ]; then
      write_flag "$DEFAULT_MODE"
    fi
  fi
fi

# /caveman slash commands
if echo "$PROMPT" | grep -q '^/caveman'; then
  PARTS=($PROMPT)
  CMD="${PARTS[0]}"
  ARG="${PARTS[1]:-}"
  MODE=""

  case "$CMD" in
    /caveman-commit)            MODE="commit" ;;
    /caveman-review)            MODE="review" ;;
    /caveman-compress|/caveman:caveman-compress) MODE="compress" ;;
    /caveman|/caveman:caveman)
      case "$ARG" in
        lite)         MODE="lite" ;;
        ultra)        MODE="ultra" ;;
        wenyan-lite)  MODE="wenyan-lite" ;;
        wenyan|wenyan-full) MODE="wenyan" ;;
        wenyan-ultra) MODE="wenyan-ultra" ;;
        *)            MODE="$DEFAULT_MODE" ;;
      esac
      ;;
  esac

  if [ -n "$MODE" ] && [ "$MODE" != "off" ]; then
    write_flag "$MODE"
  elif [ "$MODE" = "off" ]; then
    delete_flag
  fi
fi

# Natural-language deactivation
if echo "$PROMPT" | grep -qiE '(stop|disable|deactivate|turn off).*caveman|caveman.*(stop|disable|deactivate|turn off)|normal mode'; then
  delete_flag
fi

# NOTE: Per-turn reinforcement stub.
# When Copilot adds output support for userPromptSubmitted, emit:
#   {"additionalContext": "CAVEMAN MODE ACTIVE (...). Drop articles/filler/pleasantries/hedging. ..."}
# Read flag here and output JSON. For now, exit cleanly.
exit 0
