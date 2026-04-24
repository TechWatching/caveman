#!/usr/bin/env node
// caveman — Copilot CLI sessionStart hook (cross-platform)
//
// Runs on every session start:
//   1. Writes flag file at ~/.copilot/.caveman-active (statusline reads this)
//   2. Emits caveman ruleset as {"additionalContext": "..."} JSON to stdout
//      (Copilot CLI v1.0.11+ injects this into the conversation)
//   3. Detects missing statusline config and emits setup nudge

'use strict';
const fs   = require('fs');
const path = require('path');
const os   = require('os');

// ── Constants ────────────────────────────────────────────────────────────────

const VALID_MODES = [
  'off', 'lite', 'full', 'ultra',
  'wenyan-lite', 'wenyan', 'wenyan-full', 'wenyan-ultra',
  'commit', 'review', 'compress',
];
const INDEPENDENT_MODES = new Set(['commit', 'review', 'compress']);

const copilotDir   = path.join(os.homedir(), '.copilot');
const flagPath     = path.join(copilotDir, '.caveman-active');
const settingsPath = path.join(copilotDir, 'settings.json');

// SKILL.md lives relative to the project root, two levels above __dirname
// (__dirname = <project>/.github/hooks/scripts/ — CJS guaranteed by package.json)
const projectDir = process.env.CLAUDE_PROJECT_DIR ||
                   path.resolve(__dirname, '..', '..', '..');
const skillPath  = path.join(projectDir, '.github', 'skills', 'caveman', 'SKILL.md');

// ── Mode resolution ──────────────────────────────────────────────────────────

