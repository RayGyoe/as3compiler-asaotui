// layout-check/VisualDemo.as -- the VISUAL half of the layout acceptance harness.
//
// CheckMain.as answers "does every rectangle equal the hand-computed number" in
// text. This file answers the other half: "does the engine actually put the
// boxes where it says", by rasterizing the same engine's output into a real
// window you can look at, and -- more importantly -- into a BMP a machine can
// diff (see asaotui/tools/bmpdiff.cjs and reviews/probe-pixel-dump-2026-10-22.md).
//
// It is not a UI toolkit demo. There is no widget layer, no reconciler, no
// Style: every box here is drawn straight from `LayoutEngine.layoutGet`. That is
// the point -- if the picture looks wrong, the ENGINE is wrong, and nothing else
// can be blamed.
//
// WHICH CASES: one panel per feature group of the frozen differential spec
// (diff-check/spec/cases.txt, blocks b/c/d/h/i/j/k/l/m/n), so a glance at the
// picture covers the same surface CheckMain.as asserts numerically.
//
// RUN (native, real window -- needs vendor/{skia,sdl2}):
//   cd as3compiler
//   node src/index.ts ../asaotui/layout-check/VisualDemo.as \
//     ../asaotui/seam/asaot/ui/LayoutConstants.as ../asaotui/seam/asaot/ui/LayoutEngine.as \
//     ../asaotui/seam/asaot/ui/as3/As3LayoutNode.as ../asaotui/seam/asaot/ui/as3/As3LayoutEngine.as \
//     --manifest examples/window.build.example.json -o ../asaotui/layout-check/VisualDemo.exe
//
// The window STAYS OPEN (showWindow blocks until it is closed), so it can be
// screenshotted; roughly a second in, the same frame is also written to
// `visual-demo.bmp` next to this file, which is the machine-checkable artifact.
import asaot.ui.LayoutEngine;
import asaot.ui.LayoutConstants;
import asaot.ui.as3.As3LayoutEngine;
import flash.display.Shape;
import flash.display.Sprite;
import flash.display.BitmapData;
import flash.text.TextField;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

// ---------------------------------------------------------------- canvas
var W:int = 960;
var H:int = 660;
var PAGE:uint = 0xF2F4F8;
var PANEL:uint = 0xFFFFFF;
var EDGE:uint = 0xC9D2E0;
var CAPTION:uint = 0x33415C;
var PAL:Array = [0x2F6FED, 0xE0603C, 0x2FA84F, 0x8A4FD3, 0x0E9AA7];

var host:Sprite = new Sprite();
var stage:Stage = new Stage();
stage.addChild(host);

// The page background is its own sub-Sprite added FIRST, so every panel drawn
// later lands on top of it without any display-index shuffling.
var bgLayer:Sprite = new Sprite();
host.addChild(bgLayer);
var bgShape:Shape = new Shape();
bgShape.graphics.beginFill(PAGE, 1);
bgShape.graphics.drawRect(0, 0, W, H);
bgShape.graphics.endFill();
bgLayer.addChild(bgShape);

// The layout trees are built by hand so that the picture and the assertions come
// from the SAME structure: `node()` mirrors insertChild, and `paint()` walks the
// MY tree while asking the ENGINE for every rectangle.
var eng:LayoutEngine = new As3LayoutEngine();
var cfg:Object = eng.createConfig(0, true); // web defaults, like the toolkit

function node(parent:Object, index:int):Object {
    var h:Object = eng.createNode(cfg);
    var rec:Object = { h: h, kids: [] };
    if (parent != null) {
        eng.insertChild(parent.h, h, index);
        parent.kids.push(rec);
    }
    return rec;
}

function sizeOf(rec:Object, w:Number, h:Number):void {
    eng.setSize(rec.h, LayoutConstants.AXIS_WIDTH, w, LayoutConstants.UNIT_POINT);
    eng.setSize(rec.h, LayoutConstants.AXIS_HEIGHT, h, LayoutConstants.UNIT_POINT);
}

function rect(x:Number, y:Number, w:Number, h:Number, fill:uint, alpha:Number, stroke:int):void {
    var s:Shape = new Shape();
    if (stroke >= 0) s.graphics.lineStyle(1, stroke, 1);
    s.graphics.beginFill(fill, alpha);
    s.graphics.drawRect(x + 0.5, y + 0.5, w, h);
    s.graphics.endFill();
    host.addChild(s);
}

