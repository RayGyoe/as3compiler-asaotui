// probes/widgets/i18n/mutation.cjs -- proves probes/widgets/i18n CAN go red.
//
// Every mutation is one CONTRACT, not one bug: each removes exactly the mechanism
// whose absence the probe is supposed to see, so a green run after a mutation would
// mean the probe is measuring nothing.
//
//   M1 UiApp ignores the locale epoch        -> setLocale() changes nothing on screen
//                                               until something else happens to dirty
//                                               the tree (the "it works if you resize
//                                               the window" class of i18n bug)
//   M2 the fallback chain stops at the tag    -> "zh-Hant-TW" never reaches "zh-Hant"
//                                               or "zh", so a sub-tag renders the
//                                               DEFAULT language: an app that ships a
//                                               regional catalog ships nothing
//   M3 View.memo ignores the epoch            -> the memoized subtree keeps the
//                                               language it was BUILT in, and only
//                                               the cached part of a real app is
//                                               wrong -- the hardest kind to notice
//   M4 the layout direction is a constant     -> the locale can change but the rows
//                                               never mirror, so an RTL locale gets
//                                               RTL text in an LTR layout
//
// Each mutated file is restored in `finally` and its sha256 compared byte-for-byte
// with the pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/i18n/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');
const PROBE = 'probes/widgets/i18n';
const RESULTS = path.join(DIR, 'i18n-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'UIAPP IGNORES THE LOCALE EPOCH: setLocale() moves the catalog but no frame '
      + 'notices, so the window keeps the old language until an unrelated resize or '
      + 'click happens to dirty the tree',
    find: '            if (I18n.epoch() != this._i18nEpoch)',
    replace: '            if (false && I18n.epoch() != this._i18nEpoch)',
    expect: "the select hint is still"
  },
  {
    id: 'M2',
    file: 'kit/asaot/ui/I18n.as',
    why: 'THE FALLBACK CHAIN STOPS AT THE EXACT TAG: "zh-Hant-TW" no longer reaches '
      + '"zh-Hant" or "zh", so every regional sub-tag silently renders the default '
      + 'language while looking configured',
    find: '                var d:int = lastDash(t);\n'
      + '                if (d < 0) return;\n'
      + '                t = t.substring(0, d);',
    replace: '                break;   // (mutation) stop at the exact tag',
    expect: 'a sub-tag did not fall back to its parent'
  },
  {
    id: 'M3',
    file: 'kit/asaot/ui/View.as',
    why: 'VIEW.MEMO IGNORES THE EPOCH: the version string is unchanged across a locale '
      + 'switch, so the cached subtree is served in the language it was built in -- the '
      + 'cache is silently WRONG, not merely stale',
    find: '            if (entry != null && entry[0] === version && entry[1] === epoch)',
    replace: '            if (entry != null && entry[0] === version)',
    expect: 'the memoized text kept'
  },
  {
    id: 'M4',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'THE LAYOUT DIRECTION IS A CONSTANT: the locale may be RTL, but every solve '
      + 'still passes DIR_LTR, so the text flips and the layout does not',
    find: '                I18n.isRTL() ? LayoutConstants.DIR_RTL : LayoutConstants.DIR_LTR);',
    replace: '                LayoutConstants.DIR_LTR);   // (mutation) constant direction',
    expect: 'under RTL b1 is at'
  }
];

function runProbe() {
  return spawnSync(process.execPath, ['tools/probe.cjs', PROBE], { cwd: UI, encoding: 'utf8' });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

const base = runProbe();
const baseOut = (base.stdout || '') + (base.stderr || '');
const baseVerdict = /RESULT: (PASS|FAIL)/.exec(baseOut);
line('baseline (unmutated): ' + (baseVerdict ? baseVerdict[0] : 'NO VERDICT -- build failure?'));

if (!baseVerdict || baseVerdict[1] !== 'PASS') {
  line('the baseline is not green; a mutation run would be meaningless. Aborting.');
  line('--- baseline output (tail) ---');
  for (const l of baseOut.split(/\r?\n/).slice(-25)) line('  ' + l);
  fs.writeFileSync(RESULTS, log.join('\n') + '\n');
  process.exit(1);
}
line('');

for (const m of MUTATIONS) {
  const file = path.join(UI, m.file);
  const before = fs.readFileSync(file, 'utf8');
  const beforeHash = sha(file);
  if (before.indexOf(m.find) < 0) {
    line(m.id + '  SKIPPED -- anchor text not found in ' + m.file
      + ' (the file drifted; fix the mutation, do not ignore it)');
    broken++;
    continue;
  }
  try {
    fs.writeFileSync(file, before.split(m.find).join(m.replace));
    const r = runProbe();
    const out = (r.stdout || '') + (r.stderr || '');
    const verdict = /RESULT: (PASS|FAIL)/.exec(out);
    const saidIt = out.indexOf(m.expect) >= 0;
    const buildFailed = /BUILD FAILED/.test(out);
    const timedOut = /TIMEOUT/.test(out);
    const ok = verdict != null && verdict[1] === 'FAIL' && saidIt && !buildFailed;
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why);
    line('     verdict: ' + (verdict ? verdict[0] : 'none')
      + (buildFailed ? '  BUILD FAILED -- a mutation that does not compile proves nothing' : '')
      + (timedOut ? '  TIMEOUT -- the program never reached its verdict' : '')
      + (saidIt ? '' : '  MISSING the expected failure line "' + m.expect + '"'));
    const fails = out.split(/\r?\n/).filter((l) => /  FAIL  /.test(l));
    for (const f of fails.slice(0, 4)) line('     ' + f.trim());
    if (fails.length > 4) line('     ... and ' + (fails.length - 4) + ' more');
  } finally {
    fs.writeFileSync(file, before);
  }
  const afterHash = sha(file);
  line('     restore: ' + (afterHash === beforeHash
    ? 'byte-identical (' + afterHash.slice(0, 16) + ')'
    : 'MISMATCH ' + beforeHash.slice(0, 16) + ' -> ' + afterHash.slice(0, 16) + '  THIS IS BAD'));
  if (afterHash !== beforeHash) broken++;
}

line('');
line('MUTATION i18n: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