function getDefaultMode() {
  // 1. Environment variable
  const env = (process.env.CAVEMAN_DEFAULT_MODE || '').toLowerCase();
  if (VALID_MODES.includes(env)) return env;

  // 2. Config file
  try {
    const xdg = process.env.XDG_CONFIG_HOME ||
                (process.platform === 'win32'
                  ? (process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'))
                  : path.join(os.homedir(), '.config'));
    const configPath = path.join(xdg, 'caveman', 'config.json');
    const cfg = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    const m   = (cfg.defaultMode || '').toLowerCase();
    if (VALID_MODES.includes(m)) return m;
  } catch (e) { /* not found or invalid */ }

  return 'full';
}

// ── Symlink-safe flag write ──────────────────────────────────────────────────

function safeWriteFlag(p, content) {
  try {
    const dir = path.dirname(p);
    fs.mkdirSync(dir, { recursive: true });

    try { if (fs.lstatSync(dir).isSymbolicLink()) return; } catch (e) { return; }
    try {
      if (fs.lstatSync(p).isSymbolicLink()) return;
    } catch (e) {
      if (e.code !== 'ENOENT') return;
    }

    const tmp = path.join(dir, `.caveman-active.${process.pid}.${Date.now()}`);
    const O_NOFOLLOW = typeof fs.constants.O_NOFOLLOW === 'number' ? fs.constants.O_NOFOLLOW : 0;
    const openFlags  = fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | O_NOFOLLOW;
    let fd;
    try {
      fd = fs.openSync(tmp, openFlags, 0o600);
      fs.writeSync(fd, String(content));
      try { fs.fchmodSync(fd, 0o600); } catch (_) { /* best-effort on Windows */ }
    } finally {
      if (fd !== undefined) fs.closeSync(fd);
    }
    fs.renameSync(tmp, p);
  } catch (_) { /* silent fail — flag is best-effort */ }
}

// ── Main ─────────────────────────────────────────────────────────────────────

const mode = getDefaultMode();

// "off" — skip activation
if (mode === 'off') {
  try { fs.unlinkSync(flagPath); } catch (_) {}
  process.exit(0);
}

// Write flag
safeWriteFlag(flagPath, mode);

// Independent modes (commit/review/compress) — short message, skill handles the rest
if (INDEPENDENT_MODES.has(mode)) {
  process.stdout.write(JSON.stringify({
    additionalContext: 'CAVEMAN MODE ACTIVE — level: ' + mode +
                       '. Behavior defined by /caveman-' + mode + ' skill.',
  }));
  process.exit(0);
}

// Resolve wenyan alias
const modeLabel = mode === 'wenyan' ? 'wenyan-full' : mode;

// Build ruleset from SKILL.md, filtered to the active intensity level
let output;
let skillContent = '';
try { skillContent = fs.readFileSync(skillPath, 'utf8'); } catch (_) {}

if (skillContent) {
  const body     = skillContent.replace(/^---[\s\S]*?---\s*/, '');
  const filtered = body.split('\n').reduce((acc, line) => {
    const tableRow = line.match(/^\|\s*\*\*(\S+?)\*\*\s*\|/);
    if (tableRow) {
      if (tableRow[1] === modeLabel) acc.push(line);
      return acc;
    }
    const example = line.match(/^- (\S+?):\s/);
    if (example) {
      if (example[1] === modeLabel) acc.push(line);
      return acc;
    }
    acc.push(line);
    return acc;
  }, []);
  output = 'CAVEMAN MODE ACTIVE — level: ' + modeLabel + '\n\n' + filtered.join('\n');
} else {
  // Fallback — SKILL.md not found (project root detection failed, etc.)
  output =
    'CAVEMAN MODE ACTIVE — level: ' + modeLabel + '\n\n' +
    'Respond terse like smart caveman. All technical substance stay. Only fluff die.\n\n' +
    '## Persistence\n\n' +
    'ACTIVE EVERY RESPONSE. No revert after many turns. No filler drift. Still active if unsure. ' +
    'Off only: "stop caveman" / "normal mode".\n\n' +
    'Current level: **' + modeLabel + '**. Switch: `/caveman lite|full|ultra`.\n\n' +
    '## Rules\n\n' +
    'Drop: articles (a/an/the), filler (just/really/basically/actually/simply), ' +
    'pleasantries (sure/certainly/of course/happy to), hedging. ' +
    'Fragments OK. Short synonyms. Technical terms exact. Code blocks unchanged. Errors quoted exact.\n\n' +
    'Pattern: `[thing] [action] [reason]. [next step].`\n\n' +
    'Not: "Sure! I\'d be happy to help you with that."\n' +
    'Yes: "Bug in auth middleware. Token expiry check use `<` not `<=`. Fix:"\n\n' +
    '## Auto-Clarity\n\n' +
    'Drop caveman for: security warnings, irreversible action confirmations, user confused. ' +
    'Resume after.\n\n' +
    '## Boundaries\n\n' +
    'Code/commits/PRs: write normal. "stop caveman" or "normal mode": revert. ' +
    'Level persist until changed or session end.';
}

// Statusline nudge — append if statusLine not yet configured in ~/.copilot/settings.json
try {
  let hasStatusline = false;
  if (fs.existsSync(settingsPath)) {
    const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    if (settings.statusLine) hasStatusline = true;
  }
  if (!hasStatusline) {
    const isWindows  = process.platform === 'win32';
    const scriptName = isWindows ? 'copilot-statusline.ps1' : 'copilot-statusline.sh';
    const scriptPath = path.join(projectDir, 'hooks', scriptName);
    const command    = isWindows
      ? `powershell -ExecutionPolicy Bypass -File "${scriptPath}"`
      : `bash "${scriptPath}"`;
    output +=
      '\n\nSTATUSLINE SETUP NEEDED: The caveman hooks include a statusline badge showing active mode ' +
      '(e.g. [CAVEMAN], [CAVEMAN:ULTRA]). It is not configured yet. ' +
      'To enable, add this to ' + settingsPath + ': ' +
      '"statusLine": { "type": "command", "command": ' + JSON.stringify(command) + ' } ' +
      'Proactively offer to set this up for the user on first interaction.';
  }
} catch (_) { /* silent fail — never block session start */ }

process.stdout.write(JSON.stringify({ additionalContext: output }));
