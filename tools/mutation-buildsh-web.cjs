// tools/mutation-buildsh-web.cjs -- proves tools/buildsh-web.cjs goes red on each way
// the `build.sh web` arm can be wrong, and that it names the failure it is supposed
// to name.
//
// The seven mutations are the seven mistakes this arm actually invites:
//   M1  `--package web` disappears from the argv (the compiler then builds a native
//       executable or refuses; either way nothing says "web" was asked for)
//   M2  the entry class becomes `demo.DocsAir` -- which does not compile for wasm at
//       all (UncaughtErrorEvent), so this is the "it built yesterday" failure
//   M3  `--check` stops believing the compiler: any doctor status passes, so the stub
//       toolchain from the gate's A2 case (a 22-byte emcc.bat that exits 1) is
//       reported as usable -- the file is there, the name is right, nothing ran
//   M4  the `--gpu` guard stops firing (a one-letter typo in the arm comparison): the
//       option is then silently accepted on an arm where it cannot mean anything
//   M5  the .gitignore rule for the generated app dir is dropped: the `air-*` negations
//       re-include its app.xml / as-image.png / build.sh and a derived copy of the
//       tracked descriptor can be committed
//   M6  findEmsdk() stops erroring on an EMSDK_HOME that is not an emsdk and falls back
//       to the workspace copy instead (builds with a toolchain nobody asked for)
//   M7  the runner reports an emcc OUTSIDE the SDK again -- the shape of the G27
//       workaround (a launcher shim tree in .scratch/ standing in front of emcc)
//
// Each file is restored in `finally` and compared by sha256, byte for byte. Nothing
// on disk is left over: M3's stub SDK is created and removed by the gate itself.
//
// USAGE (from asaotui/):   node tools/mutation-buildsh-web.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const SH = 'ui-demo/air-gallery/build.sh';
const WG = 'ui-demo/web-gallery.cjs';
const GI = '.gitignore';
const RESULTS = path.join(UI, 'reviews', 'mutation-buildsh-web.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the argv stops asking for the web package',
    file: WG,
    find: "    '--target', 'wasm',\n    '--package', 'web',\n",
    replace: "    '--target', 'wasm',\n",
    expect: 'the build asks for the web package',
  },
  {
    id: 'M2',
    why: 'the entry class becomes DocsAir (cannot compile for wasm)',
    file: WG,
    find: "    '--main-class', 'demo.DocsWeb',",
    replace: "    '--main-class', 'demo.DocsAir',",
    expect: 'the entry class is demo.DocsWeb',
  },
  {
    id: 'M3',
    why: 'the check stops believing the compiler (a stub emcc that exits 1 passes)',
    file: WG,
    find: "  } else if (web.status !== 'ok') {",
    replace: "  } else if (web.status === 'never') {",
    expect: 'an emcc that exists but exits nonzero is NOT reported as usable',
  },
  {
    id: 'M4',
    why: 'the --gpu guard stops firing on the web arm (typo in the comparison)',
    file: SH,
    // The guard's condition, verbatim, so a reformat of build.sh makes this mutant
    // SKIP loudly instead of silently mutating something else.
    find: '  if [ "$ARM" = web ]; then\n',
    replace: '  if [ "$ARM" = wbe ]; then\n',
    expect: '`web --gpu gl` is refused with a reason',
  },
  {
    id: 'M5',
    why: 'the generated web app dir loses its ignore rule (derived app.xml becomes committable)',
    file: GI,
    find: '/ui-demo/air-gallery-web/\n',
    replace: '\n',
    expect: 'ui-demo/air-gallery-web/app.xml is git-ignored',
  },
  {
    id: 'M6',
    why: 'a wrong EMSDK_HOME falls back to the workspace SDK instead of failing',
    file: WG,
    find: "EMCC_ENTRY));\n    process.exit(2);\n",
    replace: "EMCC_ENTRY));\n",
    expect: 'an EMSDK_HOME that is not an emsdk is an error, not a fallback',
  },
  {
    id: 'M7',
    why: 'the runner reports an emcc outside the SDK again (the G27 shim is back)',
    file: WG,
    find: "    say('emcc', web.status + ' -- ' + web.detail);",
    replace: "    say('emcc', web.status + ' -- ' + path.join(UI, '.scratch', 'emcc-shim', 'upstream', 'emscripten', 'emcc.exe'));",
    expect: 'the program it names is the SDK',
  },
];

const log = [];
const line = (s) => { log.push(s); console.log(s); };

function gate() {
  return spawnSync(process.execPath, ['tools/buildsh-web.cjs'], { cwd: UI, encoding: 'utf8' });
}

let caught = 0, broken = 0;
line('MUTATION buildsh-web -- ' + MUTATIONS.length + ' mutations of the web arm');
line('gate before any mutation:');
{
  const r = gate();
  const out = ((r.stdout || '') + (r.stderr || '')).trim();
  const summary = out.split(/\r?\n/).find((l) => /^buildsh-web: /.test(l)) || out.slice(-200);
  line('  ' + summary + '  (exit ' + r.status + ')');
  if (r.status !== 0) { line('  the gate is already red: fix it before mutating'); process.exit(1); }
}
line('');

for (const m of MUTATIONS) {
  const file = path.join(UI, m.file);
  const before = fs.readFileSync(file, 'utf8');
  const beforeHash = sha(file);
  const hits = before.split(m.find).length - 1;
  if (hits !== 1) {
    line(m.id + '  SKIPPED -- anchor matched ' + hits + ' time(s) in ' + m.file
      + ' (expected exactly 1; the file drifted, fix the mutation, do not ignore it)');
    broken++;
    continue;
  }
  try {
    fs.writeFileSync(file, before.split(m.find).join(m.replace));
    const r = gate();
    const out = (r.stdout || '') + (r.stderr || '');
    const red = r.status !== 0;
    const saidIt = out.indexOf(m.expect) >= 0;
    const ok = red && saidIt;
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why);
    line('     exit ' + r.status + (saidIt ? '' : '  MISSING the expected line "' + m.expect + '"'));
    for (const l of out.split(/\r?\n/).filter((x) => /^  FAIL:/.test(x)).slice(0, 3)) line('     ' + l.trim());
  } finally {
    fs.writeFileSync(file, before);
  }
  const afterHash = sha(file);
  line('     restore: ' + (afterHash === beforeHash
    ? 'byte-identical (' + afterHash.slice(0, 16) + ')'
    : 'MISMATCH ' + beforeHash.slice(0, 16) + ' -> ' + afterHash.slice(0, 16) + '  THIS IS BAD'));
  if (afterHash !== beforeHash) broken++;
}

// The gate must be green again on the restored tree -- otherwise a mutation that
// "caught" something left a wound behind and the next reader inherits it.
{
  const r = gate();
  line('');
  line('gate after restoring every file: exit ' + r.status);
  if (r.status !== 0) broken++;
}

line('');
line('MUTATION buildsh-web: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.mkdirSync(path.dirname(RESULTS), { recursive: true });
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);