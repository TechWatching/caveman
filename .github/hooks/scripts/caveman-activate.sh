#!/bin/bash
# caveman — Copilot CLI sessionStart hook
#
# Runs on every session start:
#   1. Writes flag file at ~/.copilot/.caveman-active (statusline reads this)
#   2. Emits caveman ruleset as {"additionalContext": "..."} JSON
#      (Copilot CLI v1.0.11+ injects this into the conversation)
#   3. Detects missing statusline config and emits setup nudge

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
SKILL_PATH="$PROJECT_DIR/.github/skills/caveman/SKILL.md"
COPILOT_DIR="${HOME}/.copilot"
FLAG_PATH="${COPILOT_DIR}/.caveman-active"
SETTINGS_PATH="${COPILOT_DIR}/settings.json"

# Resolve mode: env var → config file → default "full"
MODE="${CAVEMAN_DEFAULT_MODE:-}"
if [ -z "$MODE" ]; then
  CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
  CONFIG_PATH="${CONFIG_HOME}/caveman/config.json"
  if [ -f "$CONFIG_PATH" ] && command -v python3 >/dev/null 2>&1; then
    MODE=$(python3 -c "import json,sys
try:
  d=json.load(open(sys.argv[1]))
  print(d.get('defaultMode',''))
except: print('')
" "$CONFIG_PATH" 2>/dev/null)
  fi
fi
MODE="${MODE:-full}"
MODE=$(printf '%s' "$MODE" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')

# Validate
case "$MODE" in
  off|lite|full|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress) ;;
  *) MODE="full" ;;
esac

# "off" mode — skip activation
if [ "$MODE" = "off" ]; then
  rm -f "$FLAG_PATH" 2>/dev/null
  exit 0
fi

# Write flag file (symlink-safe, atomic)
mkdir -p "$COPILOT_DIR" 2>/dev/null || true
if [ ! -L "$FLAG_PATH" ]; then
  TEMP_FILE="${COPILOT_DIR}/.caveman-active.$$.$(date +%s 2>/dev/null || echo 0)"
  if printf '%s' "$MODE" > "$TEMP_FILE" 2>/dev/null; then
    chmod 600 "$TEMP_FILE" 2>/dev/null || true
    mv "$TEMP_FILE" "$FLAG_PATH" 2>/dev/null || rm -f "$TEMP_FILE" 2>/dev/null || true
  fi
fi

# Handle independent modes (commit, review, compress)
case "$MODE" in
  commit|review|compress)
    python3 -c "import json; print(json.dumps({'additionalContext': 'CAVEMAN MODE ACTIVE — level: ${MODE}. Behavior defined by /caveman-${MODE} skill.'}))" 2>/dev/null \
      || printf '{"additionalContext":"CAVEMAN MODE ACTIVE — level: %s. Behavior defined by /caveman-%s skill."}' "$MODE" "$MODE"
    exit 0
    ;;
esac

# Resolve wenyan alias
MODE_LABEL="$MODE"
[ "$MODE" = "wenyan" ] && MODE_LABEL="wenyan-full"

# Statusline nudge: append if statusLine not configured
NUDGE=""
if [ ! -f "$SETTINGS_PATH" ] || \
   (command -v python3 >/dev/null 2>&1 && ! python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if 'statusLine' in d else 1)" "$SETTINGS_PATH" 2>/dev/null); then
  SCRIPT_PATH="${COPILOT_DIR}/hooks/copilot-statusline.sh"
  NUDGE="STATUSLINE SETUP NEEDED: The caveman hooks include a statusline badge showing active mode (e.g. [CAVEMAN], [CAVEMAN:ULTRA]). It is not configured yet. To enable, add this to ~/.copilot/settings.json: \"statusLine\": { \"type\": \"command\", \"command\": \"bash \\\"${SCRIPT_PATH}\\\"\" }. Proactively offer to set this up for the user on first interaction."
fi

# Build output from SKILL.md, filtered to active intensity level
PYTHON_FILTER='
import sys, re, json

skill_path = sys.argv[1]
mode_label = sys.argv[2]
nudge = sys.argv[3] if len(sys.argv) > 3 else ""

