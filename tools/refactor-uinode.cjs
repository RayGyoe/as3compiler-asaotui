// tools/refactor-uinode.cjs -- ONE-SHOT: move UiNode's per-kind `if` chains
// behind the Widget seam (Widget.as / Widgets.as / PaintKit.as / kind/*).
//
// Marker-based splice rather than hand-matched big blocks: every anchor below is
// asserted to exist exactly once, so a silent partial rewrite is impossible.
'use strict';
const fs = require('fs');
const FILE = 'kit/asaot/ui/UiNode.as';
let s = fs.readFileSync(FILE, 'utf8');

function cut(startAnchor, endAnchor, replacement) {
  const a = s.indexOf(startAnchor);
  if (a < 0) throw new Error('start anchor not found: ' + JSON.stringify(startAnchor.slice(0, 70)));
  if (s.indexOf(startAnchor, a + 1) >= 0) throw new Error('start anchor not unique: ' + startAnchor.slice(0, 70));
  const b = s.indexOf(endAnchor, a);
  if (b < 0) throw new Error('end anchor not found: ' + JSON.stringify(endAnchor.slice(0, 70)));
  s = s.slice(0, a) + replacement + s.slice(b);
}

function once(anchor, replacement) {
  const a = s.indexOf(anchor);
  if (a < 0) throw new Error('anchor not found: ' + JSON.stringify(anchor));
  if (s.indexOf(anchor, a + 1) >= 0) throw new Error('anchor not unique: ' + JSON.stringify(anchor));
  s = s.slice(0, a) + replacement + s.slice(a + anchor.length);
}

// ---- 1: identity field -----------------------------------------------------
once('        public var engineNode:Object;\n',
  '        public var engineNode:Object;\n'
+ '        // The per-kind behaviour (Widget.as). Resolved once, at structure time,\n'
+ '        // from Widgets.require(kind); a miss THROWS (never an invisible hole).\n'
+ '        public var widget:Widget;\n');

// ---- 2: ctor init ----------------------------------------------------------
once('            this.engineNode = null;\n',
  '            this.engineNode = null;\n            this.widget = null;\n');

// ---- 3: createBacking + makeText -> Widget ---------------------------------
cut('            this.backing = new Sprite();\n',
    '        // ---- transient state changes (paint-only, never a reflow) --------',
     '            this.backing = new Sprite();\n'
+    '            var self:UiNode = this;\n'
+    '\n'
+    '            // Everything that DIFFERS per kind lives behind one Widget instance\n'
+    '            // (see Widget.as). The display objects are created by build(), lowest\n'
+    '            // layer first, so the UiNode children keep a stable base index for\n'
+    '            // display-order repair.\n'
+    '            this.widget = Widgets.require(this.kind);\n'
+    '            this.widget.build(this);\n'
+    '\n'
+    '            this.internalCount = this.backing.numChildren;\n'
+    '            // Hover / press / click are handled on the backing object, so the\n'
+    '            // hit region is the control\'s drawn region -- the same region the\n'
+    '            // existing pick test (as_pick_hit_local) walks.\n'
+    '            this.backing.addEventListener(MouseEvent.MOUSE_OVER, function (e:MouseEvent):void { self.setHover(1); });\n'
+    '            this.backing.addEventListener(MouseEvent.MOUSE_OUT, function (e:MouseEvent):void { self.setHover(0); });\n'
+    '            if (this.widget.wantsPress())\n'
+    '            {\n'
+    '                this.backing.addEventListener(MouseEvent.MOUSE_DOWN, function (e:MouseEvent):void { self.setPressed(1); });\n'
+    '                this.backing.addEventListener(MouseEvent.MOUSE_UP, function (e:MouseEvent):void { self.setPressed(0); });\n'
+    '                this.backing.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void { self.handleClick(); });\n'
+    '            }\n'
+    '        }\n'
+    '\n');

// ---- 4: handleClick --------------------------------------------------------
cut('        public function handleClick():void\n',
    '        // ---- payload mirroring (called by the reconciler) ---------------',
     '        public function handleClick():void\n'
+    '        {\n'
+    '            this.setPressed(0);\n'
+    '            if (this.widget.click(this)) return;\n'
+    '            if (this.onClick != null) this.onClick();\n'
+    '        }\n'
+    '\n');

// ---- 5: measureSelf body + measureField + formatFor + edge helpers ---------
cut('            if (this.kind == "text" && this.tf != null)\n            {\n                measureField(this.tf, this.textContent, s);\n',
    '        // ---- pass 2: arrange (final rect already solved by the engine) ---',
     '            this.widget.measure(this);\n'
+    '        }\n'
+    '\n');

// ---- 6: arrangeSelf body ---------------------------------------------------
cut('            var tl:Number = nz(s.borderWidths != null ? s.borderWidths.left : NaN);\n',
    '        // ---- pass 3: paint ----------------------------------------------',
     '            // The inner display objects are placed by the kind, which reads the\n'
+    '            // solved rect back through PaintKit (insetX/insetY/contentW/H).\n'
+    '            this.widget.arrange(this);\n'
+    '        }\n'
+    '\n');

// ---- 7: paintSelf + the drawing helpers it used ---------------------------
cut('        public function paintSelf():void\n',
    '        public function destroySubtree():void',
     '        public function paintSelf():void\n'
+    '        {\n'
+    '            this.widget.paint(this);\n'
+    '        }\n'
+    '\n');

// ---- 8: drop the now-unused TextFormat import ------------------------------
once('    import flash.text.TextFormat;\n', '');

fs.writeFileSync(FILE, s);

// Self-checks: the refactor must have removed every per-kind branch and left
// exactly one dispatch call per pass.
const bad = ['this.kind ==', 'measureField(', 'formatFor(', 'paintCheckbox(', 'drawBox(', 'private function w1()', 'private function makeText('];
for (const t of bad) {
  const n = s.split(t).length - 1;
  if (n !== 0) throw new Error('leftover ' + JSON.stringify(t) + ' x' + n);
}
for (const t of ['this.widget.measure(this);', 'this.widget.arrange(this);', 'this.widget.paint(this);', 'this.widget.click(this)', 'Widgets.require(this.kind)']) {
  const n = s.split(t).length - 1;
  if (n !== 1) throw new Error('expected exactly one ' + JSON.stringify(t) + ', got ' + n);
}
console.log('refactor-uinode: OK, ' + s.split('\n').length + ' lines, '
  + 'no per-kind branches remain');
