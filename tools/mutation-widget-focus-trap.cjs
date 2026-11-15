#!/usr/bin/env node
// mutation-widget-focus-trap -- does the opt-in modal focus gate have teeth?
//
// Proves probes/widgets/focus-trap catches: auto-focus removed, restore removed,
// restore-to-null instead of the remembered node, the Tab trap disengaged, and a
// dialog trapping even when the author did not opt in.
//
// Usage: node tools/mutation-widget-focus-trap.cjs   (writes reviews/mutation-widget-focus-trap.txt)
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '..');
const PROBE = 'probes/widgets/focus-trap';
const LOG = path.join(ROOT, 'reviews', 'mutation-widget-focus-trap.txt');

const FILES = ['kit/asaot/ui/kind/PanelShellWidget.as', 'kit/asaot/ui/UiApp.as', 'kit/asaot/ui/kind/DialogWidget.as'];
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
  const r = spawnSync(process.execPath, ['tools/probe.cjs', PROBE], { cwd: ROOT, env, encoding: 'utf8', timeout: 240000, maxBuffer: 32 * 1024 * 1024 });
  return { out: (r.stdout || '') + '\n' + (r.stderr || ''), pass: /RESULT: PASS/.test(r.stdout || '') && r.status === 0 };
}

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the open path never calls focusFirstWithin -> a trapping dialog does not auto-focus its first stop',
    apply() {
      patch('kit/asaot/ui/kind/PanelShellWidget.as',
        '                    n.extra[TRAP_KEY] = 1;\n                    n.app.focusFirstWithin(n);',
        '                    n.extra[TRAP_KEY] = 1;');
    },
  },
  {
    id: 'M2',
    why: 'releaseFocus is a no-op -> closing a trapping dialog never restores the pre-open focus',
    apply() {
      patch('kit/asaot/ui/kind/PanelShellWidget.as',
        '            if (Number(n.extra[TRAP_KEY]) == 0) return;',
        '            return;');
    },
  },
  {
    id: 'M3',
    why: 'releaseFocus clears to null instead of the remembered node -> restore lands on (none), not bg',
    apply() {
      patch('kit/asaot/ui/kind/PanelShellWidget.as',
        '            if (prev != null && prev.app == n.app && !prev.inert() && prev.visible) n.app.focusNode(prev);\n            else n.app.focusNode(null);',
        '            n.app.focusNode(null);');
    },
  },
  {
    id: 'M4',
    why: 'the Tab trap condition is disabled -> Tab escapes the dialog to the page behind',
    apply() {
      patch('kit/asaot/ui/UiApp.as',
        '            if (this._focus != null && inTree(this.overlayRoot, this._focus))',
        '            if (false)');
    },
  },
  {
    id: 'M5',
    why: 'DialogWidget traps regardless of the author opt-in -> a focusTrap:false dialog steals focus',
    apply() {
      patch('kit/asaot/ui/kind/DialogWidget.as',
        '            return DialogNode(desc).focusTrap;',
        '            return true;');
    },
  },
];

function main() {
  const lines = [];
  const say = (s) => { lines.push(s); console.log(s); };
  say('# mutation-widget-focus-trap -- teeth for the opt-in modal focus gate');
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
    say(`MUTATION focus-trap: ${caught}/${MUTATIONS.length} caught, ${problems} problem(s)`);
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