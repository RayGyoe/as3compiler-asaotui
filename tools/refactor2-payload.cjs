// tools/refactor2-payload.cjs -- ONE-SHOT: move the per-kind field mirroring out
// of `UiNode.applyPayload` and behind `Widget.payload`, and give UiNode the two
// generic hooks a widget needs to own its own state:
//
//   n.desc  -- the current description Node (typed cast target inside a widget)
//   n.extra -- per-node scratch Object, created at STRUCTURE time (never in a
//              frame), where a widget remembers last-seen values so `payload`
//              can report "this changed" without reflowing every frame.
'use strict';
const fs = require('fs');
const FILE = 'kit/asaot/ui/UiNode.as';
let s = fs.readFileSync(FILE, 'utf8');

function once(anchor, replacement) {
  const a = s.indexOf(anchor);
  if (a < 0) throw new Error('anchor not found: ' + JSON.stringify(anchor.slice(0, 80)));
  if (s.indexOf(anchor, a + 1) >= 0) throw new Error('anchor not unique: ' + JSON.stringify(anchor.slice(0, 80)));
  s = s.slice(0, a) + replacement + s.slice(a + anchor.length);
}

function cut(startAnchor, endAnchor, replacement) {
  const a = s.indexOf(startAnchor);
  if (a < 0) throw new Error('start anchor not found: ' + JSON.stringify(startAnchor.slice(0, 80)));
  if (s.indexOf(startAnchor, a + 1) >= 0) throw new Error('start anchor not unique: ' + startAnchor.slice(0, 80));
  const b = s.indexOf(endAnchor, a);
  if (b < 0) throw new Error('end anchor not found: ' + JSON.stringify(endAnchor.slice(0, 80)));
  s = s.slice(0, a) + replacement + s.slice(b);
}

// ---- fields: desc + extra --------------------------------------------------
once('        public var widget:Widget;\n',
     '        public var widget:Widget;\n'
+ '        // The description Node this frame was reconciled from. Widgets cast it\n'
+ '        // to their own Node type to read kind-specific fields (never null while\n'
+ '        // reconciling). Held by reference only -- render() builds a fresh tree\n'
+ '        // every frame and this is overwritten, never accumulated.\n'
+ '        public var desc:Node;\n'
+ '        // Per-node scratch for widget-private state (last-seen payload values, so\n'
+ '        // `payload` can report a change without reflowing on every frame).\n'
+ '        // Allocated ONCE per node at structure time -- steady state allocates\n'
+ '        // nothing (AGENTS.md memory rule).\n'
+ '        public var extra:Object;\n');

once('            this.widget = null;\n',
     '            this.widget = null;\n            this.desc = null;\n            this.extra = {};\n');

// ---- applyPayload -> generic preamble + Widget.payload ---------------------
cut('        // ---- payload mirroring (called by the reconciler) ---------------',
    '        // ---- resolve -----------------------------------------------------',
     '        // ---- payload mirroring (called by the reconciler) ---------------\n'
+    '        // The generic Element part is copied here; everything kind-specific is\n'
+    '        // the widget\'s business (Widget.payload), which returns true when the\n'
+    '        // change forces a re-measure.\n'
+    '        // Returns true when a payload change forced a re-measure.\n'
+    '        public function applyPayload(desc:Node):Boolean\n'
+    '        {\n'
+    '            this.desc = desc;\n'
+    '            this.role = Element(desc).role;\n'
+    '            this.ariaName = Element(desc).ariaName;\n'
+    '            this.visible = Element(desc).visible;\n'
+    '\n'
+    '            var relayout:Boolean = this.widget.payload(this, desc);\n'
+    '            if (relayout)\n'
+    '            {\n'
+    '                this.dirty |= Dirty.M_MEASURE | Dirty.M_ARRANGE | Dirty.M_PAINT;\n'
+    '            }\n'
+    '            return relayout;\n'
+    '        }\n'
+    '\n');

fs.writeFileSync(FILE, s);

// Self-checks.
for (const t of ['desc is TextNode', 'desc is ButtonNode', 'desc is TextInput', 'desc is CheckboxNode', 'desc is BoxNode']) {
  const n = s.split(t).length - 1;
  if (n !== 0) throw new Error('leftover per-kind payload branch: ' + t);
}
for (const t of ['this.widget.payload(this, desc)', 'public var desc:Node', 'public var extra:Object']) {
  const n = s.split(t).length - 1;
  if (n !== 1) throw new Error('expected exactly one ' + JSON.stringify(t) + ', got ' + n);
}
console.log('refactor2-payload: OK, ' + s.split('\n').length + ' lines');

// destroySubtree must drop the new references too, or a dead node keeps the whole
// last rendered description tree alive through the GC.
const before = s;
s = s.replace('            this.tf = null;\n            this.shapeA = null;\n',
              '            this.desc = null;\n            this.extra = null;\n            this.tf = null;\n            this.shapeA = null;\n');
if (s === before) throw new Error('could not extend destroySubtree');
fs.writeFileSync(FILE, s);
console.log('refactor2-payload: destroySubtree releases desc/extra');
