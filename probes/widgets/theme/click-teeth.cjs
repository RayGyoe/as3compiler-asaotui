'use strict';
// probes/widgets/theme/click-teeth.cjs -- does PHASE 3 of this probe have teeth?
//
// Phase 3 is the swap a user actually triggers: the probe goes back to light, then
// dispatches a REAL click on the author-coloured box, whose onClick calls
// Theme.setTheme(ThemeTokens.dark()). That path matters because it rebuilds static
// StyleRefinement pointers while the app is inside an event dispatch -- and it is the
// path every real app (and the docs page) uses.
//
// The check: point that handler at the palette it is ALREADY on, so the click fires but
// cannot change anything. The probe must go red on those 12 points. Restores the source
// byte-identically (sha256 verified) in `finally`, even when the run throws.
//
// USAGE (from asaotui/):  node probes/widgets/theme/click-teeth.cjs
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const UI = path.resolve(__dirname, '..', '..', '..');
const MAIN = path.join(__dirname, 'Main.as');
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
const before = fs.readFileSync(MAIN);
const from = 'function clickToDark():void { Theme.setTheme(ThemeTokens.dark()); }';
const to = 'function clickToDark():void { Theme.setTheme(ThemeTokens.light()); }';
if (before.toString('utf8').indexOf(from) < 0) throw new Error('anchor missing in Main.as');

let out = '';
try {
  fs.writeFileSync(MAIN, Buffer.from(before.toString('utf8').replace(from, to), 'utf8'));
  try {
    out = execFileSync(process.execPath, [path.join(UI, 'tools', 'probe.cjs'), 'probes/widgets/theme'],
      { cwd: UI, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) { out = String(e.stdout || '') + String(e.stderr || ''); }
} finally {
  fs.writeFileSync(MAIN, before);
}

const same = sha(fs.readFileSync(MAIN)) === sha(before);
console.log(out.split(/\r?\n/).filter((l) => /PROBE theme|RESULT|FAIL/.test(l)).join('\n'));
console.log('restore: ' + (same ? 'byte-identical' : 'CHANGED'));
const caught = /RESULT: FAIL/.test(out) && /the click did not reach|dark, driven by a click/.test(out);
console.log(caught ? 'RESULT: PASS (phase 3 has teeth)' : 'RESULT: FAIL (phase 3 is vacuous)');
process.exit(caught && same ? 0 : 1);