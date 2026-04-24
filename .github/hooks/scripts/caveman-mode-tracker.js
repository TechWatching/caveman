#!/usr/bin/env node
// caveman — Copilot CLI userPromptSubmitted hook (cross-platform)
//
// Detects /caveman commands and natural-language activation/deactivation.
// Writes mode to flag file at ~/.copilot/.caveman-active.
//
// NOTE: Copilot CLI does not yet inject userPromptSubmitted hook output into
// the conversation. The flag write keeps the statusline badge in sync.
// Per-turn reinforcement is stubbed — upgrade to emit {"additionalContext": ...}
// when Copilot adds output support for this hook event.

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

const copilotDir = path.join(os.homedir(), '.copilot');
const flagPath   = path.join(copilotDir, '.caveman-active');

// ── Mode resolution ──────────────────────────────────────────────────────────

function getDefaultMode() {
  const env = (process.env.CAVEMAN_DEFAULT_MODE || '').toLowerCase();
  if (VALID_MODES.includes(env)) return env;

  try {
    const xdg = process.env.XDG_CONFIG_HOME ||
                (process.platform === 'win32'
                  ? (process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'))
                  : path.join(os.homedir(), '.config'));
    const configPath = path.join(xdg, 'caveman', 'config.json');
    const cfg = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    const m   = (cfg.defaultMode || '').toLowerCase();
    if (VALID_MODES.includes(m)) return m;
  } catch (_) {}

  return 'full';
}

// ── Symlink-safe flag write ──────────────────────────────────────────────────

function safeWriteFlag(p, content) {
  try {
    const dir = path.dirname(p);
    fs.mkdirSync(dir, { recursive: true });

    try { if (fs.lstatSync(dir).isSymbolicLink()) return; } catch (_) { return; }
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
  } catch (_) { /* silent fail */ }
}

// ── Main ─────────────────────────────────────────────────────────────────────

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const data   = JSON.parse(input);
    const prompt = (data.prompt || '').trim().toLowerCase();

    if (!prompt) process.exit(0);

    // Natural-language activation
    if (
      /\b(activate|enable|turn on|start|talk like)\b.*\bcaveman\b/i.test(prompt) ||
      /\bcaveman\b.*\b(mode|activate|enable|turn on|start)\b/i.test(prompt)
    ) {
      if (!/\b(stop|disable|turn off|deactivate)\b/i.test(prompt)) {
        const mode = getDefaultMode();
        if (mode !== 'off') safeWriteFlag(flagPath, mode);
      }
    }

    // /caveman slash commands
    if (prompt.startsWith('/caveman')) {
      const parts = prompt.split(/\s+/);
      const cmd   = parts[0];
      const arg   = parts[1] || '';
      let mode    = null;

      if (cmd === '/caveman-commit') {
        mode = 'commit';
      } else if (cmd === '/caveman-review') {
        mode = 'review';
      } else if (cmd === '/caveman-compress' || cmd === '/caveman:caveman-compress') {
        mode = 'compress';
      } else if (cmd === '/caveman' || cmd === '/caveman:caveman') {
        if (arg === 'lite')                         mode = 'lite';
        else if (arg === 'ultra')                   mode = 'ultra';
        else if (arg === 'wenyan-lite')             mode = 'wenyan-lite';
        else if (arg === 'wenyan' || arg === 'wenyan-full') mode = 'wenyan';
        else if (arg === 'wenyan-ultra')            mode = 'wenyan-ultra';
        else                                        mode = getDefaultMode();
      }

      if (mode && mode !== 'off') {
        safeWriteFlag(flagPath, mode);
      } else if (mode === 'off') {
        try { fs.unlinkSync(flagPath); } catch (_) {}
      }
    }

    // Natural-language deactivation
    if (
      /\b(stop|disable|deactivate|turn off)\b.*\bcaveman\b/i.test(prompt) ||
      /\bcaveman\b.*\b(stop|disable|deactivate|turn off)\b/i.test(prompt) ||
      /\bnormal mode\b/i.test(prompt)
    ) {
      try { fs.unlinkSync(flagPath); } catch (_) {}
    }

    // NOTE: Per-turn reinforcement stub.
    // When Copilot adds output support for userPromptSubmitted, emit:
    //   {"additionalContext": "CAVEMAN MODE ACTIVE (...). Drop articles/filler/..."}
    // Read flag here and write JSON to stdout. For now exit cleanly.
  } catch (_) {
    // Silent fail
  }
});
