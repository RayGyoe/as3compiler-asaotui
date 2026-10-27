// Which of the three perf changes broke motion / stick? Disable one at a time.
const fs = require('fs');
const crypto = require('crypto');
const { execFileSync } = require('child_process');
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const FILES = {
  paint: 'kit/asaot/ui/PaintKit.as',
  app: 'kit/asaot/ui/UiApp.as',
  node: 'kit/asaot/ui/UiNode.as'
};
const orig = {};
for (const k in FILES) orig[k] = fs.readFileSync(FILES[k], 'utf8');

const CASES = [
  { name: 'measure cache OFF', file: 'paint',
    find: 'if (n.measureKey == key && n.state.measureValid == 3) return;',
    replace: 'if (false && n.measureKey == key) return;' },
  { name: 'resize-marks-paint OFF', file: 'node',
    find: 'if (w != this.absW || h != this.absH) this.dirty |= Dirty.M_PAINT;',
    replace: '// OFF' },
  { name: 'paintAll restored after a solve', file: 'app',
    find: `                if (this.root != null) paintDirty(this.root);
                if (this.overlayRoot != null) paintDirty(this.overlayRoot);`,
    replace: `                if (this.root != null) paintAll(this.root);
                if (this.overlayRoot != null) paintAll(this.overlayRoot);` }
];
function run(probe) {
  try {
    execFileSync('node', ['tools/probe.cjs', probe], { stdio: 'pipe' });
    return 'PASS';
  } catch (e) {
    const out = String(e.stdout || '') + String(e.stderr || '');
    const m = out.match(/FAIL[^\n]*/g);
    return 'FAIL ' + (m ? m.slice(0, 2).join(' | ') : '').slice(0, 200);
  }
}
try {
  for (const c of CASES) {
    if (!orig[c.file].includes(c.find)) { console.log('ANCHOR MISSING ' + c.name); continue; }
    fs.writeFileSync(FILES[c.file], orig[c.file].replace(c.find, c.replace));
    console.log('=== ' + c.name + ' ===');
    console.log('  motion: ' + run('probes/widgets/motion'));
    console.log('  stick:  ' + run('probes/widgets/stick'));
    fs.writeFileSync(FILES[c.file], orig[c.file]);
  }
} finally {
  for (const k in FILES) fs.writeFileSync(FILES[k], orig[k]);
  console.log('restore byte-identical: ' + Object.keys(FILES).every((k) => sha(fs.readFileSync(FILES[k], 'utf8')) === sha(orig[k])));
}
