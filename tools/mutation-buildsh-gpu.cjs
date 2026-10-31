// tools/mutation-buildsh-gpu.cjs -- proves tools/buildsh-gpu.cjs goes red on each way
// `build.sh --gpu` can be wrong, and that it names the failure it is supposed to name.
//
// The five mutations are the five mistakes this option actually invites:
//   M1  a backend is named in the usage text but never passed (the "looks honoured"
//       failure -- the window opens, on the platform's default backend)
//   M2  a mode maps to the wrong <renderMode> (cpu silently meaning gpu)
//   M3  an unknown mode is swallowed instead of refused (AGENTS.md 2.5)
//   M4  the derived descriptor is printed but not handed to the AOT arm
//   M5  the derived descriptor drifts a SECOND line (requestedDisplayResolution),
//       which is exactly what would break the HiDPI A/B in ui-demo/check-dpi.cjs
//
// build.sh is restored in `finally` and its sha256 compared byte-for-byte. app.xml is
// never a mutation target: `check-dpi.cjs` and this gate both treat it as tracked
// input, and a half-restored descriptor is not a thing worth risking for a test.
//
// USAGE (from asaotui/):   node tools/mutation-buildsh-gpu.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const SH = 'ui-demo/air-gallery/build.sh';
const RESULTS = path.join(UI, 'reviews', 'mutation-buildsh-gpu.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the named-backend mode stops naming its backend (parsed, printed, never passed)',
    file: SH,
    // `gl` is REFUSED off Windows (macOS composites on Metal), so blaming it there
    // would make the mutation invisible and the sweep would report a MISS that says
    // nothing about the code. Aim it at the backend-carrying mode the HOST actually
    // exercises: `gl` on Windows, `d3d12` everywhere else. Same line, same defect.
    find: process.platform === 'win32'
      ? '    gl)     DESC=app.gl.xml;     RENDER=gpu;    BACKEND=gl ;;'
      : '    d3d12)  DESC=app.d3d12.xml;  RENDER=gpu;    BACKEND=d3d12 ;;',
    replace: process.platform === 'win32'
      ? '    gl)     DESC=app.gl.xml;     RENDER=gpu;    BACKEND= ;;'
      : '    d3d12)  DESC=app.d3d12.xml;  RENDER=gpu;    BACKEND= ;;',
    expect: process.platform === 'win32' ? 'passes --gpu-backend gl' : 'passes --gpu-backend d3d12'
  },
  {
    id: 'M2',
    why: 'cpu is wired to the gpu <renderMode> (a mode that means something else)',
    file: SH,
    find: '    cpu)    DESC=app.cpu.xml;    RENDER=cpu;    BACKEND= ;;',
    replace: '    cpu)    DESC=app.cpu.xml;    RENDER=gpu;    BACKEND= ;;',
    expect: 'writes <renderMode>cpu</renderMode>'
  },
  {
    id: 'M3',
    why: 'an unknown --gpu value is ignored instead of refused',
    file: SH,
    find: '    *)      die "unknown --gpu \'$1\' (known: cpu, gpu, d3d12, gl, direct)" ;;',
    replace: '    *)      : ;;',
    expect: 'an unknown --gpu mode is refused'
  },
  {
    id: 'M4',
    why: 'the derived descriptor is described but not passed to the AOT arm',
    file: SH,
    find: '  [ "$DESC" = app.xml ] || printf \' --app-xml %s\' "$DESC"',
    replace: '  :',
    expect: 'passes --app-xml app.gpu.xml'
  },
  {
    id: 'M5',
    why: 'the derived descriptor moves a second line (breaks the HiDPI A/B)',
    file: SH,
    find: 'fs.writeFileSync(out, src.replace(re, "<renderMode>" + mode + "</renderMode>"));',
    replace: 'fs.writeFileSync(out, src.replace(re, "<renderMode>" + mode + "</renderMode>")'
      + '.replace("<requestedDisplayResolution>high</requestedDisplayResolution>",'
      + ' "<requestedDisplayResolution>standard</requestedDisplayResolution>"));',
    expect: 'changes nothing but the <renderMode> line'
  }
];

function run() {
  return spawnSync(process.execPath, ['tools/buildsh-gpu.cjs'], { cwd: UI, encoding: 'utf8' });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

const base = run();
const baseOut = (base.stdout || '') + (base.stderr || '');
const baseVerdict = (/buildsh-gpu: (\d+) checks, (\d+) failures/.exec(baseOut) || [, '?', '?']);
line('baseline (unmutated): exit ' + base.status + ', ' + baseVerdict[1] + ' checks, '
  + baseVerdict[2] + ' failures');
if (base.status !== 0) {
  line('the baseline is not green; a mutation run would be meaningless. Aborting.');
  for (const l of baseOut.split(/\r?\n/)) line('  ' + l);
  fs.writeFileSync(RESULTS, log.join('\n') + '\n');
  process.exit(1);
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
    const r = run();
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

line('');
line('MUTATION buildsh-gpu: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.mkdirSync(path.dirname(RESULTS), { recursive: true });
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);