import fs from 'node:fs';
import path from 'node:path';

export function load(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}

export function save(file, obj, { mode } = {}) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file + '.tmp', JSON.stringify(obj, null, 2), mode ? { mode } : undefined);
  if (mode) fs.chmodSync(file + '.tmp', mode);
  fs.renameSync(file + '.tmp', file);
}