function label(x:Number, y:Number, text:String, color:uint, size:Number):void {
    var tf:TextField = new TextField();
    tf.text = text;
    tf.x = x;
    tf.y = y;
    tf.width = 320;
    tf.height = 20;
    tf.selectable = false;
    host.addChild(tf);
}

// Paint one node's rectangle (in the coordinate frame `ox,oy` is the parent's
// origin, exactly like the rect layoutGet returns) and recurse into the children
// with this node's origin as their frame.
function paint(rec:Object, ox:Number, oy:Number, depth:int):void {
    var o:Array = [];
    eng.layoutGet(rec.h, o);
    var x:Number = ox + o[0];
    var y:Number = oy + o[1];
    var w:Number = o[2];
    var hh:Number = o[3];
    var c:uint = PAL[depth % PAL.length];
    rect(x, y, w, hh, c, 0.16, c);
    var i:int;
    for (i = 0; i < rec.kids.length; i++) paint(rec.kids[i], x, y, depth + 1);
}

// A panel = caption + a framed area; `build` returns the root record, which is
// laid out at exactly the inner area and then painted.
function panel(px:Number, py:Number, pw:Number, ph:Number, title:String):void {
    rect(px, py, pw, ph, PANEL, 1, EDGE);
    label(px + 12, py + 8, title, CAPTION, 12);
}

function inner(px:Number, py:Number, pw:Number, ph:Number):Array {
    return [px + 12, py + 34, pw - 24, ph - 46];
}

// ============================================================ the six panels
var GX:Number = 20;
var GY:Number = 56;
var PW:Number = 300;
var PH:Number = 282;
var GAP:Number = 20;

// ---- panel 1: column + padding + row-gap (spec block b) ----
var p1x:Number = GX;
var p1y:Number = GY;
panel(p1x, p1y, PW, PH, '1) column + padding 16 + row-gap 10');
var i1:Array = inner(p1x, p1y, PW, PH);
var r1:Object = node(null, 0);
sizeOf(r1, i1[2], i1[3]);
eng.setFlexDirection(r1.h, LayoutConstants.FLEX_DIR_COLUMN);
eng.setPadding(r1.h, LayoutConstants.EDGE_ALL, 16, LayoutConstants.UNIT_POINT);
eng.setGap(r1.h, LayoutConstants.GUTTER_ROW, 10, LayoutConstants.UNIT_POINT);
node(r1, 0); eng.setSize(r1.kids[0].h, LayoutConstants.AXIS_HEIGHT, 40, LayoutConstants.UNIT_POINT);
node(r1, 1); eng.setSize(r1.kids[1].h, LayoutConstants.AXIS_HEIGHT, 40, LayoutConstants.UNIT_POINT);
node(r1, 2); eng.setSize(r1.kids[2].h, LayoutConstants.AXIS_HEIGHT, 40, LayoutConstants.UNIT_POINT);
eng.calculate(r1.h, i1[2], i1[3], LayoutConstants.DIR_LTR);
paint(r1, i1[0], i1[1], 0);

// ---- panel 2: row + flex-grow 1:2:3 + basis 0 (spec block c) ----
var p2x:Number = GX + PW + GAP;
var p2y:Number = GY;
panel(p2x, p2y, PW, PH, '2) row + flex-grow 1 : 2 : 3 (basis 0)');
var i2:Array = inner(p2x, p2y, PW, PH);
var r2:Object = node(null, 0);
sizeOf(r2, i2[2], i2[3]);
eng.setFlexDirection(r2.h, LayoutConstants.FLEX_DIR_ROW);
eng.setAlignItems(r2.h, LayoutConstants.ALIGN_FLEX_START);
var g:int;
for (g = 1; g <= 3; g++) {
    node(r2, g - 1);
    eng.setFlex(r2.kids[g - 1].h, g, 1, 0, LayoutConstants.UNIT_POINT);
    eng.setSize(r2.kids[g - 1].h, LayoutConstants.AXIS_HEIGHT, 30 + 20 * g, LayoutConstants.UNIT_POINT);
}
eng.calculate(r2.h, i2[2], i2[3], LayoutConstants.DIR_LTR);
paint(r2, i2[0], i2[1], 0);

