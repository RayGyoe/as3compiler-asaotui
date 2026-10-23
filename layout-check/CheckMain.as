// layout-check/CheckMain.as -- the U1 pure-AS3 layout acceptance harness.
//
// Runs the five hand-computed cases from u1-prototype/check-layout.md section 3
// against asaot.ui.as3.As3LayoutEngine, THROUGH OUR OWN AOT COMPILER, and
// prints got (l,t,w,h) vs want for every node. EPS = 0.01 (the same tolerance
// the U1 prototype pinned). All pass -> the process exits 0; any failure ->
// `throw` aborts (non-zero exit). The assertions are never relaxed or skipped.
//
// calculate() is handed the ROOT'S REAL available size (not NaN -- NaN is only
// for asking for an intrinsic size, which would change the root's own box).
import asaot.ui.LayoutEngine;
import asaot.ui.LayoutConstants;
import asaot.ui.as3.As3LayoutEngine;

var EPS:Number = 0.01;
var gChecks:int = 0;
var gFails:int = 0;

function fmt(x:Number):String { return x.toFixed(2); }

function chk(name:String, eng:LayoutEngine, n:Object,
             wl:Number, wt:Number, ww:Number, wh:Number):void
{
    var o:Array = [];
    eng.layoutGet(n, o);
    var ol:Number = o[0];
    var ot:Number = o[1];
    var ow:Number = o[2];
    var oh:Number = o[3];
    var ok:Boolean = Math.abs(ol - wl) <= EPS
        && Math.abs(ot - wt) <= EPS
        && Math.abs(ow - ww) <= EPS
        && Math.abs(oh - wh) <= EPS;
    gChecks++;
    var line:String = name + '  got (' + fmt(ol) + ',' + fmt(ot) + ',' + fmt(ow) + ',' + fmt(oh)
        + ')  want (' + fmt(wl) + ',' + fmt(wt) + ',' + fmt(ww) + ',' + fmt(wh) + ')';
    if (ok)
    {
        trace('  OK   ' + line);
    }
    else
    {
        gFails++;
        trace('  FAIL ' + line);
    }
}

// Assert that a style value the pure-AS3 subset does NOT implement THROWS
// loudly (never a silent wrong layout). The native engine implements some of
// these (display / aspect-ratio / baseline); the subset refuses instead of
// quietly aliasing. Counts one check either way.
function chkThrows(name:String, run:Function):void
{
    gChecks++;
    var threw:Boolean = false;
    try { run(); } catch (e:Error) { threw = true; }
    if (threw) trace('  OK   ' + name + ' (throws as documented)');
    else { gFails++; trace('  FAIL ' + name + ' expected an explicit throw'); }
}

function mkEng():LayoutEngine { return new As3LayoutEngine(); }

function mkRootEx(eng:LayoutEngine, w:Number, h:Number, web:Boolean):Object
{
    var cfg:Object = eng.createConfig(0, web);
    var r:Object = eng.createNode(cfg);
    eng.setSize(r, LayoutConstants.AXIS_WIDTH,  w, LayoutConstants.UNIT_POINT);
    eng.setSize(r, LayoutConstants.AXIS_HEIGHT, h, LayoutConstants.UNIT_POINT);
    return r;
}

// The UI toolkit asks for web defaults everywhere (CSS/GPUI-style), which is
// what every case above assumes.
function mkRoot(eng:LayoutEngine, w:Number, h:Number):Object
{
    return mkRootEx(eng, w, h, true);
}

function mkChild(eng:LayoutEngine, parent:Object, index:int):Object
{
    var cfg:Object = eng.createConfig(0, true);
    var c:Object = eng.createNode(cfg);
    eng.insertChild(parent, c, index);
    return c;
}

function sized(eng:LayoutEngine, c:Object, w:Number, h:Number):void
{
    eng.setSize(c, LayoutConstants.AXIS_WIDTH,  w, LayoutConstants.UNIT_POINT);
    eng.setSize(c, LayoutConstants.AXIS_HEIGHT, h, LayoutConstants.UNIT_POINT);
}

// ---- builders for the extended (P1..P8) cases -----------------------------
// Each returns [engine, child0, child1, ...] so a check can name one child.

// row 200x100 pad10, 3 kids 30x10, justify `j`, optional COLUMN gap `g`.
function justifyRow(j:int, g:Number):Array
{
    var e:LayoutEngine = mkEng();
    var r:Object = mkRoot(e, 200, 100);
    e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
    e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
    if (g > 0) e.setGap(r, LayoutConstants.GUTTER_COLUMN, g, LayoutConstants.UNIT_POINT);
    e.setJustifyContent(r, j);
    var a:Object = mkChild(e, r, 0); sized(e, a, 30, 10);
    var b:Object = mkChild(e, r, 1); sized(e, b, 30, 10);
    var c:Object = mkChild(e, r, 2); sized(e, c, 30, 10);
    e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
    return [e, a, c];
}

// row 200x100 pad10 align-items `al`; kidH == 0 leaves the height auto.
function alignRow(al:int, kidH:Number):Array
{
    var e:LayoutEngine = mkEng();
    var r:Object = mkRoot(e, 200, 100);
    e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
    e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
    e.setAlignItems(r, al);
    var a:Object = mkChild(e, r, 0);
    e.setSize(a, LayoutConstants.AXIS_WIDTH, 30, LayoutConstants.UNIT_POINT);
    if (kidH > 0) e.setSize(a, LayoutConstants.AXIS_HEIGHT, kidH, LayoutConstants.UNIT_POINT);
    var b:Object = mkChild(e, r, 1);
    e.setSize(b, LayoutConstants.AXIS_WIDTH, 30, LayoutConstants.UNIT_POINT);
    if (kidH > 0) e.setSize(b, LayoutConstants.AXIS_HEIGHT, kidH, LayoutConstants.UNIT_POINT);
    e.calculate(r, 200, 100, LayoutConstants.DIR_LTR);
    return [e, a, b];
}

