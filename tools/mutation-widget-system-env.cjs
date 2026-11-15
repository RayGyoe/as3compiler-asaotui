#!/usr/bin/env node
// mutation-widget-system-env -- teeth for the follow-the-system wiring (A2).
//
// Proves probes/widgets/system-env catches: the palette not following Env.isDark,
// Motion not following Env.reduceMotion, the follow guard removed (system drives
// even when off), and the env-change latch dropped (changes never fold).
//
// Usage: node tools/mutation-widget-system-env.cjs  (writes reviews/mutation-widget-system-env.txt)
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '..');
const PROBE = 'probes/widgets/system-env';
const LOG = path.join(ROOT, 'reviews', 'mutation-widget-system-env.txt');
const FILES = ['kit/asaot/ui/UiApp.as'];
const backup = new Map();
function sha(f) { return crypto.createHash('sha256').update(fs.readFileSync(path.join(ROOT, f))).digest('hex'); }
function save() { for (const f of FILES) backup.set(f, { buf: fs.readFileSync(path.join(ROOT, f)), hash: sha(f) }); }
function restore() { for (const [f, v] of backup) fs.writeFileSync(path.join(ROOT, f), v.buf); }
function verifyRestored() { const bad = FILES.filter(f => sha(f) !== backup.get(f).hash); if (bad.length) throw new Error('NOT byte-identical: ' + bad.join(', ')); }
function patch(rel, from, to) {
  const p = path.join(ROOT, rel);
  const s = fs.readFileSync(p, 'utf8');
  const n = s.split(from).length - 1;
  if (n !== 1) throw new Error(`anchor occurs ${n}x (want 1) in ${rel}: ${from.slice(0, 90)}`);
  fs.writeFileSync(p, s.replace(from, to));
}
function runProbe() {
  const env = { ...process.env };
  if (!env.ASC_COMPILER) env.ASC_COMPILER = path.resolve(ROOT, '../as3compiler');
  const r = spawnSync(process.execPath, ['tools/probe.cjs', PROBE], { windowsHide: true, cwd: ROOT, env, encoding: 'utf8', timeout: 240000, maxBuffer: 32 * 1024 * 1024 });
  return { out: (r.stdout || '') + '\n' + (r.stderr || ''), pass: /RESULT: PASS/.test(r.stdout || '') && r.status === 0 };
}

const MUTATIONS = [
  {
    id: 'M1',
    why: 'syncSystemEnv never applies the palette -> Env.isDark does not drive the theme',
    apply() { patch('kit/asaot/ui/UiApp.as', 'if (!Theme.isTheme(want)) Theme.setTheme(want);', 'if (false) Theme.setTheme(want);'); },
  },
  {
    id: 'M2',
    why: 'syncSystemEnv never wires Motion -> Env.reduceMotion does not drive the accessibility switch',
    apply() { patch('kit/asaot/ui/UiApp.as', 'Motion.reducedMotion = this.env.reduceMotion;', '/* motion wiring removed */'); },
  },
  {
    id: 'M3',
    why: 'the followSystem guard is removed -> the system drives theme/motion even when the author opted out',
    apply() { patch('kit/asaot/ui/UiApp.as', 'if (!this._followSystem || this.env == null) return;', 'if (this.env == null) return;'); },
  },
  {
    id: 'M4',
    why: 'envChanged drops the _sysDirty latch -> a system change is never folded at the frame boundary',
    apply() { patch('kit/asaot/ui/UiApp.as', '// frame boundary (syncSystemEnv), never inside the platform callback.\n            this._sysDirty = true;', '// frame boundary (syncSystemEnv), never inside the platform callback.'); },
  },
];

function main() {
  const lines = [];
  const say = (s) => { lines.push(s); console.log(s); };
  say('# mutation-widget-system-env -- teeth for the follow-the-system wiring');
  say('');
  save();
  let problems = 0;
  try {
    const base = runProbe();
    say('baseline ' + PROBE + ': ' + (base.out.match(/RESULT: (PASS|FAIL)/) || ['RESULT: ?'])[0] + '  (' + ((base.out.match(/(\d+) checks/) || [])[1] || '?') + ' checks)');
    if (!base.pass) { say('BASELINE IS RED -- fix the probe before mutating.'); problems++; }
    say('');
    let caught = 0;
    for (const m of MUTATIONS) {
      restore();
      m.apply();
      const r = runProbe();
      const died = !r.pass;
      if (died) caught++; else problems++;
      say(`${m.id}  ${died ? 'CAUGHT' : 'SURVIVED'}  ${m.why}`);
      const fail = r.out.split('\n').find(l => /FAIL /.test(l));
      if (fail) say('     ' + fail.trim().slice(0, 160));
      say('     verdict: ' + (r.out.match(/RESULT: (PASS|FAIL)/) || ['RESULT: ?'])[0]);
    }
    say('');
    say(`MUTATION system-env: ${caught}/${MUTATIONS.length} caught, ${problems} problem(s)`);
  } finally {
    restore();
    verifyRestored();
    say('all sources restored byte-identical (sha256 verified)');
  }
  say(problems === 0 ? 'RESULT: PASS' : 'RESULT: FAIL');
  fs.mkdirSync(path.dirname(LOG), { recursive: true });
  fs.writeFileSync(LOG, lines.join('\n') + '\n');
  process.exit(problems === 0 ? 0 : 1);
}
main();