// ---- panel 3: justify-content (three strips) ----
var p3x:Number = GX + 2 * (PW + GAP);
var p3y:Number = GY;
panel(p3x, p3y, PW, PH, '3) justify-content');
var i3:Array = inner(p3x, p3y, PW, PH);
var stripW:Number = i3[2];
var stripH:Number = 52;
var js:Array = [LayoutConstants.JUSTIFY_CENTER, LayoutConstants.JUSTIFY_SPACE_BETWEEN,
                LayoutConstants.JUSTIFY_SPACE_EVENLY, LayoutConstants.JUSTIFY_FLEX_END];
var jn:Array = ['center', 'space-between', 'space-evenly', 'flex-end'];
var k:int;
for (k = 0; k < 4; k++) {
    var sy:Number = i3[1] + k * (stripH + 12);
    rect(i3[0], sy, stripW, stripH, 0xEAF0FA, 0.7, -1);
    var r3:Object = node(null, 0);
    sizeOf(r3, stripW, stripH);
    eng.setFlexDirection(r3.h, LayoutConstants.FLEX_DIR_ROW);
    eng.setJustifyContent(r3.h, js[k]);
    eng.setAlignItems(r3.h, LayoutConstants.ALIGN_CENTER);
    var m:int;
    for (m = 0; m < 3; m++) {
        node(r3, m);
        sizeOf(r3.kids[m], 44, 24);
    }
    eng.calculate(r3.h, stripW, stripH, LayoutConstants.DIR_LTR);
    paint(r3, i3[0], sy, 0);
    label(i3[0] + stripW - 130, sy + stripH - 16, String(jn[k]), 0x6B7A99, 11);
}

// ---- panel 4: align-items (four strips) ----
var p4x:Number = GX;
var p4y:Number = GY + PH + GAP;
panel(p4x, p4y, PW, PH, '4) align-items');
var i4:Array = inner(p4x, p4y, PW, PH);
var ais:Array = [LayoutConstants.ALIGN_FLEX_START, LayoutConstants.ALIGN_CENTER,
                 LayoutConstants.ALIGN_FLEX_END, LayoutConstants.ALIGN_STRETCH];
var ain:Array = ['flex-start', 'center', 'flex-end', 'stretch'];
for (k = 0; k < 4; k++) {
    var ay:Number = i4[1] + k * (stripH + 12);
    rect(i4[0], ay, stripW, stripH, 0xEAF0FA, 0.7, -1);
    var r4:Object = node(null, 0);
    sizeOf(r4, stripW, stripH);
    eng.setFlexDirection(r4.h, LayoutConstants.FLEX_DIR_ROW);
    eng.setAlignItems(r4.h, ais[k]);
    eng.setPadding(r4.h, LayoutConstants.EDGE_ALL, 6, LayoutConstants.UNIT_POINT);
    for (m = 0; m < 4; m++) {
        node(r4, m);
        eng.setSize(r4.kids[m].h, LayoutConstants.AXIS_WIDTH, 44, LayoutConstants.UNIT_POINT);
        // deliberately different heights so flex-start/center/flex-end are
        // distinguishable; the last one keeps height auto so `stretch` shows.
        if (m < 3) eng.setSize(r4.kids[m].h, LayoutConstants.AXIS_HEIGHT, 10 + 10 * m, LayoutConstants.UNIT_POINT);
    }
    eng.calculate(r4.h, stripW, stripH, LayoutConstants.DIR_LTR);
    paint(r4, i4[0], ay, 0);
    label(i4[0] + stripW - 130, ay + stripH - 16, String(ain[k]), 0x6B7A99, 11);
}

// ---- panel 5: flex-wrap (spec block k) ----
var p5x:Number = GX + PW + GAP;
var p5y:Number = GY + PH + GAP;
panel(p5x, p5y, PW, PH, '5) row + flex-wrap (7 items of 60x36)');
var i5:Array = inner(p5x, p5y, PW, PH);
var r5:Object = node(null, 0);
sizeOf(r5, i5[2], i5[3]);
eng.setFlexDirection(r5.h, LayoutConstants.FLEX_DIR_ROW);
eng.setFlexWrap(r5.h, LayoutConstants.WRAP_WRAP);
eng.setAlignContent(r5.h, LayoutConstants.ALIGN_FLEX_START);
eng.setGap(r5.h, LayoutConstants.GUTTER_COLUMN, 10, LayoutConstants.UNIT_POINT);
eng.setGap(r5.h, LayoutConstants.GUTTER_ROW, 10, LayoutConstants.UNIT_POINT);
for (m = 0; m < 7; m++) {
    node(r5, m);
    sizeOf(r5.kids[m], 60, 36);
}
eng.calculate(r5.h, i5[2], i5[3], LayoutConstants.DIR_LTR);
paint(r5, i5[0], i5[1], 0);

