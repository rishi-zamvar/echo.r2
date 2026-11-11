// Merge/unmerge Echo hub http hooks in Claude settings.json. Contract shared with install.ps1.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { loadConfig } from '../auth.js';
import { save } from '../store.js';

const MARK = '/hook/ext/';
const EVENTS = ['Stop', 'Notification'];
const marked = (g) => (g.hooks || []).some((h) => typeof h.url === 'string' && h.url.includes(MARK));

export function merge(settings, url) {
  settings.hooks ??= {};
  for (const ev of EVENTS) {
    const arr = (settings.hooks[ev] ??= []).filter((g) => !marked(g));
    arr.push({ hooks: [{ type: 'http', url, timeout: 3 }] });
    settings.hooks[ev] = arr;
  }
  return settings;
}

export function unmerge(settings) {
  if (!settings.hooks) return settings;
  for (const ev of EVENTS) {
    if (!Array.isArray(settings.hooks[ev])) continue;
    settings.hooks[ev] = settings.hooks[ev].filter((g) => !marked(g));
    if (!settings.hooks[ev].length) delete settings.hooks[ev];
  }
  if (!Object.keys(settings.hooks).length) delete settings.hooks;
  return settings;
}

function cli(action, file) {
  file ||= path.join(process.env.ECHO_CLAUDE_HOME || path.join(os.homedir(), '.claude'), 'settings.json');
  let raw = null, settings = {};
  if (fs.existsSync(file)) {
    raw = fs.readFileSync(file);
    try { settings = JSON.parse(raw.toString('utf8')); } catch { throw new Error(`cannot parse ${file}; not modified`); }
  } else if (action === 'unmerge') return;
  if (action === 'merge') {
    const dataDir = process.env.ECHO_DATA_DIR || path.join(os.homedir(), '.echo-hub');
    const url = `http://127.0.0.1:${process.env.ECHO_HOOK_PORT || 8791}${MARK}${loadConfig(dataDir).hookSecret}`;
    merge(settings, url);
  } else unmerge(settings);
  if (raw && !fs.existsSync(file + '.echo-bak')) fs.writeFileSync(file + '.echo-bak', raw, { mode: 0o600 });
  save(file, settings, { mode: 0o600 });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [action, file] = process.argv.slice(2);
  try {
    if (!['merge', 'unmerge'].includes(action)) throw new Error('usage: hooks-merge.js merge|unmerge [settingsPath]');
    cli(action, file);
  } catch (e) { console.error(`hooks-merge: ${e.message}`); process.exit(1); }
}
