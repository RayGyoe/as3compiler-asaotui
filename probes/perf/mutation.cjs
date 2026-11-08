// Prove the memo probe fails when an unchanged subtree is rebuilt.
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');
const file = path.join(UI, 'kit/asaot/ui/View.as');
const find = 'if (entry != null && entry[0] === version) return entry[1] as Node;';
const replace = 'if (false && entry != null && entry[0] === version) return entry[1] as Node;';
const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
function probe() {
  return spawnSync(process.execPath, ['tools/probe.cjs', 'probes/perf'], { cwd: UI, encoding: 'utf8' });
}
const log = [];
function line(s) { console.log(s); log.push(s); }
const base = probe();
const baseOut = (base.stdout || '') + (base.stderr || '');
if (!/RESULT: PASS/.test(baseOut)) {
  line('baseline is not green; aborting');
  line(baseOut);
  fs.writeFileSync(path.join(DIR, 'perf-mutation.txt'), log.join('\n') + '\n');
  process.exit(1);
}
line('baseline: PASS');
const before = fs.readFileSync(file, 'utf8');
const hash = sha(file);
let ok = false;
try {
  if (!before.includes(find)) throw new Error('memo mutation anchor not found');
  fs.writeFileSync(file, before.replace(find, replace));
  const r = probe();
  const out = (r.stdout || '') + (r.stderr || '');
  ok = /RESULT: FAIL/.test(out) && out.includes('memo rebuilt an unchanged subtree') && !/BUILD FAILED/.test(out);
  line('M1 ' + (ok ? 'CAUGHT' : 'MISSED') + ': disable memo hits');
  if (!ok) line(out);
} finally {
  fs.writeFileSync(file, before);
}
const restored = sha(file) === hash;
line('M1 restore: ' + (restored ? 'byte-identical' : 'HASH MISMATCH'));

const rfile = path.join(UI, 'kit/asaot/ui/Reconciler.as');
const rfind = 'if (old != null && desc.memoRoot && old.desc === desc && !old.lastStyleStale) return old;';
const rreplace = 'if (false && old != null && desc.memoRoot && old.desc === desc && !old.lastStyleStale) return old;';
const rbefore = fs.readFileSync(rfile, 'utf8');
const rhash = sha(rfile);
let ok2 = false;
try {
  if (!rbefore.includes(rfind)) throw new Error('same-description mutation anchor not found');
  fs.writeFileSync(rfile, rbefore.replace(rfind, rreplace));
  const r = probe();
  const out = (r.stdout || '') + (r.stderr || '');
  ok2 = /RESULT: FAIL/.test(out) && out.includes('memo reconcile walked an unchanged subtree')
    && !/BUILD FAILED/.test(out);
  line('M2 ' + (ok2 ? 'CAUGHT' : 'MISSED') + ': walk an unchanged memo subtree');
  if (!ok2) line(out);
} finally {
  fs.writeFileSync(rfile, rbefore);
}
const restored2 = sha(rfile) === rhash;
line('M2 restore: ' + (restored2 ? 'byte-identical' : 'HASH MISMATCH'));
line(ok && restored && ok2 && restored2 ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(path.join(DIR, 'perf-mutation.txt'), log.join('\n') + '\n');
process.exit(ok && restored && ok2 && restored2 ? 0 : 1);