// ---- panel 6: margins + absolute positioning (spec blocks l/n) ----
var p6x:Number = GX + 2 * (PW + GAP);
var p6y:Number = GY + PH + GAP;
panel(p6x, p6y, PW, PH, '6) margin + position:absolute');
var i6:Array = inner(p6x, p6y, PW, PH);
var r6:Object = node(null, 0);
sizeOf(r6, i6[2], i6[3]);
eng.setFlexDirection(r6.h, LayoutConstants.FLEX_DIR_COLUMN);
eng.setPadding(r6.h, LayoutConstants.EDGE_ALL, 10, LayoutConstants.UNIT_POINT);
eng.setGap(r6.h, LayoutConstants.GUTTER_ROW, 10, LayoutConstants.UNIT_POINT);
// two flow children with asymmetric margins
for (m = 0; m < 2; m++) {
    node(r6, m);
    eng.setSize(r6.kids[m].h, LayoutConstants.AXIS_HEIGHT, 36, LayoutConstants.UNIT_POINT);
    eng.setMargin(r6.kids[m].h, LayoutConstants.EDGE_LEFT, 20 + 30 * m, LayoutConstants.UNIT_POINT);
    eng.setMargin(r6.kids[m].h, LayoutConstants.EDGE_TOP, 6 + 6 * m, LayoutConstants.UNIT_POINT);
}
// one absolute child pinned to the bottom-right of the padding box
node(r6, 2);
eng.setPositionType(r6.kids[2].h, LayoutConstants.POSITION_ABSOLUTE);
sizeOf(r6.kids[2], 90, 44);
eng.setPosition(r6.kids[2].h, LayoutConstants.EDGE_RIGHT, 10, LayoutConstants.UNIT_POINT);
eng.setPosition(r6.kids[2].h, LayoutConstants.EDGE_BOTTOM, 10, LayoutConstants.UNIT_POINT);
eng.calculate(r6.h, i6[2], i6[3], LayoutConstants.DIR_LTR);
paint(r6, i6[0], i6[1], 0);

// ---------------------------------------------------------------- page title
label(20, 18, 'asaot.ui -- As3LayoutEngine: every rectangle below is the ENGINE output (layoutGet), not a mock', CAPTION, 14);

// ---------------------------------------------------------------- evidence
var OUT:String = 'C:/Users/rayle/Desktop/as3compiler-aot/asaotui/layout-check/visual-demo.bmp';

function dumpBmp():void {
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    var px:ByteArray = bd.getPixels(new Rectangle(0, 0, W, H));
    var imgSize:int = W * H * 4;
    var ba:ByteArray = new ByteArray();
    ba.writeByte(0x42); ba.writeByte(0x4D);
    ba.writeByte(54 + imgSize & 255); ba.writeByte((54 + imgSize) >> 8 & 255);
    ba.writeByte((54 + imgSize) >> 16 & 255); ba.writeByte((54 + imgSize) >> 24 & 255);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(54); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(40); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(W & 255); ba.writeByte(W >> 8 & 255); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(H & 255); ba.writeByte(H >> 8 & 255); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(1); ba.writeByte(0);
    ba.writeByte(32); ba.writeByte(0);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(imgSize & 255); ba.writeByte(imgSize >> 8 & 255);
    ba.writeByte(imgSize >> 16 & 255); ba.writeByte(imgSize >> 24 & 255);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    var y:int;
    var x:int;
    for (y = H - 1; y >= 0; y--) {
        for (x = 0; x < W; x++) {
            var i:int = (y * W + x) * 4;
            ba.writeByte(px[i + 3]);
            ba.writeByte(px[i + 2]);
            ba.writeByte(px[i + 1]);
            ba.writeByte(px[i]);
        }
    }
    var f:File = new File(OUT);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba, 0, 0);
    fs.close();
    trace('visual-demo: wrote ' + OUT);
}

function after():void {
    dumpBmp();
    trace('visual-demo: window stays open for inspection / screenshot');
}

setTimeout(after, 1200);
trace('visual-demo: opening ' + W + 'x' + H + ' window');
stage.showWindow(W, H, 'asaot.ui layout-check -- visual');
trace('visual-demo: window closed');