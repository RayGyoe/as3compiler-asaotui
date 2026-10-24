// mutation-kind-coverage.cjs -- proves tools/kind-coverage.cjs has teeth.
//
// The gate certifies "every widget kind the kit registers is shown by the gallery
// demo". A scan like that fails in one direction only: it can say PASS on a demo
// that is missing a widget (exactly the state this tool was written to end -- six
// kinds had shipped while STATUS.md claimed one was missing). So every mutation
// here makes the DEMO the thing that is wrong, and the tool must notice, name the
// kind, and exit non-zero.
//
// M1 -- the tree call is renamed in the demo: the widget is still compiled (the kit
//       is untouched) but no page shows it. This is the everyday regression: a page
//       is rewritten and a control quietly leaves the demo.
// M2 -- a new kind + its factory appear in the kit and NOTHING in the demo uses
//       them. This is the regression that actually happened, twice. It is also the
//       only mutation that exercises kind->class->factory resolution: without it a
//       new widget would be invisible to the scan and the gate would stay green.
// M3 -- the tree call survives only inside a `//` comment. The first version of
//       this tool read comments as code and reported `tree` as SHOWN for exactly
//       this reason (the demo's prose says "the second tree (the page below ...").
//       A scan that certifies prose certifies nothing.
//
// No build here: the subject is source text, so a mutation only has to make the
// TEXT wrong. (M1/M3 would not compile, and that is fine -- the tool must answer
// for the text it is given.) Every mutation is restored byte-for-byte in `finally`
// and the sha256 is compared, so an interrupted run cannot leave a broken demo.
//
// Usage: node tools/mutation-kind-coverage.cjs
// Exit:  0 = every mutation was caught, 1 = at least one survived.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const VIEW = path.join(UI, 'ui-demo/demo/DocsData.as');
const NEW_NODE = path.join(UI, 'kit/asaot/ui/ShadowNode.as');
const NEW_FACT = path.join(UI, 'kit/asaot/ui/shadow.as');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
// --verbose so the verdict carries the `MISSING <kind>` row the mutations assert
// on; the exit code alone would not say WHICH widget left the demo.
const run = () => {
  const r = spawnSync(process.execPath, ['tools/kind-coverage.cjs', '--verbose'], { cwd: UI, encoding: 'utf8', maxBuffer: 1 << 24 });
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
};

const original = fs.readFileSync(VIEW, 'utf8');
const hash0 = sha(VIEW);
const base = run();
if (base.code !== 0) {
  console.error('[mutation] the baseline is not green -- nothing to mutate against:');
  console.error(base.out);
  process.exit(1);
}

const results = [];
function mutate(name, apply, expectKind) {
  let applied = false;
  try {
    apply();
    applied = true;
    const r = run();
    const named = r.out.includes(expectKind);
    const red = r.code !== 0;
    const pass = red && named && !/RESULT: PASS/.test(r.out);
    results.push({ name, pass, code: r.code });
    console.log((pass ? '[CAUGHT] ' : '[SURVIVED] ') + name + '  (exit ' + r.code + ', names "' + expectKind + '": ' + named + ')');
    if (!pass) console.log(r.out.split('\n').slice(-14).join('\n'));
  } finally {
    fs.writeFileSync(VIEW, original);
    for (const p of [NEW_NODE, NEW_FACT]) if (fs.existsSync(p)) fs.unlinkSync(p);
    const back = sha(VIEW) === hash0 && !fs.existsSync(NEW_NODE) && !fs.existsSync(NEW_FACT);
    if (!back) {
      console.error('[mutation] RESTORE FAILED for ' + name + ' -- the demo is no longer byte-identical');
      process.exit(2);
    }
    if (applied) {
      const r = run();
      if (r.code !== 0) {
        console.error('[mutation] the tool did not return to green after restoring ' + name);
        console.error(r.out);
        process.exit(2);
      }
    }
  }
}

// M1: rename the call. `tree(` appears once in the demo (DocsData.as, the tree page).
mutate('M1 tree call renamed in the demo', () => {
  if (!/\btree\s*\(/.test(original)) throw new Error('M1 pattern missing');
  fs.writeFileSync(VIEW, original.replace(/\btree\s*\(/, 'treeRenamed('));
}, 'MISSING  tree');

// M2: a new widget ships with no gallery entry. Both files are new, so the kit is
// otherwise untouched and the mutation is exactly "author forgot the demo".
mutate('M2 new kind registered, no gallery entry', () => {
  fs.writeFileSync(NEW_NODE, [
    'package asaot.ui',
    '{',
    '    public class ShadowNode',
    '    {',
    '        public function ShadowNode():void',
    '        {',
    '            Widgets.register("shadow", new ShadowNode());',
    '        }',
    '    }',
    '}',
    ''
  ].join('\n'));
  fs.writeFileSync(NEW_FACT, [
    'package asaot.ui',
    '{',
    '    public function shadow(opts:Object = null):Node',
    '    {',
    '        return new ShadowNode();',
    '    }',
    '}',
    ''
  ].join('\n'));
}, 'MISSING  shadow');

// M3: the call is only prose. Comments must not count as code.
mutate('M3 tree call only inside a comment', () => {
  if (!/\btree\s*\(/.test(original)) throw new Error('M3 pattern missing');
  fs.writeFileSync(VIEW, original.replace(/\btree\s*\(/, '// tree('));
}, 'MISSING  tree');

const bad = results.filter((r) => !r.pass);
console.log('---- ' + (results.length - bad.length) + '/' + results.length + ' mutations caught ----');
if (bad.length) {
  console.error('[mutation] SURVIVORS: ' + bad.map((b) => b.name).join('; '));
  process.exit(1);
}
console.log('[mutation] RESULT: PASS');