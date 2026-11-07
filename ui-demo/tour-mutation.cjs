// ui-demo/tour-mutation.cjs -- does the GALLERY TOUR actually catch the defects it
// claims to pin?
//
// Each mutation reintroduces one of the three fixes (nav centring, panel body wrapping,
// prose measurement) and the tour must report FAIL naming it. Every file is restored
// byte for byte and verified with sha256 -- a mutation that leaves a stale byte behind
// corrupts the very evidence this file produces.
//
// USAGE (from asaotui/): node ui-demo/tour-mutation.cjs
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = __dirname;                 // ui-demo/, the run-gallery.cjs dir

const MUTATIONS = [
  {
    id: 'M1 nav label carries the row height',
    file: 'ui-demo/demo/DocsStyle.as',
    find: 'size: [Length.pct(1), null],\n            text: { fontSize: 13, fontWeight: "bold", color: 0x1D4ED8 }',
    replace: 'size: [Length.pct(1), Length.px(NAV_H_ITEM)],\n            text: { fontSize: 13, fontWeight: "bold", color: 0x1D4ED8 }',
    expect: 'the index label sits at y+',
  },
  {
    id: 'M2 dialog body loses its point width',
    file: 'ui-demo/demo/DocsView.as',
    find: '                size: [inner, null],\n                text: { fontSize: size, color: color, whiteSpace: "normal" } }) });',
    replace: '                size: [null, null],\n                text: { fontSize: size, color: color } }) });',
    expect: 'the dialog body is',
  },
  {
    id: 'M3 dialog body loses whiteSpace normal',
    file: 'ui-demo/demo/DocsView.as',
    find: 'text: { fontSize: size, color: color, whiteSpace: "normal" } }) });',
    replace: 'text: { fontSize: size, color: color } }) });',
    expect: 'the dialog body paints',
  },
  {
    id: 'M4 DocsWrap measures with the default face',
    file: 'ui-demo/demo/DocsWrap.as',
    find: '            scratch.text = s;\n            scratch.setTextFormat(PaintKit.formatFor(style));',
    replace: '            scratch.setTextFormat(PaintKit.formatFor(style));\n            scratch.text = s;',
    expect: 'prose line painting wider than its box',
  },
  {
    id: 'M5 live row loses its horizontal padding',
    // Edges.fromArray reads the 2-element form as [horizontal, vertical], so the row that
    // was written [0, 14] got 14pt of VERTICAL padding and none horizontally -- invisible
    // until the numeric column started really right-aligning, at which point the digits
    // ended exactly on the scrollView's overlay track.
    file: 'ui-demo/demo/DocsLive.as',
    find: [
      '                flexDirection: "row", alignItems: "center", gap: 12,',
      '                size: [Length.pct(1), Length.px(ROW_H)], padding: [14, 0],',
    ].join('\n'),
    replace: [
      '                flexDirection: "row", alignItems: "center", gap: 12,',
      '                size: [Length.pct(1), Length.px(ROW_H)], padding: [0, 14],',
    ].join('\n'),
    expect: 'under the scroll bar that starts at',
  },
];

function sha(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex').slice(0, 16);
}

function runTour() {
  const r = spawnSync(process.execPath, ['run-gallery.cjs'], {
    cwd: UI, encoding: 'utf8', timeout: 900000,
    env: Object.assign({}, process.env, { ASC_NO_OPEN: '1' }),
  });
  const out = (r.stdout || '') + (r.stderr || '');
  const tourPath = path.join(UI, 'air-gallery', 'gallery.txt');
  const tour = fs.existsSync(tourPath) ? fs.readFileSync(tourPath, 'utf8') : '';
  const verdict = /RESULT: (PASS|FAIL)/.exec(out);
  const problems = /verdict ----\nFAIL ([\s\S]*?)\n\[gallery\] RESULT/.exec(out);
  return {
    ok: verdict != null && verdict[1] === 'PASS',
    verdict: verdict == null ? 'NO VERDICT' : verdict[1],
    why: problems == null ? '' : problems[1].trim(),
    tour,
  };
}

const before = {};
for (const m of MUTATIONS) if (!(m.file in before)) before[m.file] = sha(m.file);

const lines = [];
let caught = 0, survived = 0;

lines.push('baseline...');
{
  const b = runTour();
  lines.push('baseline: ' + b.verdict + (b.ok ? '' : ' -- ' + b.why));
  if (!b.ok) {
    console.log(lines.join('\n'));
    console.error('the UNAMBIGUOUS state is not green; mutations prove nothing');
    process.exit(1);
  }
}

for (const m of MUTATIONS) {
  const original = fs.readFileSync(m.file, 'utf8');
  if (original.indexOf(m.find) < 0) {
    lines.push(m.id + ': ANCHOR MISSING -- mutation not applied');
    survived++;
    continue;
  }
  try {
    fs.writeFileSync(m.file, original.replace(m.find, m.replace));
    const r = runTour();
    const hit = r.verdict === 'FAIL' && r.why.indexOf(m.expect) >= 0;
    if (hit) caught++;
    else survived++;
    lines.push(m.id + ': ' + (hit ? 'CAUGHT' : 'SURVIVED')
      + '  [' + r.verdict + '] ' + (r.why || '(no named problem)'));
  } finally {
    fs.writeFileSync(m.file, original);
  }
}

// restore proof
lines.push('');
for (const f of Object.keys(before)) {
  const now = sha(f);
  lines.push((now === before[f] ? 'restore ok   ' : 'RESTORE BROKEN ') + f + '  ' + now
    + (now === before[f] ? '' : ' (was ' + before[f] + ')'));
}
lines.push('');
lines.push('final baseline (the artifacts left in air-gallery must be the REAL ones):');
{
  const f = runTour();
  lines.push('final: ' + f.verdict + (f.ok ? '' : ' -- ' + f.why));
  if (!f.ok) survived++;
}
lines.push('');
lines.push(caught + ' CAUGHT / ' + survived + ' survived  of ' + MUTATIONS.length);

const txt = lines.join('\n') + '\n';
fs.writeFileSync(path.join(__dirname, 'tour-mutation.txt'), txt);
console.log(txt);
if (survived > 0 || lines.some((l) => l.indexOf('RESTORE BROKEN') >= 0)) process.exit(1);