// air-check/AirMain.as -- does the whole `asaot.ui` library actually RUN on AIR?
//
// This is the answer to "can this library run under air (mxmlc -> adl)?". The
// layout seam was deliberately drawn as a PURE AS3 INTERFACE (see
// ../seam/README.md) precisely so that the entire library -- including layout --
// is plain AS3 with no host C calls. This file is the proof: mxmlc compiles the
// library sources, adl runs them, and the pure-AS3 engine (As3LayoutEngine)
// produces the same rectangles it produces under our own AOT compiler.
//
// WHAT IT IS AND IS NOT
//   * It IS a smoke test that AIR can compile+run the library and reach the
//     same numbers. The cases carry the SAME names + order + values as the
//     frozen differential spec `diff-check/spec/cases.txt` (105 checks): a~g are
//     the original U1 cases (check-layout.md section 3 plus the two
//     config-default cases), and 17..105 cover the P1..P8 additions (justify /
//     align-items / align-self / align-content / wrap / margin / position /
//     percent padding + gap / reverse directions + RTL / overflow).
//   * It is NOT the differential harness. That is diff-check/ (a Yoga arm and an
//     AS3 arm, both driven by ONE frozen spec file). Here the cases are inline
//     on purpose: this file must not depend on `flash.filesystem` for reading a
//     spec, so that a failure can only mean "the library does not run on AIR",
//     never "a path was wrong". The GOT stream is nevertheless expected to be
//     character-for-character the same as the Yoga arm's.
//
// TWO AIR-SPECIFIC TRAPS THIS FILE WORKS AROUND (measured on this machine):
//   1. `adl` never returns on its own -- an AIR app keeps its event loop alive
//      until NativeApplication.exit(). Without it the process hangs forever
//      (measured: 900 s, killed).
//   2. `trace()` output does NOT reach adl.exe's stdout on Windows (no console
//      attached). So the results must be written to a FILE for the caller to
//      read; trace is only a best-effort courtesy.
//
// WHY A Sprite ROOT CLASS: mxmlc resolves the document class by file name, so
// an .as file with only top-level statements fails with "cannot load the SWF's
// root class". Our own AOT accepts both forms; only this AIR driver needs the
// class form.
package
{
    import asaot.ui.LayoutConstants;
    import asaot.ui.LayoutEngine;
    import asaot.ui.as3.As3LayoutEngine;

    import flash.desktop.NativeApplication;
    import flash.display.Sprite;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public class AirMain extends Sprite
    {
        private var EPS:Number = 0.01;
        private var out:String = '';
        private var checks:int = 0;
        private var fails:int = 0;

        public function AirMain()
        {
            out += 'AIR-CHECK air=' + NativeApplication.nativeApplication.runtimeVersion;
            out += ' (mxmlc -> adl)\n';
            run();
            runExt();
            out += '---- ' + checks + ' checks, ' + fails + ' failures ----\n';
            out += (fails == 0 ? 'RESULT: PASS\n' : 'RESULT: FAIL\n');
            trace(out);
            writeOut();
            NativeApplication.nativeApplication.exit();
        }

        private function eng(web:Boolean):LayoutEngine
        {
            var e:LayoutEngine = new As3LayoutEngine();
            e.createConfig(0, web);
            return e;
        }

        private function root(e:LayoutEngine, cfg:Object, w:Number, h:Number):Object
        {
            var r:Object = e.createNode(cfg);
            e.setSize(r, LayoutConstants.AXIS_WIDTH,  w, LayoutConstants.UNIT_POINT);
            e.setSize(r, LayoutConstants.AXIS_HEIGHT, h, LayoutConstants.UNIT_POINT);
            return r;
        }

        private function child(e:LayoutEngine, cfg:Object, p:Object, i:int,
                              w:Number, h:Number):Object
        {
            var c:Object = e.createNode(cfg);
            e.insertChild(p, c, i);
            e.setSize(c, LayoutConstants.AXIS_WIDTH,  w, LayoutConstants.UNIT_POINT);
            e.setSize(c, LayoutConstants.AXIS_HEIGHT, h, LayoutConstants.UNIT_POINT);
            return c;
        }

        // A child with NO explicit size at all (auto on both axes). This is NOT
        // the same as child(...,0,0): an explicit 0 is a real 0, whereas
        // omitting setSize leaves the axis UNIT_UNDEFINED so the engine derives
        // it (stretch along the cross axis, flex basis along the main axis).
        // Getting this wrong is exactly what produced 5 bogus failures on the
        // AIR arm -- c/e1/e2 need childAuto, not child(...,0,0).
        private function childAuto(e:LayoutEngine, cfg:Object, p:Object, i:int):Object
        {
            var c:Object = e.createNode(cfg);
            e.insertChild(p, c, i);
            return c;
        }

        private function chk(name:String, e:LayoutEngine, n:Object,
                             wl:Number, wt:Number, ww:Number, wh:Number):void
        {
            var o:Array = [];
            e.layoutGet(n, o);
            var l:Number = o[0];
            var t:Number = o[1];
            var w:Number = o[2];
            var h:Number = o[3];
            var ok:Boolean = Math.abs(l - wl) <= EPS && Math.abs(t - wt) <= EPS
                && Math.abs(w - ww) <= EPS && Math.abs(h - wh) <= EPS;
            checks++;
            if (!ok) fails++;
            out += 'GOT ' + name + ' ' + f4(l) + ' ' + f4(t) + ' ' + f4(w) + ' ' + f4(h) + '\n';
            out += (ok ? '  OK   ' : '  FAIL ') + name + ' got (' + f4(l) + ',' + f4(t) + ','
                + f4(w) + ',' + f4(h) + ') want (' + f4(wl) + ',' + f4(wt) + ','
                + f4(ww) + ',' + f4(wh) + ')\n';
        }

        private function f4(x:Number):String
        {
            // toFixed(4) is the shared output contract; the engines themselves
            // are float-precision, so 4 decimals is well inside EPS = 0.01.
            return x.toFixed(4);
        }

        private function run():void
        {
            var e:LayoutEngine;

            // ---- a) one explicitly sized node ----------------------------------
            e = eng(true);
            var ra:Object = root(e, e.createConfig(0, true), 100, 50);
            e.calculate(ra, 100, 50, LayoutConstants.DIR_LTR);
            chk('a.root', e, ra, 0, 0, 100, 50);

            // ---- b) column + padding(all=16) + row-gap(10) ---------------------
            e = eng(true);
            var cb:Object = e.createConfig(0, true);
            var rb:Object = root(e, cb, 200, 300);
            e.setFlexDirection(rb, LayoutConstants.FLEX_DIR_COLUMN);
            e.setPadding(rb, LayoutConstants.EDGE_ALL, 16, LayoutConstants.UNIT_POINT);
            e.setGap(rb, LayoutConstants.GUTTER_ROW, 10, LayoutConstants.UNIT_POINT);
            var b0:Object = child(e, cb, rb, 0, 100, 40);
            var b1:Object = child(e, cb, rb, 1, 100, 40);
            var b2:Object = child(e, cb, rb, 2, 100, 40);
            e.calculate(rb, 200, 300, LayoutConstants.DIR_LTR);
            chk('b.root',   e, rb,  0,   0, 200, 300);
            chk('b.child0', e, b0, 16,  16, 100,  40);
            chk('b.child1', e, b1, 16,  66, 100,  40);
            chk('b.child2', e, b2, 16, 116, 100,  40);

            // ---- c) row + flexGrow 1:2:3 + basis 0 ------------------------------
            e = eng(true);
            var cc:Object = e.createConfig(0, true);
            var rc:Object = root(e, cc, 300, 100);
            e.setFlexDirection(rc, LayoutConstants.FLEX_DIR_ROW);
            var c0:Object = childAuto(e, cc, rc, 0);
            var c1:Object = childAuto(e, cc, rc, 1);
            var c2:Object = childAuto(e, cc, rc, 2);
            e.setFlex(c0, 1, 1, 0, LayoutConstants.UNIT_POINT);
            e.setFlex(c1, 2, 1, 0, LayoutConstants.UNIT_POINT);
            e.setFlex(c2, 3, 1, 0, LayoutConstants.UNIT_POINT);
            e.calculate(rc, 300, 100, LayoutConstants.DIR_LTR);
            chk('c.child0', e, c0,   0, 0,  50, 100);
            chk('c.child1', e, c1,  50, 0, 100, 100);
            chk('c.child2', e, c2, 150, 0, 150, 100);

            // ---- d) percent basis = parent CONTENT BOX; explicit size = border-box
            e = eng(true);
            var cd:Object = e.createConfig(0, true);
            var rd:Object = root(e, cd, 200, 100);
            e.setFlexDirection(rd, LayoutConstants.FLEX_DIR_COLUMN);
            e.setPadding(rd, LayoutConstants.EDGE_ALL, 20, LayoutConstants.UNIT_POINT);
            e.setBorder(rd, LayoutConstants.EDGE_ALL, 10);
            var d0:Object = e.createNode(cd);
            e.insertChild(rd, d0, 0);
            e.setSize(d0, LayoutConstants.AXIS_WIDTH,  50, LayoutConstants.UNIT_PERCENT);
            e.setSize(d0, LayoutConstants.AXIS_HEIGHT, 50, LayoutConstants.UNIT_PERCENT);
            e.calculate(rd, 200, 100, LayoutConstants.DIR_LTR);
            chk('d.root',  e, rd,  0,  0, 200, 100);
            chk('d.child', e, d0, 30, 30,  70,  20);

            // ---- e1) min-width beats flex-shrink --------------------------------
            e = eng(true);
            var ce1:Object = e.createConfig(0, true);
            var re1:Object = root(e, ce1, 100, 50);
            e.setFlexDirection(re1, LayoutConstants.FLEX_DIR_ROW);
            var e10:Object = childAuto(e, ce1, re1, 0);
            e.setFlex(e10, 0, 1, 200, LayoutConstants.UNIT_POINT);
            e.setMinMax(e10, LayoutConstants.AXIS_WIDTH, false, 150, LayoutConstants.UNIT_POINT);
            e.calculate(re1, 100, 50, LayoutConstants.DIR_LTR);
            chk('e1.child', e, e10, 0, 0, 150, 50);

            // ---- e2) max-width beats flex-grow ---------------------------------
            e = eng(true);
            var ce2:Object = e.createConfig(0, true);
            var re2:Object = root(e, ce2, 300, 50);
            e.setFlexDirection(re2, LayoutConstants.FLEX_DIR_ROW);
            var e20:Object = childAuto(e, ce2, re2, 0);
            e.setFlex(e20, 1, 1, 100, LayoutConstants.UNIT_POINT);
            e.setMinMax(e20, LayoutConstants.AXIS_WIDTH, true, 150, LayoutConstants.UNIT_POINT);
            e.calculate(re2, 300, 50, LayoutConstants.DIR_LTR);
            chk('e2.child', e, e20, 0, 0, 150, 50);

            // ---- f) web defaults -> an UNSET direction defaults to row ----------
            // The nodes below deliberately never call setFlexDirection.
            e = eng(true);
            var cf:Object = e.createConfig(0, true);
            var rf:Object = root(e, cf, 200, 100);
            var f0:Object = child(e, cf, rf, 0, 50, 40);
            var f1:Object = child(e, cf, rf, 1, 50, 40);
            e.calculate(rf, 200, 100, LayoutConstants.DIR_LTR);
            chk('f.child0', e, f0,  0, 0, 50, 40);
            chk('f.child1', e, f1, 50, 0, 50, 40);

            // ---- g) without web defaults -> an UNSET direction defaults to column
            e = eng(true);
            var cg:Object = e.createConfig(0, false);
            var rg:Object = root(e, cg, 200, 100);
            var g0:Object = child(e, cg, rg, 0, 50, 40);
            var g1:Object = child(e, cg, rg, 1, 50, 40);
            e.calculate(rg, 200, 100, LayoutConstants.DIR_LTR);
            chk('g.child0', e, g0, 0,  0, 50, 40);
            chk('g.child1', e, g1, 0, 40, 50, 40);
        }

        // ---- builders for the extended cases -----------------------------

        private function kidW(e:LayoutEngine, cfg:Object, p:Object, i:int, w:Number):Object
        {
            var c:Object = e.createNode(cfg);
            e.insertChild(p, c, i);
            e.setSize(c, LayoutConstants.AXIS_WIDTH, w, LayoutConstants.UNIT_POINT);
            return c;
        }

        // row 200x100 pad10, 3 kids 30x10, justify `j`, optional COLUMN gap.
        private function row3(j:int, g:Number):Array
        {
            var e:LayoutEngine = eng(true);
            var cfg:Object = e.createConfig(0, true);
            var r:Object = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            if (g > 0) e.setGap(r, LayoutConstants.GUTTER_COLUMN, g, LayoutConstants.UNIT_POINT);
            e.setJustifyContent(r, j);
            var c0:Object = child(e, cfg, r, 0, 30, 10);
            child(e, cfg, r, 1, 30, 10);
            var c2:Object = child(e, cfg, r, 2, 30, 10);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            return [e, c0, c2];
        }

        // row 200x100 pad10 align-items `al`; 2 kids w30; kidH <= 0 -> auto h.
        private function alignRow2(al:int, kidH:Number):Array
        {
            var e:LayoutEngine = eng(true);
            var cfg:Object = e.createConfig(0, true);
            var r:Object = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            e.setAlignItems(r, al);
            var c0:Object;
            var c1:Object;
            if (kidH > 0)
            {
                c0 = child(e, cfg, r, 0, 30, kidH);
                c1 = child(e, cfg, r, 1, 30, kidH);
            }
            else
            {
                c0 = kidW(e, cfg, r, 0, 30);
                c1 = kidW(e, cfg, r, 1, 30);
            }
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            return [e, c0, c1];
        }

        // row 200x200 pad10 wrap, `n` kids of kw x kh, gap(all) g.
        private function wrapRow2(ac:int, useAc:Boolean, rev:Boolean,
                                  n:int, kw:Number, kh:Number, g:Number):Array
        {
            var e:LayoutEngine = eng(true);
            var cfg:Object = e.createConfig(0, true);
            var r:Object = root(e, cfg, 200, 200);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            if (g > 0) e.setGap(r, LayoutConstants.GUTTER_ALL, g, LayoutConstants.UNIT_POINT);
            if (rev) e.setFlexWrap(r, LayoutConstants.WRAP_WRAP_REVERSE);
            else e.setFlexWrap(r, LayoutConstants.WRAP_WRAP);
            if (useAc) e.setAlignContent(r, ac);
            var out:Array = [e];
            var i:int;
            for (i = 0; i < n; i++) { out.push(child(e, cfg, r, i, kw, kh)); }
            e.calculate(r, 200, 200, LayoutConstants.DIR_LTR);
            return out;
        }

        // The extended cases: names / order / numbers identical to the frozen
        // spec (checks 17..105). Inline on purpose -- see the file header.
        private function runExt():void
        {
            var e:LayoutEngine;
            var cfg:Object;
            var r:Object;

            // ---- h) justify-content (6 values) --------------------------
            var h1:Array = row3(LayoutConstants.JUSTIFY_FLEX_START, 0);
            chk('h1.justifyFlexStart',  h1[0], h1[1],  10, 10, 30, 10);
            chk('h1.justifyFlexStart2', h1[0], h1[2],  70, 10, 30, 10);
            var h2:Array = row3(LayoutConstants.JUSTIFY_CENTER, 0);
            chk('h2.justifyCenter',  h2[0], h2[1],  55, 10, 30, 10);
            chk('h2.justifyCenter2', h2[0], h2[2], 115, 10, 30, 10);
            var h3:Array = row3(LayoutConstants.JUSTIFY_FLEX_END, 0);
            chk('h3.justifyFlexEnd',  h3[0], h3[1], 100, 10, 30, 10);
            chk('h3.justifyFlexEnd2', h3[0], h3[2], 160, 10, 30, 10);
            var h4:Array = row3(LayoutConstants.JUSTIFY_SPACE_BETWEEN, 0);
            chk('h4.justifySpaceBetween',  h4[0], h4[1],  10, 10, 30, 10);
            chk('h4.justifySpaceBetween2', h4[0], h4[2], 160, 10, 30, 10);
            var h5:Array = row3(LayoutConstants.JUSTIFY_SPACE_AROUND, 0);
            chk('h5.justifySpaceAround',  h5[0], h5[1],  25, 10, 30, 10);
            chk('h5.justifySpaceAround2', h5[0], h5[2], 145, 10, 30, 10);
            var h6:Array = row3(LayoutConstants.JUSTIFY_SPACE_EVENLY, 0);
            chk('h6.justifySpaceEvenly',  h6[0], h6[1],  32.5, 10, 30, 10);
            chk('h6.justifySpaceEvenly2', h6[0], h6[2], 137.5, 10, 30, 10);

            // ---- i) justify + gap -------------------------------------
            var i1:Array = row3(LayoutConstants.JUSTIFY_SPACE_BETWEEN, 5);
            chk('i1.justifyGapBetween',  i1[0], i1[1],  10, 10, 30, 10);
            chk('i1.justifyGapBetween2', i1[0], i1[2], 160, 10, 30, 10);
            var i2:Array = row3(LayoutConstants.JUSTIFY_SPACE_AROUND, 5);
            chk('i2.justifyGapAround',  i2[0], i2[1],  23.3333, 10, 30, 10);
            chk('i2.justifyGapAround2', i2[0], i2[2], 146.6667, 10, 30, 10);
            var i3:Array = row3(LayoutConstants.JUSTIFY_SPACE_EVENLY, 5);
            chk('i3.justifyGapEvenly',  i3[0], i3[1],  30, 10, 30, 10);
            chk('i3.justifyGapEvenly2', i3[0], i3[2], 140, 10, 30, 10);

            // ---- j) align-items / align-self ---------------------------
            var j1:Array = alignRow2(LayoutConstants.ALIGN_FLEX_START, 10);
            chk('j1.alignStart',  j1[0], j1[1], 10, 10, 30, 10);
            chk('j1.alignStart2', j1[0], j1[2], 40, 10, 30, 10);
            var j2:Array = alignRow2(LayoutConstants.ALIGN_CENTER, 10);
            chk('j2.alignCenter',  j2[0], j2[1], 10, 45, 30, 10);
            chk('j2.alignCenter2', j2[0], j2[2], 40, 45, 30, 10);
            var j3:Array = alignRow2(LayoutConstants.ALIGN_FLEX_END, 10);
            chk('j3.alignEnd',  j3[0], j3[1], 10, 80, 30, 10);
            chk('j3.alignEnd2', j3[0], j3[2], 40, 80, 30, 10);
            var j4:Array = alignRow2(LayoutConstants.ALIGN_STRETCH, 0);
            chk('j4.alignStretch',  j4[0], j4[1], 10, 10, 30, 80);
            chk('j4.alignStretch2', j4[0], j4[2], 40, 10, 30, 80);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            e.setAlignItems(r, LayoutConstants.ALIGN_FLEX_START);
            var j50:Object = child(e, cfg, r, 0, 30, 10);
            e.setAlignSelf(j50, LayoutConstants.ALIGN_CENTER);
            var j51:Object = child(e, cfg, r, 1, 30, 10);
            e.setAlignSelf(j51, LayoutConstants.ALIGN_FLEX_END);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('j5.alignSelfCenter', e, j50, 10, 45, 30, 10);
            chk('j5.alignSelfEnd',    e, j51, 40, 80, 30, 10);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            e.setAlignItems(r, LayoutConstants.ALIGN_FLEX_START);
            var j60:Object = kidW(e, cfg, r, 0, 30);
            e.setAlignSelf(j60, LayoutConstants.ALIGN_STRETCH);
            var j61:Object = child(e, cfg, r, 1, 30, 10);
            e.setAlignSelf(j61, LayoutConstants.ALIGN_AUTO);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('j6.alignSelfStretch', e, j60, 10, 10, 30, 80);
            chk('j6.alignSelfInherit', e, j61, 40, 10, 30, 10);

            // ---- k) wrap / align-content / wrap-reverse --------------
            var k1:Array = wrapRow2(LayoutConstants.ALIGN_FLEX_START, true, false, 5, 60, 40, 5);
            chk('k1.wrapRow0', k1[0], k1[1], 10,  10, 60, 40);
            chk('k1.wrapRow1', k1[0], k1[2], 75,  10, 60, 40);
            chk('k1.wrapRow2', k1[0], k1[3], 10,  55, 60, 40);
            chk('k1.wrapRow3', k1[0], k1[4], 75,  55, 60, 40);
            chk('k1.wrapRow4', k1[0], k1[5], 10, 100, 60, 40);
            // k2 pins the WEB DEFAULT align-content = stretch, and uses a NARROW
            // container (100 wide) so every kid gets its own line.
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 100, 200);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            e.setFlexWrap(r, LayoutConstants.WRAP_WRAP);
            var k20:Object = child(e, cfg, r, 0, 60, 40);
            var k21:Object = child(e, cfg, r, 1, 60, 40);
            var k22:Object = child(e, cfg, r, 2, 60, 40);
            var k23:Object = child(e, cfg, r, 3, 60, 40);
            e.calculate(r, 100, 200, LayoutConstants.DIR_LTR);
            chk('k2.alignContentDefaultStretch0', e, k20, 10,  10, 60, 40);
            chk('k2.alignContentDefaultStretch1', e, k21, 10,  55, 60, 40);
            chk('k2.alignContentDefaultStretch2', e, k22, 10, 100, 60, 40);
            chk('k2.alignContentDefaultStretch3', e, k23, 10, 145, 60, 40);
            var k3:Array = wrapRow2(LayoutConstants.ALIGN_SPACE_BETWEEN, true, false, 6, 90, 40, 0);
            chk('k3.acBetween0', k3[0], k3[1], 10,  10, 90, 40);
            chk('k3.acBetween1', k3[0], k3[3], 10,  80, 90, 40);
            chk('k3.acBetween2', k3[0], k3[5], 10, 150, 90, 40);
            var k4:Array = wrapRow2(LayoutConstants.ALIGN_CENTER, true, false, 6, 90, 40, 0);
            chk('k4.acCenter0', k4[0], k4[1], 10,  40, 90, 40);
            chk('k4.acCenter1', k4[0], k4[3], 10,  80, 90, 40);
            chk('k4.acCenter2', k4[0], k4[5], 10, 120, 90, 40);
            var k5:Array = wrapRow2(LayoutConstants.ALIGN_FLEX_END, true, false, 6, 90, 40, 0);
            chk('k5.acEnd0', k5[0], k5[1], 10,  70, 90, 40);
            chk('k5.acEnd1', k5[0], k5[3], 10, 110, 90, 40);
            chk('k5.acEnd2', k5[0], k5[5], 10, 150, 90, 40);
            var k6:Array = wrapRow2(LayoutConstants.ALIGN_SPACE_AROUND, true, false, 6, 90, 40, 0);
            chk('k6.acAround0', k6[0], k6[1], 10,  20, 90, 40);
            chk('k6.acAround1', k6[0], k6[3], 10,  80, 90, 40);
            chk('k6.acAround2', k6[0], k6[5], 10, 140, 90, 40);
            var k7:Array = wrapRow2(LayoutConstants.ALIGN_FLEX_START, true, true, 6, 60, 40, 5);
            chk('k7.wrapReverse0', k7[0], k7[1], 10, 150, 60, 40);
            chk('k7.wrapReverse2', k7[0], k7[3], 10, 105, 60, 40);
            chk('k7.wrapReverse4', k7[0], k7[5], 10,  60, 60, 40);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 100, 200);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_COLUMN);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            e.setGap(r, LayoutConstants.GUTTER_ALL, 5, LayoutConstants.UNIT_POINT);
            e.setFlexWrap(r, LayoutConstants.WRAP_WRAP);
            e.setAlignContent(r, LayoutConstants.ALIGN_FLEX_START);
            var kc0:Object = child(e, cfg, r, 0, 60, 40);
            var kc1:Object = child(e, cfg, r, 1, 60, 40);
            var kc2:Object = child(e, cfg, r, 2, 60, 40);
            var kc3:Object = child(e, cfg, r, 3, 60, 40);
            var kc4:Object = child(e, cfg, r, 4, 60, 40);
            e.calculate(r, 100, 200, LayoutConstants.DIR_LTR);
            chk('k8.columnWrap0', e, kc0, 10,  10, 60, 40);
            chk('k8.columnWrap1', e, kc1, 10,  55, 60, 40);
            chk('k8.columnWrap2', e, kc2, 10, 100, 60, 40);
            chk('k8.columnWrap3', e, kc3, 10, 145, 60, 40);
            chk('k8.columnWrap4', e, kc4, 75,  10, 60, 40);

            // ---- l) margin -------------------------------------------
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            var l10:Object = child(e, cfg, r, 0, 30, 10);
            e.setMargin(l10, LayoutConstants.EDGE_LEFT, 5, LayoutConstants.UNIT_POINT);
            e.setMargin(l10, LayoutConstants.EDGE_RIGHT, 7, LayoutConstants.UNIT_POINT);
            var l11:Object = child(e, cfg, r, 1, 30, 10);
            e.setMargin(l11, LayoutConstants.EDGE_RIGHT, 3, LayoutConstants.UNIT_POINT);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('l1.marginPoint',  e, l10, 15, 10, 30, 10);
            chk('l1.marginPoint2', e, l11, 52, 10, 30, 10);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            var l20:Object = child(e, cfg, r, 0, 30, 10);
            e.setMargin(l20, LayoutConstants.EDGE_LEFT, 10, LayoutConstants.UNIT_PERCENT);
            e.setMargin(l20, LayoutConstants.EDGE_TOP, 10, LayoutConstants.UNIT_PERCENT);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('l2.marginPercent', e, l20, 28, 28, 30, 10);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            var l30:Object = child(e, cfg, r, 0, 30, 10);
            e.setMargin(l30, LayoutConstants.EDGE_HORIZONTAL, 5, LayoutConstants.UNIT_POINT);
            e.setMargin(l30, LayoutConstants.EDGE_VERTICAL, 4, LayoutConstants.UNIT_POINT);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('l3.marginHV', e, l30, 15, 14, 30, 10);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            var l40:Object = child(e, cfg, r, 0, 30, 10);
            e.setMargin(l40, LayoutConstants.EDGE_START, 8, LayoutConstants.UNIT_POINT);
            var l41:Object = child(e, cfg, r, 1, 30, 10);
            e.setMargin(l41, LayoutConstants.EDGE_END, 6, LayoutConstants.UNIT_POINT);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('l4.marginStart', e, l40,  8, 0, 30, 10);
            chk('l4.marginEnd',   e, l41, 38, 0, 30, 10);

            // ---- m) position relative --------------------------------
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            child(e, cfg, r, 0, 30, 10);
            var m10:Object = child(e, cfg, r, 1, 30, 10);
            e.setPositionType(m10, LayoutConstants.POSITION_RELATIVE);
            e.setPosition(m10, LayoutConstants.EDGE_LEFT, 20, LayoutConstants.UNIT_POINT);
            e.setPosition(m10, LayoutConstants.EDGE_TOP, 5, LayoutConstants.UNIT_POINT);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('m1.relativeInset', e, m10, 60, 15, 30, 10);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            var m20:Object = child(e, cfg, r, 0, 30, 10);
            e.setPositionType(m20, LayoutConstants.POSITION_RELATIVE);
            e.setPosition(m20, LayoutConstants.EDGE_RIGHT, 20, LayoutConstants.UNIT_POINT);
            e.setPosition(m20, LayoutConstants.EDGE_BOTTOM, 5, LayoutConstants.UNIT_POINT);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('m2.relativeNegative', e, m20, -10, 5, 30, 10);

            // ---- n) position absolute --------------------------------
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            e.setBorder(r, LayoutConstants.EDGE_ALL, 5);
            var n10:Object = child(e, cfg, r, 0, 30, 10);
            var n11:Object = child(e, cfg, r, 1, 50, 20);
            e.setPositionType(n11, LayoutConstants.POSITION_ABSOLUTE);
            e.setPosition(n11, LayoutConstants.EDGE_LEFT, 20, LayoutConstants.UNIT_POINT);
            e.setPosition(n11, LayoutConstants.EDGE_TOP, 30, LayoutConstants.UNIT_POINT);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('n1.absoluteFlow',  e, n10, 15, 15, 30, 10);
            chk('n1.absoluteInset', e, n11, 25, 35, 50, 20);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 200);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setBorder(r, LayoutConstants.EDGE_ALL, 10);
            var n20:Object = child(e, cfg, r, 0, 50, 20);
            e.setPositionType(n20, LayoutConstants.POSITION_ABSOLUTE);
            e.setPosition(n20, LayoutConstants.EDGE_RIGHT, 20, LayoutConstants.UNIT_POINT);
            e.setPosition(n20, LayoutConstants.EDGE_BOTTOM, 30, LayoutConstants.UNIT_POINT);
            e.calculate(r, 200, 200, LayoutConstants.DIR_LTR);
            chk('n2.absoluteRightBottom', e, n20, 120, 140, 50, 20);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 200);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            e.setJustifyContent(r, LayoutConstants.JUSTIFY_CENTER);
            e.setAlignItems(r, LayoutConstants.ALIGN_CENTER);
            var n30:Object = child(e, cfg, r, 0, 50, 20);
            e.setPositionType(n30, LayoutConstants.POSITION_ABSOLUTE);
            e.calculate(r, 200, 200, LayoutConstants.DIR_LTR);
            chk('n3.absoluteCentred', e, n30, 75, 90, 50, 20);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setBorder(r, LayoutConstants.EDGE_ALL, 10);
            var n40:Object = child(e, cfg, r, 0, 50, 20);
            e.setPositionType(n40, LayoutConstants.POSITION_ABSOLUTE);
            e.setPosition(n40, LayoutConstants.EDGE_LEFT, 10, LayoutConstants.UNIT_PERCENT);
            e.setPosition(n40, LayoutConstants.EDGE_TOP, 10, LayoutConstants.UNIT_PERCENT);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('n4.absolutePercent', e, n40, 28, 18, 50, 20);

            // ---- o) percent padding / gap ----------------------------
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_PERCENT);
            var o10:Object = child(e, cfg, r, 0, 30, 20);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('o1.percentPadding', e, o10, 20, 20, 30, 20);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            e.setGap(r, LayoutConstants.GUTTER_COLUMN, 10, LayoutConstants.UNIT_PERCENT);
            child(e, cfg, r, 0, 30, 10);
            var o21:Object = child(e, cfg, r, 1, 30, 10);
            var o22:Object = child(e, cfg, r, 2, 30, 10);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('o2.percentGapRow1', e, o21,  58, 10, 30, 10);
            chk('o2.percentGapRow2', e, o22, 106, 10, 30, 10);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 100, 200);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_COLUMN);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            e.setGap(r, LayoutConstants.GUTTER_ROW, 10, LayoutConstants.UNIT_PERCENT);
            child(e, cfg, r, 0, 30, 20);
            var o32:Object = child(e, cfg, r, 1, 30, 20);
            e.calculate(r, 100, 200, LayoutConstants.DIR_LTR);
            chk('o3.percentGapCol', e, o32, 10, 48, 30, 20);

            // ---- p) reverse directions / RTL -------------------------
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW_REVERSE);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            e.setGap(r, LayoutConstants.GUTTER_ALL, 5, LayoutConstants.UNIT_POINT);
            var p10:Object = child(e, cfg, r, 0, 30, 10);
            e.setMargin(p10, LayoutConstants.EDGE_LEFT, 4, LayoutConstants.UNIT_POINT);
            var p11:Object = child(e, cfg, r, 1, 30, 10);
            var p12:Object = child(e, cfg, r, 2, 30, 10);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('p1.rowReverse0', e, p10, 160, 10, 30, 10);
            chk('p1.rowReverse1', e, p11, 121, 10, 30, 10);
            chk('p1.rowReverse2', e, p12,  86, 10, 30, 10);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 100, 200);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_COLUMN_REVERSE);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            e.setGap(r, LayoutConstants.GUTTER_ALL, 5, LayoutConstants.UNIT_POINT);
            var p20:Object = child(e, cfg, r, 0, 30, 10);
            var p21:Object = child(e, cfg, r, 1, 30, 10);
            var p22:Object = child(e, cfg, r, 2, 30, 10);
            e.calculate(r, 100, 200, LayoutConstants.DIR_LTR);
            chk('p2.columnReverse0', e, p20, 10, 180, 30, 10);
            chk('p2.columnReverse1', e, p21, 10, 165, 30, 10);
            chk('p2.columnReverse2', e, p22, 10, 150, 30, 10);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            var p30:Object = child(e, cfg, r, 0, 30, 10);
            var p31:Object = child(e, cfg, r, 1, 30, 10);
            e.calculate(r, 200, 100, LayoutConstants.DIR_RTL);
            chk('p3.rtlRow0', e, p30, 170, 0, 30, 10);
            chk('p3.rtlRow1', e, p31, 140, 0, 30, 10);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            var p40:Object = child(e, cfg, r, 0, 30, 10);
            e.setMargin(p40, LayoutConstants.EDGE_START, 8, LayoutConstants.UNIT_POINT);
            var p41:Object = child(e, cfg, r, 1, 30, 10);
            e.calculate(r, 200, 100, LayoutConstants.DIR_RTL);
            chk('p4.rtlStart',  e, p40, 162, 0, 30, 10);
            chk('p4.rtlStart2', e, p41, 132, 0, 30, 10);
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_START, 4, LayoutConstants.UNIT_POINT);
            var p50:Object = child(e, cfg, r, 0, 30, 10);
            e.setMargin(p50, LayoutConstants.EDGE_START, 8, LayoutConstants.UNIT_POINT);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('p5.ltrStart', e, p50, 12, 0, 30, 10);

            // ---- q) overflow (stored, never applied) -----------------
            e = eng(true);
            cfg = e.createConfig(0, true);
            r = root(e, cfg, 200, 100);
            e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
            e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
            e.setOverflow(r, LayoutConstants.OVERFLOW_HIDDEN);
            var q10:Object = childAuto(e, cfg, r, 0);
            e.setFlex(q10, 0, 0, 300, LayoutConstants.UNIT_POINT);
            e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
            chk('q1.overflowRoot',  e, r,    0,  0, 200, 100);
            chk('q1.overflowChild', e, q10, 10, 10, 300,  80);
        }

        // `adl` gives an AIR app no console on Windows, so the file IS the
        // result channel. Written next to app-air.xml (the app directory).
        private function writeOut():void
        {
            var dir:String = File.applicationDirectory.nativePath;
            var f:File = new File(dir + File.separator + 'air-out.txt');
            var fs:FileStream = new FileStream();
            fs.open(f, FileMode.WRITE);
            fs.writeUTFBytes(out);
            fs.close();
        }
    }
}