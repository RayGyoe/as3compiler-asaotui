// probes/widgets/touch-scroll/mutation.cjs -- proves probes/widgets/touch-scroll CAN go
// red on the round that added touch drag + momentum (MOBILE.md S1/S2).
//
// Every mutation is one CONTRACT, not one bug: each removes exactly the mechanism whose
// absence the probe is supposed to see, so a green run after a mutation would mean the
// probe is measuring nothing.
//
//   M1 the drag moves the content by half           -> the finger and the content do not
//                                                       stay together (1:1 is the whole
//                                                       contract)
//   M2 the drag moves the content the wrong way     -> the list scrolls against the finger
//   M3 the press is not withdrawn when a drag starts-> the row stays painted pressed while
//                                                       its list scrolls, the most reported
//                                                       mobile glitch
//   M4 momentum is ignored for every viewport       -> `momentum:false` becomes a lie and a
//                                                       fling never coasts
//   M5 momentum is forced on for every viewport     -> the form whose list must stop dead
//                                                       coasts under the finger
//   M6 the axis is never locked                     -> a horizontal swipe nudges a vertical
//                                                       list by its (small) vertical part
//   M7 a drag past the end is not clamped          -> the view lands outside its content
//   M8 a programmatic scroll does not cancel the coast -> "back to top" fights the glide and
//                                                       drifts back down
//   M9 the drag is anchored at touch-down           -> the 8pt of slop that proved "this is
//                                                       a drag" also scrolls, so a wobbling
//                                                       tap jumps the list
//
// Each mutated file is restored in `finally` and its sha256 compared byte-for-byte with
// the pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/touch-scroll/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');
const PROBE = 'probes/widgets/touch-scroll';
const RESULTS = path.join(DIR, 'touch-scroll-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'THE DRAG MOVES THE CONTENT BY HALF: the finger and the content do not stay '
      + 'together, which is the whole contract of a 1:1 drag',
    find: '            var raw:Number = start - (pos - anchor);',
    replace: '            var raw:Number = (start - (pos - anchor)) * 0.5;',
    expect: 'a 20pt drag moved the content to 10',
  },
  {
    id: 'M2',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'THE DRAG MOVES THE CONTENT THE WRONG WAY: the list scrolls against the finger',
    find: '            var raw:Number = start - (pos - anchor);',
    replace: '            var raw:Number = start + (pos - anchor);',
    expect: 'a 20pt drag moved the content to 0',
  },
  {
    id: 'M9',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'THE DRAG IS ANCHORED AT TOUCH-DOWN: the 8pt of motion that proved "this is a '
      + 'drag" also scrolls, so a tap that wobbles jumps the list',
    find: '            n.extra[TD_X] = x;\n            n.extra[TD_Y] = y;',
    replace: '            n.extra[TD_X] = originX;\n            n.extra[TD_Y] = originY;',
    expect: 'a 20pt drag moved the content to 40',
  },
  {
    id: 'M3',
    file: 'kit/asaot/ui/PointerRouter.as',
    why: 'THE PRESS IS NOT WITHDRAWN WHEN A DRAG STARTS: the row stays painted pressed '
      + 'while its list scrolls',
    find: '                if (p.node != null) this.app.dispatchPointerMouse(MouseEvent.MOUSE_UP, p.node, p.x, p.y);\n                this.press = null;',
    replace: '                this.press = null;\n                // (mutation) the visual press is left on the row',
    expect: 'the row stayed pressed after the drag took over',
  },
  {
    id: 'M4',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'MOMENTUM IS IGNORED FOR EVERY VIEWPORT: `momentum:false` becomes a lie and a '
      + 'fling never coasts',
    find: '            if (!sv.momentum) return;',
    replace: '            if (true) return;',
    expect: 'the release did not coast',
  },
  {
    id: 'M5',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'MOMENTUM IS FORCED ON FOR EVERY VIEWPORT: the list an author asked to stop dead '
      + 'coasts under the finger',
    find: '            if (!sv.momentum) return;',
    replace: '            if (false) return;',
    expect: 'the momentum:false list coasted to',
  },
  {
    id: 'M6',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'THE AXIS IS NEVER LOCKED: a horizontal swipe nudges a vertical list by its '
      + '(small) vertical part instead of being consumed',
    find: '                if (ady >= adx) axis = (Number(n.extra[MAX_Y]) > 0) ? 1 : -1;\n                else axis = (Number(n.extra[MAX_X]) > 0) ? 2 : -1;',
    replace: '                axis = (Number(n.extra[MAX_Y]) > 0) ? 1 : -1;',
    expect: 'a horizontal swipe moved the vertical list',
  },
  {
    id: 'M7',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'A DRAG PAST THE END IS NOT CLAMPED: the view leaves its content and the rest of '
      + 'the frame shows blank space',
    find: '            if (off > maxOff) off = maxOff;',
    replace: '            // (mutation) no upper clamp',
    expect: 'a drag past the end landed at',
  },
  {
    id: 'M8',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'A PROGRAMMATIC SCROLL DOES NOT CANCEL THE COAST: "back to top" is written, then '
      + 'the glide adds its own motion on top and the view drifts back down',
    find: '            if (requested(n, REQ_Y, LIVE_Y, sv.offsetY))\n            {\n                this.stopGlide(n);',
    replace: '            if (requested(n, REQ_Y, LIVE_Y, sv.offsetY))\n            {',
    expect: 'a programmatic scroll did not cancel the glide',
  },
  {
    id: 'M10',
    file: 'kit/asaot/ui/PointerRouter.as',
    why: 'A FINGER LANDING DOES NOT STOP A COAST: the press is recorded but the viewport is '
      + 'never told, so the list keeps sliding under a finger that is already down',
    find: '                    var ts:TouchScrollable = this.scrollableOf(sv);\n                    if (ts != null) ts.touchPress(sv);',
    replace: '                    // (mutation) the coast is left running',
    expect: 'a finger on a coasting list did not stop it',
  },
  {
    id: 'M11',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'THE STRETCH IS NOT DAMPED: a hard drag pulls the content 220px off its own end instead of the '
      + 'damped ~40px the rubber-band curve gives',
    find: '                over = dampOver(raw - clampTo(raw, maxOff), limit);',
    replace: '                over = raw - clampTo(raw, maxOff);',
    expect: 'want ~40 (damped',
  },
  {
    id: 'M12',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'A RELEASE WHILE STRETCHED DOES NOT SPRING BACK: the pane stays past its end until something else '
      + 'moves it (S3 without the return half)',
    find: '                n.extra[(axis == 1) ? SPRING_Y : SPRING_X] = 1;',
    replace: '                n.extra[(axis == 1) ? SPRING_Y : SPRING_X] = 0;',
    expect: 'the pane did not return to the end',
  },
  {
    id: 'M13',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'THE STRETCH NEVER REACHES THE PIXELS: the offset is tracked and published, but the clip is drawn '
      + 'at the clamped position, so nothing moves on screen',
    find: '            var vy:Number = oy + overY;',
    replace: '            var vy:Number = oy;',
    expect: 'the bottom of the stretched pane is',
  },
  {
    id: 'M14',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: '`overscroll: "none"` IS IGNORED: a pane whose author said it must not move bounces anyway, which '
      + 'is the form-list bug the mode exists to prevent',
    find: '            if (sv0.overscroll == "rubber")',
    replace: '            if (true)',
    expect: "overscroll:'none' still stretched by",
  },
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
line('MUTATION touch-scroll: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