try:
    with open(skill_path, "r", encoding="utf-8") as f:
        content = f.read()
    # Strip YAML frontmatter
    body = re.sub(r"^---[\s\S]*?---\s*", "", content)
    lines = body.split("\n")
    out = []
    for line in lines:
        # Intensity table data rows: | **level** | ... — keep only active level
        m = re.match(r"^\|\s*\*\*(\S+?)\*\*\s*\|", line)
        if m:
            if m.group(1) == mode_label:
                out.append(line)
            continue
        # Example lines: "- level: ..." — keep only active level
        m = re.match(r"^- (\S+?):\s", line)
        if m:
            if m.group(1) == mode_label:
                out.append(line)
            continue
        out.append(line)
    text = "CAVEMAN MODE ACTIVE — level: " + mode_label + "\n\n" + "\n".join(out)
except Exception:
    text = ("CAVEMAN MODE ACTIVE — level: " + mode_label + "\n\n"
            "Respond terse like smart caveman. All technical substance stay. Only fluff die.\n\n"
            "## Persistence\n\n"
            "ACTIVE EVERY RESPONSE. No revert after many turns. No filler drift. "
            "Still active if unsure. Off only: \"stop caveman\" / \"normal mode\".\n\n"
            "## Rules\n\n"
            "Drop: articles (a/an/the), filler (just/really/basically), pleasantries, hedging. "
            "Fragments OK. Short synonyms. Technical terms exact. Code blocks unchanged.\n\n"
            "Pattern: [thing] [action] [reason]. [next step].\n\n"
            "## Auto-Clarity\n\n"
            "Drop caveman for: security warnings, irreversible action confirmations, user confused. "
            "Resume after.\n\n"
            "## Boundaries\n\n"
            "Code/commits/PRs: write normal. \"stop caveman\" or \"normal mode\": revert.")

if nudge:
    text += "\n\n" + nudge

print(json.dumps({"additionalContext": text}))
'

if command -v python3 >/dev/null 2>&1; then
  python3 -c "$PYTHON_FILTER" "$SKILL_PATH" "$MODE_LABEL" "$NUDGE" 2>/dev/null && exit 0
fi

# Fallback: no Python — minimal hardcoded rules
TEXT="CAVEMAN MODE ACTIVE — level: ${MODE_LABEL}

Respond terse like smart caveman. All technical substance stay. Only fluff die.

## Persistence

ACTIVE EVERY RESPONSE. No revert after many turns. No filler drift. Still active if unsure. Off only: \"stop caveman\" / \"normal mode\".

## Rules

Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries (sure/certainly/of course/happy to), hedging. Fragments OK. Short synonyms (big not extensive, fix not implement a solution for). Technical terms exact. Code blocks unchanged. Errors quoted exact.

Pattern: [thing] [action] [reason]. [next step].

Not: \"Sure! I'd be happy to help you with that. The issue you're experiencing is likely caused by...\"
Yes: \"Bug in auth middleware. Token expiry check use < not <=. Fix:\"

## Auto-Clarity

Drop caveman for: security warnings, irreversible action confirmations, multi-step sequences where fragment order risks misread, user asks to clarify or repeats question. Resume caveman after clear part done.

## Boundaries

Code/commits/PRs: write normal. \"stop caveman\" or \"normal mode\": revert. Level persist until changed or session end."

if [ -n "$NUDGE" ]; then
  TEXT="${TEXT}

${NUDGE}"
fi

# Output as JSON using python3 or jq, else manual escape
if command -v python3 >/dev/null 2>&1; then
  python3 -c "import json,sys; print(json.dumps({'additionalContext': sys.argv[1]}))" "$TEXT"
elif command -v jq >/dev/null 2>&1; then
  jq -cn --arg ctx "$TEXT" '{"additionalContext": $ctx}'
else
  # Minimal manual escape: replace backslash, double-quote, newline
  ESCAPED=$(printf '%s' "$TEXT" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | head -c 65536)
  printf '{"additionalContext":"%s"}' "$ESCAPED"
fi
