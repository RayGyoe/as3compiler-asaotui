// mutation-demo-options.cjs -- prove tools/demo-options.cjs has teeth.
//
// Three one-line mutations, each of which must turn the scan RED, and each restored
// byte-for-byte (sha256 checked afterwards):
//
//   M1 a demo passes a key no factory reads  -- the reported shape (a page teaching
//      an option that does not exist). Patched into a REAL call, not a snippet.
//   M2 a factory stops reading a key its demos pass -- the other direction: the docs
//      are right and the kit moved out from under them.
//   M3 one style SHORTHAND is dropped from StyleRefinement.from -- proves the
//      shorthand allowance is DERIVED from the source (so box({gap}) is fine), not a
//      blanket "anything goes" that would make the scan decorative.
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const CASES = [
  {
    id: 'M1',
    name: 'a demo passes "bogusOption"',
    file: path.join(ROOT, 'ui-demo', 'demo', 'DocsFeedback.as'),
    from: 'button({ key: "prBtn", label: "+10%", style: DocsDemo.QUIET,',
    to: 'button({ key: "prBtn", label: "+10%", bogusOption: 1, style: DocsDemo.QUIET,'
  },
  {
    id: 'M2',
    name: 'progress() stops reading `value`',
    file: path.join(ROOT, 'kit', 'asaot', 'ui', 'progress.as'),
    from: 'if (opts != null && opts.value != null) n.value = Number(opts.value);',
    to: ''
  },
  {
    id: 'M3',
    name: 'StyleRefinement.from stops reading `flexGrow`',
    file: path.join(ROOT, 'kit', 'asaot', 'ui', 'style', 'StyleRefinement.as'),
    from: '            if (o.flexGrow != null) r.flexGrow = Number(o.flexGrow);\n',
    to: ''
  }
];

let bad = 0;
for (const c of CASES) {
  const before = sha(c.file);
  const src = fs.readFileSync(c.file, 'utf8');
  const hits = src.split(c.from).length - 1;
  if (hits !== 1) {
    console.log(c.id + ': SKIPPED -- the anchor occurs ' + hits + ' times in ' + path.basename(c.file));
    bad++;
    continue;
  }
  fs.writeFileSync(c.file, src.replace(c.from, c.to));
  let r;
  try {
    r = spawnSync(process.execPath, ['tools/demo-options.cjs'], { cwd: ROOT, encoding: 'utf8' });
  } finally {
    fs.writeFileSync(c.file, src);
  }
  const out = (r.stdout || '') + (r.stderr || '');
  const rows = (out.match(/^ {2}\S+:\d+ .*$/gm) || []).length;
  const caught = r.status !== 0 && /DEMO OPTIONS: FAIL/.test(out);
  if (!caught) bad++;
  console.log('---- ' + c.id + ': ' + c.name);
  console.log('   exit ' + r.status + ', ' + rows + ' call site(s) reported -> ' + (caught ? 'CAUGHT' : 'MISSED'));
  for (const l of out.split(/\r?\n/).filter((x) => /^ {2}\S+:\d+ /.test(x)).slice(0, 3)) console.log('   | ' + l.trim());
  console.log('   restore: ' + (sha(c.file) === before ? 'byte-identical ' + before.slice(0, 16) : 'DIFFERS!!'));
  if (sha(c.file) !== before) bad++;
}
console.log(bad === 0 ? 'MUTATION: 3/3 CAUGHT' : 'MUTATION: ' + bad + ' problem(s)');
process.exit(bad === 0 ? 0 : 1);