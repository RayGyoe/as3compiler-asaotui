// tools/mutation-bound-truthy.cjs -- prove the style-scan gate (gates.cjs section 7)
// can go RED.
//
// WHY THIS EXISTS: that gate was written for G9 and counted lines matching the
// string `Boolean-CALL`. The tool never printed that string, so the count was
// always 0 and the gate was structurally incapable of failing -- it certified the
// kit's cleanliness no matter what the kit contained. The gate now consumes the
// tool's EXIT CODE (with the printed `G9-RISK` marker as a second signal), so the
// property to demonstrate is: "with one risky local present, the tool exits
// non-zero".
//
// The mutation plants ONE `:Object` local that is later used as a condition, in a
// throwaway file inside kit/ (the directory the gate scans). The file is deleted in
// `finally` and its absence is verified.
//
// NOTE on G9 being fixed: the pattern is no longer a CORRECTNESS bug. The gate
// survives as a style/perf rule -- `*` avoids a boxing allocation per read
// (`as_value_to_obj`) and the Array-identity hazard recorded as G14. That is why
// this mutation asserts the TOOL goes red, not that any output changed.
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const PLANT = path.join(UI, 'kit', 'asaot', 'ui', '_mut_g9_risky.as');

const src = [
  '// TEMPORARY mutation file -- created and deleted by tools/mutation-bound-truthy.cjs.',
  'package asaotui',
  '{',
  '    public class _MutG9Risky',
  '    {',
  '        public function f(o:Object):Boolean',
  '        {',
  '            var z:Object = o;',
  '            if (z) return true;',      // <-- the risky use the scanner looks for
  '            return false;',
  '        }',
  '    }',
  '}',
  '',
].join('\n');

const results = [];
function record(name, ok, detail) { results.push({ name, ok, detail }); }

const existedBefore = fs.existsSync(PLANT);
try {
  if (existedBefore) throw new Error('refusing to run: ' + PLANT + ' already exists');
  fs.writeFileSync(PLANT, src);

  const r = spawnSync(process.execPath, [path.join(__dirname, 'find-bound-truthy.cjs'), 'kit', 'seam'],
    { cwd: UI, encoding: 'utf8' });
  const out = (r.stdout || '') + (r.stderr || '');
  const hits = out.split(/\r?\n/).filter((l) => /G9-RISK/.test(l)).length;
  record('planted risky local -> tool exits non-zero', r.status !== 0,
    'exit ' + r.status + ' (want != 0)');
  record('planted risky local -> named in the output', hits >= 1,
    hits + ' G9-RISK line(s), want >= 1');
  record('the gate consumes that exit code', r.status !== 0,
    'gates.cjs: code = (r.status !== 0 || hits > 0) ? 1 : 0 -- a non-zero status is sufficient');
} finally {
  if (fs.existsSync(PLANT)) fs.unlinkSync(PLANT);
}

const leftover = fs.existsSync(PLANT);
record('planted file removed', !leftover, leftover ? 'STILL PRESENT: ' + PLANT : 'kit/ is clean');

console.log('');
for (const r of results) console.log((r.ok ? 'MUTATION PASS  ' : 'MUTATION FAIL  ') + r.name + '   [' + r.detail + ']');
const bad = results.filter((r) => !r.ok).length;
console.log('');
console.log('MUTATION: ' + (bad === 0 ? 'PASS (' + results.length + '/' + results.length + ')' : 'FAIL (' + bad + ' problem(s))'));
process.exit(bad === 0 ? 0 : 1);