// row 200x200 pad10 wrap (or wrap-reverse), align-content `ac`, `n` kids of
// `kw`x`kh`, gap(all) `g` (0 == no gap). A non-zero main gap participates in
// LINE BREAKING, so it can change how many items fit per line.
function wrapRow(ac:int, reverse:Boolean, n:int, kw:Number, kh:Number, g:Number):Array
{
    var e:LayoutEngine = mkEng();
    var r:Object = mkRoot(e, 200, 200);
    e.setFlexDirection(r, LayoutConstants.FLEX_DIR_ROW);
    e.setPadding(r, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
    if (g > 0) e.setGap(r, LayoutConstants.GUTTER_ALL, g, LayoutConstants.UNIT_POINT);
    if (reverse) e.setFlexWrap(r, LayoutConstants.WRAP_WRAP_REVERSE);
    else e.setFlexWrap(r, LayoutConstants.WRAP_WRAP);
    e.setAlignContent(r, ac);
    var out:Array = [e];
    var i:int;
    for (i = 0; i < n; i++)
    {
        var c:Object = mkChild(e, r, i);
        sized(e, c, kw, kh);
        out.push(c);
    }
    e.calculate(r, 200, 200, LayoutConstants.DIR_LTR);
    return out;
}

// ======================================================================
trace('=== a) root w=100 h=50 ===');
var ea:LayoutEngine = mkEng();
var ra:Object = mkRoot(ea, 100, 50);
ea.calculate(ra, 100, 50, LayoutConstants.DIR_LTR);
chk('a.root', ea, ra, 0, 0, 100, 50);

// ======================================================================
trace('=== b) column + padding(16) + row-gap(10), 3 children 100x40 ===');
var eb:LayoutEngine = mkEng();
var rb:Object = mkRoot(eb, 200, 300);
eb.setFlexDirection(rb, LayoutConstants.FLEX_DIR_COLUMN);
eb.setPadding(rb, LayoutConstants.EDGE_ALL, 16, LayoutConstants.UNIT_POINT);
eb.setGap(rb, LayoutConstants.GUTTER_ROW, 10, LayoutConstants.UNIT_POINT);
var b0:Object = mkChild(eb, rb, 0); sized(eb, b0, 100, 40);
var b1:Object = mkChild(eb, rb, 1); sized(eb, b1, 100, 40);
var b2:Object = mkChild(eb, rb, 2); sized(eb, b2, 100, 40);
eb.calculate(rb, 200, 300, LayoutConstants.DIR_LTR);
chk('b.root',   eb, rb,  0,   0, 200, 300);
chk('b.child0', eb, b0, 16,  16, 100,  40);
chk('b.child1', eb, b1, 16,  66, 100,  40);
chk('b.child2', eb, b2, 16, 116, 100,  40);

// ======================================================================
trace('=== c) row + grow 1:2:3, basis 0, root 300x100 ===');
var ec:LayoutEngine = mkEng();
var rc:Object = mkRoot(ec, 300, 100);
ec.setFlexDirection(rc, LayoutConstants.FLEX_DIR_ROW);
var c0:Object = mkChild(ec, rc, 0); ec.setFlex(c0, 1, 1, 0, LayoutConstants.UNIT_POINT);
var c1:Object = mkChild(ec, rc, 1); ec.setFlex(c1, 2, 1, 0, LayoutConstants.UNIT_POINT);
var c2:Object = mkChild(ec, rc, 2); ec.setFlex(c2, 3, 1, 0, LayoutConstants.UNIT_POINT);
ec.calculate(rc, 300, 100, LayoutConstants.DIR_LTR);
chk('c.child0', ec, c0,   0, 0,  50, 100);
chk('c.child1', ec, c1,  50, 0, 100, 100);
chk('c.child2', ec, c2, 150, 0, 150, 100);

// ======================================================================
trace('=== d) percent vs parent padding(20)+border(10) ===');
var ed:LayoutEngine = mkEng();
var rd:Object = mkRoot(ed, 200, 100);
ed.setPadding(rd, LayoutConstants.EDGE_ALL, 20, LayoutConstants.UNIT_POINT);
ed.setBorder(rd, LayoutConstants.EDGE_ALL, 10);
var d0:Object = mkChild(ed, rd, 0);
ed.setSize(d0, LayoutConstants.AXIS_WIDTH,  50, LayoutConstants.UNIT_PERCENT);
ed.setSize(d0, LayoutConstants.AXIS_HEIGHT, 50, LayoutConstants.UNIT_PERCENT);
ed.calculate(rd, 200, 100, LayoutConstants.DIR_LTR);
chk('d.root',  ed, rd,  0,  0, 200, 100);
chk('d.child', ed, d0, 30, 30,  70,  20);

// ======================================================================
trace('=== e1) min-width wins over shrink ===');
var ee1:LayoutEngine = mkEng();
var re1:Object = mkRoot(ee1, 100, 50);
ee1.setFlexDirection(re1, LayoutConstants.FLEX_DIR_ROW);
var e10:Object = mkChild(ee1, re1, 0);
ee1.setFlex(e10, 0, 1, 200, LayoutConstants.UNIT_POINT);
ee1.setMinMax(e10, LayoutConstants.AXIS_WIDTH, false, 150, LayoutConstants.UNIT_POINT);
ee1.calculate(re1, 100, 50, LayoutConstants.DIR_LTR);
chk('e1.child', ee1, e10, 0, 0, 150, 50);

// ======================================================================
trace('=== e2) max-width wins over grow ===');
var ee2:LayoutEngine = mkEng();
var re2:Object = mkRoot(ee2, 300, 50);
ee2.setFlexDirection(re2, LayoutConstants.FLEX_DIR_ROW);
var e20:Object = mkChild(ee2, re2, 0);
ee2.setFlex(e20, 1, 1, 100, LayoutConstants.UNIT_POINT);
ee2.setMinMax(e20, LayoutConstants.AXIS_WIDTH, true, 150, LayoutConstants.UNIT_POINT);
ee2.calculate(re2, 300, 50, LayoutConstants.DIR_LTR);
chk('e2.child', ee2, e20, 0, 0, 150, 50);

// ======================================================================
// The config's STYLE DEFAULT. as_ui_yg_config_new's `use_web_defaults` picks
// flex-direction: row (CSS/GPUI) or Yoga's own column, so a node that never
// calls setFlexDirection must still land on the right axis. Pinning BOTH
// directions matters: cases a-e all set a direction explicitly, so a wrong
// default would hide behind them and only show up against Yoga.
trace('=== f) web defaults -> an unset direction defaults to row ===');
var ef:LayoutEngine = mkEng();
var rf:Object = mkRoot(ef, 200, 100);
var f0:Object = mkChild(ef, rf, 0); sized(ef, f0, 50, 40);
var f1:Object = mkChild(ef, rf, 1); sized(ef, f1, 50, 40);
ef.calculate(rf, 200, 100, LayoutConstants.DIR_LTR);
chk('f.child0', ef, f0,  0, 0, 50, 40);
chk('f.child1', ef, f1, 50, 0, 50, 40);

trace('=== g) no web defaults -> an unset direction defaults to column ===');
var eg:LayoutEngine = mkEng();
var rg:Object = mkRootEx(eg, 200, 100, false);
var g0:Object = mkChild(eg, rg, 0); sized(eg, g0, 50, 40);
var g1:Object = mkChild(eg, rg, 1); sized(eg, g1, 50, 40);
eg.calculate(rg, 200, 100, LayoutConstants.DIR_LTR);
chk('g.child0', eg, g0, 0,  0, 50, 40);
chk('g.child1', eg, g1, 0, 40, 50, 40);

// ======================================================================
// EXTENDED CASES (P1..P8). Every number below is HAND-COMPUTED from the Yoga
// algorithm (the formula is written above each block) and then checked against
// THIS engine. They are deliberately NOT read back from a run: an expectation
// that is "whatever the engine printed" cannot fail, and would be worthless.
// The same numbers are independently held by diff-check/spec/cases.txt, where
// Yoga itself computes them.
// ======================================================================

// ---- h) P1 justify-content: row 200x100 pad10, 3 kids 30x10 ----------
// content 180x80; sizeConsumed 90; free 90.
//   flex-start : cursor 10            -> 10 / 40 / 70
//   center     : lead 90/2=45         -> 55 / 85 / 115
//   flex-end   : lead 90              -> 100 / 130 / 160
//   space-btw  : between 90/2=45      -> 10 / 85 / 160
//   space-arnd : lead 90/6=15, gap 30 -> 25 / 85 / 145
//   space-evly : lead 90/4=22.5       -> 32.5 / 85 / 137.5
trace('=== h) justify-content (6 values) ===');
var jh1:Array = justifyRow(LayoutConstants.JUSTIFY_FLEX_START, 0);
chk('h1.justifyFlexStart0',  jh1[0], jh1[1],  10, 10, 30, 10);
chk('h1.justifyFlexStart2',  jh1[0], jh1[2],  70, 10, 30, 10);
var jh2:Array = justifyRow(LayoutConstants.JUSTIFY_CENTER, 0);
chk('h2.justifyCenter0',     jh2[0], jh2[1],  55, 10, 30, 10);
chk('h2.justifyCenter2',     jh2[0], jh2[2], 115, 10, 30, 10);
var jh3:Array = justifyRow(LayoutConstants.JUSTIFY_FLEX_END, 0);
chk('h3.justifyFlexEnd0',    jh3[0], jh3[1], 100, 10, 30, 10);
chk('h3.justifyFlexEnd2',    jh3[0], jh3[2], 160, 10, 30, 10);
var jh4:Array = justifyRow(LayoutConstants.JUSTIFY_SPACE_BETWEEN, 0);
chk('h4.justifySpaceBetween0', jh4[0], jh4[1],  10, 10, 30, 10);
chk('h4.justifySpaceBetween2', jh4[0], jh4[2], 160, 10, 30, 10);
var jh5:Array = justifyRow(LayoutConstants.JUSTIFY_SPACE_AROUND, 0);
chk('h5.justifySpaceAround0', jh5[0], jh5[1],  25, 10, 30, 10);
chk('h5.justifySpaceAround2', jh5[0], jh5[2], 145, 10, 30, 10);
var jh6:Array = justifyRow(LayoutConstants.JUSTIFY_SPACE_EVENLY, 0);
chk('h6.justifySpaceEvenly0', jh6[0], jh6[1],  32.5, 10, 30, 10);
chk('h6.justifySpaceEvenly2', jh6[0], jh6[2], 137.5, 10, 30, 10);

// ---- i) P1 justify + gap: the gap is folded INTO the distribution -----
// sizeConsumed = 90 + 2*5 = 100, free 80. between includes the 5pt gap.
//   space-between: between 5+40      -> 10 / 85 / 160
//   space-around : lead 80/6, gap 5+2*lead -> 23.3333 / 85 / 146.6667
//   space-evenly : lead 80/4=20, gap 5+20  -> 30 / 85 / 140
trace('=== i) justify-content + gap ===');
var ji1:Array = justifyRow(LayoutConstants.JUSTIFY_SPACE_BETWEEN, 5);
chk('i1.justifyGapBetween0', ji1[0], ji1[1],  10, 10, 30, 10);
chk('i1.justifyGapBetween2', ji1[0], ji1[2], 160, 10, 30, 10);
var ji2:Array = justifyRow(LayoutConstants.JUSTIFY_SPACE_AROUND, 5);
chk('i2.justifyGapAround0',  ji2[0], ji2[1],  23.3333, 10, 30, 10);
chk('i2.justifyGapAround2',  ji2[0], ji2[2], 146.6667, 10, 30, 10);
var ji3:Array = justifyRow(LayoutConstants.JUSTIFY_SPACE_EVENLY, 5);
chk('i3.justifyGapEvenly0',  ji3[0], ji3[1],  30, 10, 30, 10);
chk('i3.justifyGapEvenly2',  ji3[0], ji3[2], 140, 10, 30, 10);

// ---- j) P2 align-items / align-self -----------------------------------
// row 200x100 pad10 -> cross content 80; kid cross outer 10.
//   flex-start: 10 ; center: 10+(80-10)/2=45 ; flex-end: 10+70=80 ; stretch: 80
trace('=== j) align-items / align-self ===');
var aj1:Array = alignRow(LayoutConstants.ALIGN_FLEX_START, 10);
chk('j1.alignStart0',  aj1[0], aj1[1], 10, 10, 30, 10);
chk('j1.alignStart1',  aj1[0], aj1[2], 40, 10, 30, 10);
var aj2:Array = alignRow(LayoutConstants.ALIGN_CENTER, 10);
chk('j2.alignCenter0', aj2[0], aj2[1], 10, 45, 30, 10);
chk('j2.alignCenter1', aj2[0], aj2[2], 40, 45, 30, 10);
var aj3:Array = alignRow(LayoutConstants.ALIGN_FLEX_END, 10);
chk('j3.alignEnd0',    aj3[0], aj3[1], 10, 80, 30, 10);
chk('j3.alignEnd1',    aj3[0], aj3[2], 40, 80, 30, 10);
// stretch (auto height) -> the whole line cross = 80.
var aj4:Array = alignRow(LayoutConstants.ALIGN_STRETCH, 0);
chk('j4.alignStretch0', aj4[0], aj4[1], 10, 10, 30, 80);
chk('j4.alignStretch1', aj4[0], aj4[2], 40, 10, 30, 80);
// align-self overrides align-items (container flex-start).
var es:LayoutEngine = mkEng();
var rs:Object = mkRoot(es, 200, 100);
es.setFlexDirection(rs, LayoutConstants.FLEX_DIR_ROW);
es.setPadding(rs, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
es.setAlignItems(rs, LayoutConstants.ALIGN_FLEX_START);
var js0:Object = mkChild(es, rs, 0);
es.setAlignSelf(js0, LayoutConstants.ALIGN_CENTER);
sized(es, js0, 30, 10);
var js1:Object = mkChild(es, rs, 1);
es.setAlignSelf(js1, LayoutConstants.ALIGN_FLEX_END);
sized(es, js1, 30, 10);
es.calculate(rs, 200, 100, LayoutConstants.DIR_LTR);
chk('j5.alignSelfCenter', es, js0, 10, 45, 30, 10);
chk('j5.alignSelfEnd',    es, js1, 40, 80, 30, 10);
// align-self stretch with auto height -> 80; a definite height beats stretch.
var es2:LayoutEngine = mkEng();
var rs2:Object = mkRoot(es2, 200, 100);
es2.setFlexDirection(rs2, LayoutConstants.FLEX_DIR_ROW);
es2.setPadding(rs2, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
es2.setAlignItems(rs2, LayoutConstants.ALIGN_FLEX_START);
var ks0:Object = mkChild(es2, rs2, 0);
es2.setAlignSelf(ks0, LayoutConstants.ALIGN_STRETCH);
es2.setSize(ks0, LayoutConstants.AXIS_WIDTH, 30, LayoutConstants.UNIT_POINT);
var ks1:Object = mkChild(es2, rs2, 1);
es2.setAlignSelf(ks1, LayoutConstants.ALIGN_AUTO);
sized(es2, ks1, 30, 10);
es2.calculate(rs2, 200, 100, LayoutConstants.DIR_LTR);
chk('j6.alignSelfStretch', es2, ks0, 10, 10, 30, 80);
chk('j6.alignSelfInherit', es2, ks1, 40, 10, 30, 10);

// ---- k) P4 wrap / align-content / wrap-reverse ------------------------
// k1: row 200x200 pad10 gap(all)5 wrap ac=flex-start, 5 kids 60x40.
// lines [0,1] [2,3] [4]; lineCross 40; total 40*3+5*2=130 <= 180 inner -> no
// fallback; tops 10, 10+40+5=55, 55+40+5=100.
trace('=== k) flex-wrap / align-content / wrap-reverse ===');
var wk1:Array = wrapRow(LayoutConstants.ALIGN_FLEX_START, false, 5, 60, 40, 5);
chk('k1.wrap0', wk1[0], wk1[1], 10,  10, 60, 40);
chk('k1.wrap1', wk1[0], wk1[2], 75,  10, 60, 40);
chk('k1.wrap2', wk1[0], wk1[3], 10,  55, 60, 40);
chk('k1.wrap3', wk1[0], wk1[4], 75,  55, 60, 40);
chk('k1.wrap4', wk1[0], wk1[5], 10, 100, 60, 40);
// k3: 6 kids 90x40, NO gap -> 2 per line (90+90 = 180 fits exactly) -> 3
// lines; lineCross 40, total 120; remaining 60.
//   space-between: leadPerLine 30        -> 10 / 80 / 150
//   center       : currentLead += 30     -> 40 / 80 / 120
//   flex-end     : currentLead += 60     -> 70 / 110 / 150
//   space-around : leadPerLine 20, +=10  -> 20 / 80 / 140
var wk3:Array = wrapRow(LayoutConstants.ALIGN_SPACE_BETWEEN, false, 6, 90, 40, 0);
chk('k3.acBetween0', wk3[0], wk3[1], 10,  10, 90, 40);
chk('k3.acBetween1', wk3[0], wk3[3], 10,  80, 90, 40);
chk('k3.acBetween2', wk3[0], wk3[5], 10, 150, 90, 40);
var wk4:Array = wrapRow(LayoutConstants.ALIGN_CENTER, false, 6, 90, 40, 0);
chk('k4.acCenter0', wk4[0], wk4[1], 10,  40, 90, 40);
chk('k4.acCenter1', wk4[0], wk4[3], 10,  80, 90, 40);
chk('k4.acCenter2', wk4[0], wk4[5], 10, 120, 90, 40);
var wk5:Array = wrapRow(LayoutConstants.ALIGN_FLEX_END, false, 6, 90, 40, 0);
chk('k5.acEnd0', wk5[0], wk5[1], 10,  70, 90, 40);
chk('k5.acEnd1', wk5[0], wk5[3], 10, 110, 90, 40);
chk('k5.acEnd2', wk5[0], wk5[5], 10, 150, 90, 40);
var wk6:Array = wrapRow(LayoutConstants.ALIGN_SPACE_AROUND, false, 6, 90, 40, 0);
chk('k6.acAround0', wk6[0], wk6[1], 10,  20, 90, 40);
chk('k6.acAround1', wk6[0], wk6[3], 10,  80, 90, 40);
chk('k6.acAround2', wk6[0], wk6[5], 10, 140, 90, 40);
// k7 wrap-reverse: 6 kids 60x40 gap(all)5 -> lines [0,1] [2,3] [4,5]; base tops
// 10/55/100 (cross gap folded in), then mirrored: 200-40-t -> 150 / 105 / 60.
var wk7:Array = wrapRow(LayoutConstants.ALIGN_FLEX_START, true, 6, 60, 40, 5);
chk('k7.wrapReverse0', wk7[0], wk7[1], 10, 150, 60, 40);
chk('k7.wrapReverse2', wk7[0], wk7[3], 10, 105, 60, 40);
chk('k7.wrapReverse4', wk7[0], wk7[5], 10,  60, 60, 40);
// k8 column wrap: column 100x200 pad10 gap(all)5 wrap ac=flex-start, 5 kids
// 60x40. main(content h)=180 -> line0 holds 4 (10,55,100,145); item 5 wraps.
// cross lines: total 60+5+60=125 > 80 -> overflow -> fallback flex-start.
trace('=== k8) column wrap ===');
var ec8:LayoutEngine = mkEng();
var rc8:Object = mkRoot(ec8, 100, 200);
ec8.setFlexDirection(rc8, LayoutConstants.FLEX_DIR_COLUMN);
ec8.setPadding(rc8, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
ec8.setGap(rc8, LayoutConstants.GUTTER_ALL, 5, LayoutConstants.UNIT_POINT);
ec8.setFlexWrap(rc8, LayoutConstants.WRAP_WRAP);
ec8.setAlignContent(rc8, LayoutConstants.ALIGN_FLEX_START);
var kc0:Object = mkChild(ec8, rc8, 0); sized(ec8, kc0, 60, 40);
var kc1:Object = mkChild(ec8, rc8, 1); sized(ec8, kc1, 60, 40);
var kc2:Object = mkChild(ec8, rc8, 2); sized(ec8, kc2, 60, 40);
var kc3:Object = mkChild(ec8, rc8, 3); sized(ec8, kc3, 60, 40);
var kc4:Object = mkChild(ec8, rc8, 4); sized(ec8, kc4, 60, 40);
ec8.calculate(rc8, 100, 200, LayoutConstants.DIR_LTR);
chk('k8.colWrap0', ec8, kc0, 10,  10, 60, 40);
chk('k8.colWrap1', ec8, kc1, 10,  55, 60, 40);
chk('k8.colWrap2', ec8, kc2, 10, 100, 60, 40);
chk('k8.colWrap3', ec8, kc3, 10, 145, 60, 40);
chk('k8.colWrap4', ec8, kc4, 75,  10, 60, 40);

// ---- l) P3 margin -----------------------------------------------------
trace('=== l) margin ===');
// point margins eat main-axis space: c0 left 5+10=15; cursor 10+(30+5+7)=52.
var el:LayoutEngine = mkEng();
var rl:Object = mkRoot(el, 200, 100);
el.setFlexDirection(rl, LayoutConstants.FLEX_DIR_ROW);
el.setPadding(rl, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
var lc0:Object = mkChild(el, rl, 0); sized(el, lc0, 30, 10);
el.setMargin(lc0, LayoutConstants.EDGE_LEFT, 5, LayoutConstants.UNIT_POINT);
el.setMargin(lc0, LayoutConstants.EDGE_RIGHT, 7, LayoutConstants.UNIT_POINT);
var lc1:Object = mkChild(el, rl, 1); sized(el, lc1, 30, 10);
el.setMargin(lc1, LayoutConstants.EDGE_RIGHT, 3, LayoutConstants.UNIT_POINT);
el.calculate(rl, 200, 100, LayoutConstants.DIR_LTR);
chk('l1.marginPoint0', el, lc0, 15, 10, 30, 10);
chk('l1.marginPoint1', el, lc1, 52, 10, 30, 10);
// percent margin resolves on the owner WIDTH even vertically: 10% of 180 = 18.
var el2:LayoutEngine = mkEng();
var rl2:Object = mkRoot(el2, 200, 100);
el2.setFlexDirection(rl2, LayoutConstants.FLEX_DIR_ROW);
el2.setPadding(rl2, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
var lc2:Object = mkChild(el2, rl2, 0); sized(el2, lc2, 30, 10);
el2.setMargin(lc2, LayoutConstants.EDGE_LEFT, 10, LayoutConstants.UNIT_PERCENT);
el2.setMargin(lc2, LayoutConstants.EDGE_TOP, 10, LayoutConstants.UNIT_PERCENT);
el2.calculate(rl2, 200, 100, LayoutConstants.DIR_LTR);
chk('l2.marginPercent', el2, lc2, 28, 28, 30, 10);
// EDGE_HORIZONTAL / EDGE_VERTICAL shorthands.
var el3:LayoutEngine = mkEng();
var rl3:Object = mkRoot(el3, 200, 100);
el3.setFlexDirection(rl3, LayoutConstants.FLEX_DIR_ROW);
el3.setPadding(rl3, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
var lc3:Object = mkChild(el3, rl3, 0); sized(el3, lc3, 30, 10);
el3.setMargin(lc3, LayoutConstants.EDGE_HORIZONTAL, 5, LayoutConstants.UNIT_POINT);
el3.setMargin(lc3, LayoutConstants.EDGE_VERTICAL, 4, LayoutConstants.UNIT_POINT);
el3.calculate(rl3, 200, 100, LayoutConstants.DIR_LTR);
chk('l3.marginHV', el3, lc3, 15, 14, 30, 10);
// EDGE_START/END in LTR map to LEFT/RIGHT; a trailing margin only eats space.
var el4:LayoutEngine = mkEng();
var rl4:Object = mkRoot(el4, 200, 100);
el4.setFlexDirection(rl4, LayoutConstants.FLEX_DIR_ROW);
var lc4:Object = mkChild(el4, rl4, 0); sized(el4, lc4, 30, 10);
el4.setMargin(lc4, LayoutConstants.EDGE_START, 8, LayoutConstants.UNIT_POINT);
var lc5:Object = mkChild(el4, rl4, 1); sized(el4, lc5, 30, 10);
el4.setMargin(lc5, LayoutConstants.EDGE_END, 6, LayoutConstants.UNIT_POINT);
el4.calculate(rl4, 200, 100, LayoutConstants.DIR_LTR);
chk('l4.marginStart', el4, lc4,  8, 0, 30, 10);
chk('l4.marginEnd',   el4, lc5, 38, 0, 30, 10);

// ---- m) P5 position-type relative + inset ------------------------------
// c1 relative left 20 top 5 -> base 40/10 shifted to 60/15.
// right/bottom insets shift NEGATIVELY (relativePosition returns -end).
trace('=== m) position relative ===');
var em:LayoutEngine = mkEng();
var rm:Object = mkRoot(em, 200, 100);
em.setFlexDirection(rm, LayoutConstants.FLEX_DIR_ROW);
em.setPadding(rm, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
var mc0:Object = mkChild(em, rm, 0); sized(em, mc0, 30, 10);
var mc1:Object = mkChild(em, rm, 1); sized(em, mc1, 30, 10);
em.setPositionType(mc1, LayoutConstants.POSITION_RELATIVE);
em.setPosition(mc1, LayoutConstants.EDGE_LEFT, 20, LayoutConstants.UNIT_POINT);
em.setPosition(mc1, LayoutConstants.EDGE_TOP, 5, LayoutConstants.UNIT_POINT);
em.calculate(rm, 200, 100, LayoutConstants.DIR_LTR);
chk('m1.relativeInset', em, mc1, 60, 15, 30, 10);
var em2:LayoutEngine = mkEng();
var rm2:Object = mkRoot(em2, 200, 100);
em2.setFlexDirection(rm2, LayoutConstants.FLEX_DIR_ROW);
em2.setPadding(rm2, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
var mc2:Object = mkChild(em2, rm2, 0); sized(em2, mc2, 30, 10);
em2.setPositionType(mc2, LayoutConstants.POSITION_RELATIVE);
em2.setPosition(mc2, LayoutConstants.EDGE_RIGHT, 20, LayoutConstants.UNIT_POINT);
em2.setPosition(mc2, LayoutConstants.EDGE_BOTTOM, 5, LayoutConstants.UNIT_POINT);
em2.calculate(rm2, 200, 100, LayoutConstants.DIR_LTR);
chk('m2.relativeNegative', em2, mc2, -10, 5, 30, 10);

// ---- n) P5 position-type absolute + inset ------------------------------
// containing block = the padding box (border-box minus border).
trace('=== n) position absolute ===');
var en:LayoutEngine = mkEng();
var rn:Object = mkRoot(en, 200, 100);
en.setFlexDirection(rn, LayoutConstants.FLEX_DIR_ROW);
en.setPadding(rn, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
en.setBorder(rn, LayoutConstants.EDGE_ALL, 5);
var nc0:Object = mkChild(en, rn, 0); sized(en, nc0, 30, 10);
var nc1:Object = mkChild(en, rn, 1); sized(en, nc1, 50, 20);
en.setPositionType(nc1, LayoutConstants.POSITION_ABSOLUTE);
en.setPosition(nc1, LayoutConstants.EDGE_LEFT, 20, LayoutConstants.UNIT_POINT);
en.setPosition(nc1, LayoutConstants.EDGE_TOP, 30, LayoutConstants.UNIT_POINT);
en.calculate(rn, 200, 100, LayoutConstants.DIR_LTR);
chk('n1.absoluteFlow',  en, nc0, 15, 15, 30, 10);
chk('n1.absoluteInset', en, nc1, 25, 35, 50, 20);
// right/bottom: left = 200-50-10-20 = 120; top = 200-20-10-30 = 140.
var en2:LayoutEngine = mkEng();
var rn2:Object = mkRoot(en2, 200, 200);
en2.setFlexDirection(rn2, LayoutConstants.FLEX_DIR_ROW);
en2.setBorder(rn2, LayoutConstants.EDGE_ALL, 10);
var nc2:Object = mkChild(en2, rn2, 0); sized(en2, nc2, 50, 20);
en2.setPositionType(nc2, LayoutConstants.POSITION_ABSOLUTE);
en2.setPosition(nc2, LayoutConstants.EDGE_RIGHT, 20, LayoutConstants.UNIT_POINT);
en2.setPosition(nc2, LayoutConstants.EDGE_BOTTOM, 30, LayoutConstants.UNIT_POINT);
en2.calculate(rn2, 200, 200, LayoutConstants.DIR_LTR);
chk('n2.absoluteRightBottom', en2, nc2, 120, 140, 50, 20);
// no insets -> the parent's justify/align centre it in the padding box.
// x: (180-50)/2 + 10 = 75 ; y: (180-20)/2 + 10 = 90.
var en3:LayoutEngine = mkEng();
var rn3:Object = mkRoot(en3, 200, 200);
en3.setFlexDirection(rn3, LayoutConstants.FLEX_DIR_ROW);
en3.setPadding(rn3, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
en3.setJustifyContent(rn3, LayoutConstants.JUSTIFY_CENTER);
en3.setAlignItems(rn3, LayoutConstants.ALIGN_CENTER);
var nc3:Object = mkChild(en3, rn3, 0); sized(en3, nc3, 50, 20);
en3.setPositionType(nc3, LayoutConstants.POSITION_ABSOLUTE);
en3.calculate(rn3, 200, 200, LayoutConstants.DIR_LTR);
chk('n3.absoluteCentred', en3, nc3, 75, 90, 50, 20);
// percent insets resolve on the containing block (180x80): 10% -> 18 / 8.
var en4:LayoutEngine = mkEng();
var rn4:Object = mkRoot(en4, 200, 100);
en4.setFlexDirection(rn4, LayoutConstants.FLEX_DIR_ROW);
en4.setBorder(rn4, LayoutConstants.EDGE_ALL, 10);
var nc4:Object = mkChild(en4, rn4, 0); sized(en4, nc4, 50, 20);
en4.setPositionType(nc4, LayoutConstants.POSITION_ABSOLUTE);
en4.setPosition(nc4, LayoutConstants.EDGE_LEFT, 10, LayoutConstants.UNIT_PERCENT);
en4.setPosition(nc4, LayoutConstants.EDGE_TOP, 10, LayoutConstants.UNIT_PERCENT);
en4.calculate(rn4, 200, 100, LayoutConstants.DIR_LTR);
chk('n4.absolutePercent', en4, nc4, 28, 18, 50, 20);

// ---- o) P6 percent padding / percent gap -------------------------------
// percent padding on every edge resolves on the owner WIDTH: 10% of 200 = 20.
trace('=== o) percent padding / gap ===');
var eo:LayoutEngine = mkEng();
var ro:Object = mkRoot(eo, 200, 100);
eo.setFlexDirection(ro, LayoutConstants.FLEX_DIR_ROW);
eo.setPadding(ro, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_PERCENT);
var oc0:Object = mkChild(eo, ro, 0); sized(eo, oc0, 30, 20);
eo.calculate(ro, 200, 100, LayoutConstants.DIR_LTR);
chk('o1.percentPadding', eo, oc0, 20, 20, 30, 20);
// main-axis percent gap: 10% of content width 180 = 18 -> 10 / 58 / 106.
var eo2:LayoutEngine = mkEng();
var ro2:Object = mkRoot(eo2, 200, 100);
eo2.setFlexDirection(ro2, LayoutConstants.FLEX_DIR_ROW);
eo2.setPadding(ro2, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
eo2.setGap(ro2, LayoutConstants.GUTTER_COLUMN, 10, LayoutConstants.UNIT_PERCENT);
var oc1:Object = mkChild(eo2, ro2, 0); sized(eo2, oc1, 30, 10);
var oc2:Object = mkChild(eo2, ro2, 1); sized(eo2, oc2, 30, 10);
var oc3:Object = mkChild(eo2, ro2, 2); sized(eo2, oc3, 30, 10);
eo2.calculate(ro2, 200, 100, LayoutConstants.DIR_LTR);
chk('o2.percentGapRow1', eo2, oc2,  58, 10, 30, 10);
chk('o2.percentGapRow2', eo2, oc3, 106, 10, 30, 10);
// column main-axis percent gap: 10% of content height 180 = 18 -> 10 / 48.
var eo3:LayoutEngine = mkEng();
var ro3:Object = mkRoot(eo3, 100, 200);
eo3.setFlexDirection(ro3, LayoutConstants.FLEX_DIR_COLUMN);
eo3.setPadding(ro3, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
eo3.setGap(ro3, LayoutConstants.GUTTER_ROW, 10, LayoutConstants.UNIT_PERCENT);
var oc4:Object = mkChild(eo3, ro3, 0); sized(eo3, oc4, 30, 20);
var oc5:Object = mkChild(eo3, ro3, 1); sized(eo3, oc5, 30, 20);
eo3.calculate(ro3, 100, 200, LayoutConstants.DIR_LTR);
chk('o3.percentGapCol', eo3, oc5, 10, 48, 30, 20);

// ---- p) P7 reverse directions and RTL ---------------------------------
// row-reverse starts at the RIGHT edge; c0's trailing (LEFT) margin 4 adds
// to the advance: right = 10 -> left 160; 10+5+30+4=49 -> 121; 49+5+30=84 -> 86.
trace('=== p) reverse directions / RTL ===');
var ep:LayoutEngine = mkEng();
var rp:Object = mkRoot(ep, 200, 100);
ep.setFlexDirection(rp, LayoutConstants.FLEX_DIR_ROW_REVERSE);
ep.setPadding(rp, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
ep.setGap(rp, LayoutConstants.GUTTER_ALL, 5, LayoutConstants.UNIT_POINT);
var pc0:Object = mkChild(ep, rp, 0); sized(ep, pc0, 30, 10);
ep.setMargin(pc0, LayoutConstants.EDGE_LEFT, 4, LayoutConstants.UNIT_POINT);
var pc1:Object = mkChild(ep, rp, 1); sized(ep, pc1, 30, 10);
var pc2:Object = mkChild(ep, rp, 2); sized(ep, pc2, 30, 10);
ep.calculate(rp, 200, 100, LayoutConstants.DIR_LTR);
chk('p1.rowReverse0', ep, pc0, 160, 10, 30, 10);
chk('p1.rowReverse1', ep, pc1, 121, 10, 30, 10);
chk('p1.rowReverse2', ep, pc2,  86, 10, 30, 10);
// column-reverse 100x200 pad10 gap(all)5 -> tops 180 / 165 / 150.
var ep2:LayoutEngine = mkEng();
var rp2:Object = mkRoot(ep2, 100, 200);
ep2.setFlexDirection(rp2, LayoutConstants.FLEX_DIR_COLUMN_REVERSE);
ep2.setPadding(rp2, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
ep2.setGap(rp2, LayoutConstants.GUTTER_ALL, 5, LayoutConstants.UNIT_POINT);
var pc3:Object = mkChild(ep2, rp2, 0); sized(ep2, pc3, 30, 10);
var pc4:Object = mkChild(ep2, rp2, 1); sized(ep2, pc4, 30, 10);
var pc5:Object = mkChild(ep2, rp2, 2); sized(ep2, pc5, 30, 10);
ep2.calculate(rp2, 100, 200, LayoutConstants.DIR_LTR);
chk('p2.columnReverse0', ep2, pc3, 10, 180, 30, 10);
chk('p2.columnReverse1', ep2, pc4, 10, 165, 30, 10);
chk('p2.columnReverse2', ep2, pc5, 10, 150, 30, 10);
// RTL mirrors row -> row-reverse for the same style: 2 kids 30x10 -> 170 / 140.
var ep3:LayoutEngine = mkEng();
var rp3:Object = mkRoot(ep3, 200, 100);
ep3.setFlexDirection(rp3, LayoutConstants.FLEX_DIR_ROW);
var pc6:Object = mkChild(ep3, rp3, 0); sized(ep3, pc6, 30, 10);
var pc7:Object = mkChild(ep3, rp3, 1); sized(ep3, pc7, 30, 10);
ep3.calculate(rp3, 200, 100, LayoutConstants.DIR_RTL);
chk('p3.rtlRow0', ep3, pc6, 170, 0, 30, 10);
chk('p3.rtlRow1', ep3, pc7, 140, 0, 30, 10);
// RTL: EDGE_START is the RIGHT edge -> margin-start 8 lands on the right.
var ep4:LayoutEngine = mkEng();
var rp4:Object = mkRoot(ep4, 200, 100);
ep4.setFlexDirection(rp4, LayoutConstants.FLEX_DIR_ROW);
var pc8:Object = mkChild(ep4, rp4, 0); sized(ep4, pc8, 30, 10);
ep4.setMargin(pc8, LayoutConstants.EDGE_START, 8, LayoutConstants.UNIT_POINT);
var pc9:Object = mkChild(ep4, rp4, 1); sized(ep4, pc9, 30, 10);
ep4.calculate(rp4, 200, 100, LayoutConstants.DIR_RTL);
chk('p4.rtlStart0', ep4, pc8, 162, 0, 30, 10);
chk('p4.rtlStart1', ep4, pc9, 132, 0, 30, 10);
// LTR: EDGE_START is LEFT; padding-start 4 puts the origin at 4 -> 8+4 = 12.
var ep5:LayoutEngine = mkEng();
var rp5:Object = mkRoot(ep5, 200, 100);
ep5.setFlexDirection(rp5, LayoutConstants.FLEX_DIR_ROW);
ep5.setPadding(rp5, LayoutConstants.EDGE_START, 4, LayoutConstants.UNIT_POINT);
var pca:Object = mkChild(ep5, rp5, 0); sized(ep5, pca, 30, 10);
ep5.setMargin(pca, LayoutConstants.EDGE_START, 8, LayoutConstants.UNIT_POINT);
ep5.calculate(rp5, 200, 100, LayoutConstants.DIR_LTR);
chk('p5.ltrStart', ep5, pca, 12, 0, 30, 10);

// ---- q) P8 overflow is STORED, never applied to the rectangle ----------
// row 200x100 pad10; c0 flex 0 0 basis 300 -> 300 wide, 80 tall (stretch), no
// shrink; overflow:hidden changes NOTHING about the rect.
trace('=== q) overflow (stored only) ===');
var eq:LayoutEngine = mkEng();
var rq:Object = mkRoot(eq, 200, 100);
eq.setFlexDirection(rq, LayoutConstants.FLEX_DIR_ROW);
eq.setPadding(rq, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
eq.setOverflow(rq, LayoutConstants.OVERFLOW_HIDDEN);
var qc0:Object = mkChild(eq, rq, 0);
eq.setFlex(qc0, 0, 0, 300, LayoutConstants.UNIT_POINT);
eq.calculate(rq, 200, 100, LayoutConstants.DIR_LTR);
chk('q1.overflowRoot',  eq, rq,  0,  0, 200, 100);
chk('q1.overflowChild', eq, qc0, 10, 10, 300, 80);

// ======================================================================
// STYLE-SURFACE FIELDS (r..aa). These are the engine setters that the new
// author-facing Style fields map onto in UiNode.applyEngineStyle; the formulas
// are the same flexbox arithmetic as h~q but on fresh, hand-computed cases (a
// different orientation or value), so each new Style field has its own group.
// The three values the pure-AS3 subset does not implement (baseline, static,
// display, aspect-ratio) are pinned as loud throws by chkThrows.
// ======================================================================

// ---- r) justifyContent: column 200x200 pad10, 2 kids 30x10 ------------
// content 180x180, consumed 20, free 160.
//   center        : lead 80            -> top 90 / 100
//   space-between : between 160        -> top 10 / 180
trace('=== r) justifyContent (style field) ===');
var erj:LayoutEngine = mkEng();
var rrj:Object = mkRoot(erj, 200, 200);
erj.setFlexDirection(rrj, LayoutConstants.FLEX_DIR_COLUMN);
erj.setPadding(rrj, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
erj.setJustifyContent(rrj, LayoutConstants.JUSTIFY_CENTER);
var rj0:Object = mkChild(erj, rrj, 0); sized(erj, rj0, 30, 10);
var rj1:Object = mkChild(erj, rrj, 1); sized(erj, rj1, 30, 10);
erj.calculate(rrj, 200, 200, LayoutConstants.DIR_LTR);
chk('r1.justifyCenter0', erj, rj0, 10,  90, 30, 10);
chk('r1.justifyCenter1', erj, rj1, 10, 100, 30, 10);
var erj2:LayoutEngine = mkEng();
var rrj2:Object = mkRoot(erj2, 200, 200);
erj2.setFlexDirection(rrj2, LayoutConstants.FLEX_DIR_COLUMN);
erj2.setPadding(rrj2, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
erj2.setJustifyContent(rrj2, LayoutConstants.JUSTIFY_SPACE_BETWEEN);
var rk0:Object = mkChild(erj2, rrj2, 0); sized(erj2, rk0, 30, 10);
var rk1:Object = mkChild(erj2, rrj2, 1); sized(erj2, rk1, 30, 10);
erj2.calculate(rrj2, 200, 200, LayoutConstants.DIR_LTR);
chk('r2.justifyBetween0', erj2, rk0, 10,  10, 30, 10);
chk('r2.justifyBetween1', erj2, rk1, 10, 180, 30, 10);

// ---- s) alignItems: column 200x100 pad10, kids 30x10 -------------------
// cross = content width 180; center lead (180-30)/2 = 75 -> left 85;
// flex-end left 10+180-30 = 160. Main flex-start -> tops 10 / 20.
trace('=== s) alignItems (style field) ===');
var esa:LayoutEngine = mkEng();
var rsa:Object = mkRoot(esa, 200, 100);
esa.setFlexDirection(rsa, LayoutConstants.FLEX_DIR_COLUMN);
esa.setPadding(rsa, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
esa.setAlignItems(rsa, LayoutConstants.ALIGN_CENTER);
var sa0:Object = mkChild(esa, rsa, 0); sized(esa, sa0, 30, 10);
var sa1:Object = mkChild(esa, rsa, 1); sized(esa, sa1, 30, 10);
esa.calculate(rsa, 200, 100, LayoutConstants.DIR_LTR);
chk('s1.alignCenter0', esa, sa0, 85, 10, 30, 10);
chk('s1.alignCenter1', esa, sa1, 85, 20, 30, 10);
var esa2:LayoutEngine = mkEng();
var rsb:Object = mkRoot(esa2, 200, 100);
esa2.setFlexDirection(rsb, LayoutConstants.FLEX_DIR_COLUMN);
esa2.setPadding(rsb, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
esa2.setAlignItems(rsb, LayoutConstants.ALIGN_FLEX_END);
var sb0:Object = mkChild(esa2, rsb, 0); sized(esa2, sb0, 30, 10);
var sb1:Object = mkChild(esa2, rsb, 1); sized(esa2, sb1, 30, 10);
esa2.calculate(rsb, 200, 100, LayoutConstants.DIR_LTR);
chk('s2.alignEnd0', esa2, sb0, 160, 10, 30, 10);
chk('s2.alignEnd1', esa2, sb1, 160, 20, 30, 10);
// baseline is a native-only value; the subset refuses it.
trace('=== s3) alignItems baseline refuses (AS3 gap) ===');
var esb:LayoutEngine = mkEng();
var rsb2:Object = mkRoot(esb, 200, 100);
chkThrows('s3.alignItemsBaseline', function():void { esb.setAlignItems(rsb2, LayoutConstants.ALIGN_BASELINE); });

// ---- t) alignSelf: column 200x100 pad10, parent align-items flex-start -
// same cross arithmetic as s, but the child overrides it.
//   center   -> left 85 ; flex-end -> left 160 ; stretch (auto width) -> 180.
trace('=== t) alignSelf (style field) ===');
var esf:LayoutEngine = mkEng();
var rsf:Object = mkRoot(esf, 200, 100);
esf.setFlexDirection(rsf, LayoutConstants.FLEX_DIR_COLUMN);
esf.setPadding(rsf, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
esf.setAlignItems(rsf, LayoutConstants.ALIGN_FLEX_START);
var sf0:Object = mkChild(esf, rsf, 0);
esf.setAlignSelf(sf0, LayoutConstants.ALIGN_CENTER); sized(esf, sf0, 30, 10);
var sf1:Object = mkChild(esf, rsf, 1);
esf.setAlignSelf(sf1, LayoutConstants.ALIGN_FLEX_END); sized(esf, sf1, 30, 10);
esf.calculate(rsf, 200, 100, LayoutConstants.DIR_LTR);
chk('t1.alignSelfCenter', esf, sf0, 85, 10, 30, 10);
chk('t1.alignSelfEnd',    esf, sf1, 160, 20, 30, 10);
var esf2:LayoutEngine = mkEng();
var rsf2:Object = mkRoot(esf2, 200, 100);
esf2.setFlexDirection(rsf2, LayoutConstants.FLEX_DIR_COLUMN);
esf2.setPadding(rsf2, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
esf2.setAlignItems(rsf2, LayoutConstants.ALIGN_FLEX_START);
var sg0:Object = mkChild(esf2, rsf2, 0);
esf2.setAlignSelf(sg0, LayoutConstants.ALIGN_STRETCH);
esf2.setSize(sg0, LayoutConstants.AXIS_HEIGHT, 10, LayoutConstants.UNIT_POINT);
esf2.calculate(rsf2, 200, 100, LayoutConstants.DIR_LTR);
chk('t2.alignSelfStretch', esf2, sg0, 10, 10, 180, 10);
// align-self baseline is likewise refused by the subset.
var esf3:LayoutEngine = mkEng();
var rsf3:Object = mkRoot(esf3, 200, 100);
chkThrows('t3.alignSelfBaseline', function():void { esf3.setAlignSelf(rsf3, LayoutConstants.ALIGN_BASELINE); });

// ---- u) alignContent: row 200x200 pad10 wrap, 6 kids 90x40, no gap ----
// 2 per line (90+90 = 180 exactly) -> 3 lines of cross 40 = 120; remaining 60.
//   flex-start: lead 0 -> first-of-line tops 10 / 50 / 90.
trace('=== u) alignContent (style field) ===');
var wu:Array = wrapRow(LayoutConstants.ALIGN_FLEX_START, false, 6, 90, 40, 0);
chk('u1.acStart0', wu[0], wu[1], 10, 10, 90, 40);
chk('u1.acStart1', wu[0], wu[3], 10, 50, 90, 40);
chk('u1.acStart2', wu[0], wu[5], 10, 90, 90, 40);

// ---- v) flexWrap:nowrap: row 200x100 pad10, 4 kids 60x10, no shrink ---
// nowrap keeps one line; flex 0 0 60 pins the 60 width -> cursor advances
// 60 from the content origin 10 -> 10 / 70 / 130 / 190 (the last overflows).
trace('=== v) flexWrap nowrap (style field) ===');
var ev:LayoutEngine = mkEng();
var rv:Object = mkRoot(ev, 200, 100);
ev.setFlexDirection(rv, LayoutConstants.FLEX_DIR_ROW);
ev.setPadding(rv, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
ev.setFlexWrap(rv, LayoutConstants.WRAP_NO_WRAP);
var v0:Object = mkChild(ev, rv, 0); sized(ev, v0, 60, 10); ev.setFlex(v0, 0, 0, 60, LayoutConstants.UNIT_POINT);
var v1:Object = mkChild(ev, rv, 1); sized(ev, v1, 60, 10); ev.setFlex(v1, 0, 0, 60, LayoutConstants.UNIT_POINT);
var v2:Object = mkChild(ev, rv, 2); sized(ev, v2, 60, 10); ev.setFlex(v2, 0, 0, 60, LayoutConstants.UNIT_POINT);
var v3:Object = mkChild(ev, rv, 3); sized(ev, v3, 60, 10); ev.setFlex(v3, 0, 0, 60, LayoutConstants.UNIT_POINT);
ev.calculate(rv, 200, 100, LayoutConstants.DIR_LTR);
chk('v1.nowrap0', ev, v0,  10, 10, 60, 10);
chk('v1.nowrap1', ev, v1,  70, 10, 60, 10);
chk('v1.nowrap2', ev, v2, 130, 10, 60, 10);
chk('v1.nowrap3', ev, v3, 190, 10, 60, 10);

// ---- w) margin: row 200x100 pad10, one kid 30x10 ----------------------
// point all 6  -> left 10+6 = 16, top 10+6 = 16
// percent left 10% of content width 180 = 18 -> left 28
// auto         -> the subset refuses it (native-only)
trace('=== w) margin (style field) ===');
var ew:LayoutEngine = mkEng();
var rw:Object = mkRoot(ew, 200, 100);
ew.setFlexDirection(rw, LayoutConstants.FLEX_DIR_ROW);
ew.setPadding(rw, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
var w0:Object = mkChild(ew, rw, 0); sized(ew, w0, 30, 10);
ew.setMargin(w0, LayoutConstants.EDGE_ALL, 6, LayoutConstants.UNIT_POINT);
ew.calculate(rw, 200, 100, LayoutConstants.DIR_LTR);
chk('w1.marginPoint', ew, w0, 16, 16, 30, 10);
var ew2:LayoutEngine = mkEng();
var rw2:Object = mkRoot(ew2, 200, 100);
ew2.setFlexDirection(rw2, LayoutConstants.FLEX_DIR_ROW);
ew2.setPadding(rw2, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
var w1:Object = mkChild(ew2, rw2, 0); sized(ew2, w1, 30, 10);
ew2.setMargin(w1, LayoutConstants.EDGE_LEFT, 10, LayoutConstants.UNIT_PERCENT);
ew2.calculate(rw2, 200, 100, LayoutConstants.DIR_LTR);
chk('w2.marginPercent', ew2, w1, 28, 10, 30, 10);
var ew3:LayoutEngine = mkEng();
var rw3:Object = mkRoot(ew3, 200, 100);
chkThrows('w3.marginAuto', function():void { ew3.setMargin(rw3, LayoutConstants.EDGE_LEFT, 0, LayoutConstants.UNIT_AUTO); });

// ---- x) position / inset: row 200x100 pad10 --------------------------
// relative left 15 on child0 -> base left 10 shifted to 25
// absolute left 25 top 15 (containing block = padding box, origin = border 5)
//   -> 5+25 = 30, 5+15 = 20 ; the in-flow kid stays at 15/15
trace('=== x) position / inset (style field) ===');
var ex:LayoutEngine = mkEng();
var rx:Object = mkRoot(ex, 200, 100);
ex.setFlexDirection(rx, LayoutConstants.FLEX_DIR_ROW);
ex.setPadding(rx, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
var x0:Object = mkChild(ex, rx, 0); sized(ex, x0, 30, 10);
ex.setPositionType(x0, LayoutConstants.POSITION_RELATIVE);
ex.setPosition(x0, LayoutConstants.EDGE_LEFT, 15, LayoutConstants.UNIT_POINT);
ex.calculate(rx, 200, 100, LayoutConstants.DIR_LTR);
chk('x1.relativeLeft', ex, x0, 25, 10, 30, 10);
var ex2:LayoutEngine = mkEng();
var rx2:Object = mkRoot(ex2, 200, 100);
ex2.setFlexDirection(rx2, LayoutConstants.FLEX_DIR_ROW);
ex2.setPadding(rx2, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
ex2.setBorder(rx2, LayoutConstants.EDGE_ALL, 5);
var xf:Object = mkChild(ex2, rx2, 0); sized(ex2, xf, 30, 10);
var xa:Object = mkChild(ex2, rx2, 1); sized(ex2, xa, 40, 20);
ex2.setPositionType(xa, LayoutConstants.POSITION_ABSOLUTE);
ex2.setPosition(xa, LayoutConstants.EDGE_LEFT, 25, LayoutConstants.UNIT_POINT);
ex2.setPosition(xa, LayoutConstants.EDGE_TOP, 15, LayoutConstants.UNIT_POINT);
ex2.calculate(rx2, 200, 100, LayoutConstants.DIR_LTR);
chk('x2.absoluteFlow',  ex2, xf, 15, 15, 30, 10);
chk('x2.absoluteInset', ex2, xa, 30, 20, 40, 20);
var ex3:LayoutEngine = mkEng();
var rx3:Object = mkRoot(ex3, 200, 100);
chkThrows('x3.positionStatic', function():void { ex3.setPositionType(rx3, LayoutConstants.POSITION_STATIC); });

// ---- y) overflow (stored only): row 200x100 pad10, kid flex 0 0 500 ---
// 500 wide, 80 tall (stretch); overflow changes NOTHING about the rect.
trace('=== y) overflow (style field) ===');
var ey:LayoutEngine = mkEng();
var ry:Object = mkRoot(ey, 200, 100);
ey.setFlexDirection(ry, LayoutConstants.FLEX_DIR_ROW);
ey.setPadding(ry, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
ey.setOverflow(ry, LayoutConstants.OVERFLOW_HIDDEN);
var y0:Object = mkChild(ey, ry, 0);
ey.setFlex(y0, 0, 0, 500, LayoutConstants.UNIT_POINT);
ey.calculate(ry, 200, 100, LayoutConstants.DIR_LTR);
chk('y1.overflowHidden', ey, y0, 10, 10, 500, 80);
var ey2:LayoutEngine = mkEng();
var ry2:Object = mkRoot(ey2, 200, 100);
ey2.setFlexDirection(ry2, LayoutConstants.FLEX_DIR_ROW);
ey2.setPadding(ry2, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
ey2.setOverflow(ry2, LayoutConstants.OVERFLOW_SCROLL);
var y1:Object = mkChild(ey2, ry2, 0);
ey2.setFlex(y1, 0, 0, 500, LayoutConstants.UNIT_POINT);
ey2.calculate(ry2, 200, 100, LayoutConstants.DIR_LTR);
chk('y2.overflowScroll', ey2, y1, 10, 10, 500, 80);

// ---- z) display: the pure-AS3 subset refuses it (native-only) ---------
trace('=== z) display refuses (AS3 gap) ===');
var ez:LayoutEngine = mkEng();
var rz:Object = mkRoot(ez, 200, 100);
chkThrows('z1.displayFlex', function():void { ez.setDisplay(rz, LayoutConstants.DISPLAY_FLEX); });
chkThrows('z2.displayNone', function():void { ez.setDisplay(rz, LayoutConstants.DISPLAY_NONE); });

// ---- aa) aspectRatio: the pure-AS3 subset refuses it (native-only) ----
trace('=== aa) aspectRatio refuses (AS3 gap) ===');
var ea:LayoutEngine = mkEng();
var raa:Object = mkRoot(ea, 200, 100);
chkThrows('aa1.aspectRatio', function():void { ea.setAspectRatio(raa, 2.0); });

// ======================================================================
trace('---- ' + gChecks + ' checks, ' + gFails + ' failures ----');
if (gFails > 0) throw new Error('layout-check: ' + gFails + ' of ' + gChecks + ' FAILED');
trace('RESULT: PASS');