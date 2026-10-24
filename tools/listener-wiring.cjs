// listener-wiring.cjs -- a node's own listeners must be attached through
// `UiNode.listen()` so `destroySubtree()` can take them back off.
//
// WHY THIS IS A GATE (2026-10-24): the docs app crashed on AIR with
//
//     TypeError: Error #1009: Cannot access a property or method of a null object
//     reference.
//         at asaot.ui::UiNode/setHover()
//         at Function/UiNode.as$1::anonymous()
//
// -- once per click, on accordion / dialog / drawer / menu (air-trace.txt). AIR
// finishes the frame that REMOVED a display object before it recomputes which object
// the pointer is over, so the object that was under the pointer receives its
// `mouseOut` one beat after the node was torn down; the closure still held the node,
// and the node's `app` / scratch bag were already null. Anonymous closures cannot be
// removed by reference afterwards, so "handlers must survive a dead node" is not a
// discipline any single widget can be trusted to keep -- the fix is that every
// listener is BOOKKEPT (`UiNode.listen`) and released by `destroySubtree`.
//
// WHAT IT CHECKS (source level, no compile):
//   1. no `x.backing.addEventListener(` / `x.tf.addEventListener(` anywhere in kit/
//      -- the only legal way to attach is `n.listen(target, type, fn)`;
//   2. `UiNode.destroySubtree` still calls `releaseListeners()` (the other half; a
//      gutted release is invisible to check 1);
//   3. the scan actually saw listeners at all, so "0 violations" cannot mean
//      "0 matches" of a regex that stopped applying.
//
// WHAT IT CANNOT SEE: whether the release happens BEFORE the fields are nulled, or
// whether a widget's stage-level gesture listener is cleaned up -- both are
// behavioural, and `probes/lifecycle` runs the real sequence (build a node, destroy
// it, then deliver each pointer event to its old backing and require silence).
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const KIT = path.join(ROOT, 'kit');

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const f = path.join(dir, e.name);
    if (e.isDirectory()) walk(f, out);
    else if (e.name.endsWith('.as')) out.push(f);
  }
  return out;
}

const RAW = /([A-Za-z_$][\w$]*)\.(backing|tf)\.addEventListener\s*\(/g;
const WIRED = /\b(?:n|this)\.listen\s*\(/g;

const violations = [];
let wired = 0;
for (const f of walk(KIT, [])) {
  const src = fs.readFileSync(f, 'utf8');
  const rel = path.relative(ROOT, f).split(path.sep).join('/');
  for (const line of src.split(/\r?\n/)) {
    let m;
    RAW.lastIndex = 0;
    while ((m = RAW.exec(line)) !== null) {
      violations.push(rel + ': ' + m[1] + '.' + m[2]
        + '.addEventListener( -- attach through ' + m[1] + '.listen(' + m[1] + '.' + m[2] + ', ...) instead');
    }
    WIRED.lastIndex = 0;
    while (WIRED.exec(line) !== null) wired++;
  }
}

// ---- the other half: destroySubtree must release what listen() recorded -----
const uiNode = fs.readFileSync(path.join(KIT, 'asaot', 'ui', 'UiNode.as'), 'utf8');
const destroy = uiNode.slice(uiNode.indexOf('function destroySubtree'));
const destroyBody = destroy.slice(0, destroy.indexOf('\n        }'));
if (!/releaseListeners\s*\(\s*\)/.test(destroyBody)) {
  violations.push('kit/asaot/ui/UiNode.as: destroySubtree() does not call releaseListeners() -- '
    + 'every listener stays on a dead node');
}
if (!/function listen\s*\(/.test(uiNode) || !/function releaseListeners\s*\(/.test(uiNode)) {
  violations.push('kit/asaot/ui/UiNode.as: listen()/releaseListeners() are gone');
}
// The scan saw nothing => the regexes drifted, not the code. A green "0 listeners"
// would be the same silent pass this whole file exists to prevent.
if (wired === 0) {
  violations.push('no n.listen(...) call site found in kit/ -- the scan is broken');
}

console.log('wired listeners: ' + wired + '   raw attach sites: ' + violations.length);
for (const v of violations) console.log('  ' + v);
console.log('LISTENER WIRING: ' + (violations.length === 0 ? 'PASS' : 'FAIL'));
process.exit(violations.length === 0 ? 0 : 1);