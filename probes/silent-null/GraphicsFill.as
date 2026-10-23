// probes/silent-null/GraphicsFill.as -- is the missing fill a Graphics issue?
//
// MEASURED SYMPTOM (tools/pngread.cjs on ui-demo/UiDemo-shot-3.png): the demo's
// card (`background: 0xF9FAFB`, `cornerRadii: 12`) and sign-in button
// (`background: 0x2563EB`) paint their 1px border and NO fill:
//
//   row y=284:  x=47 #1d4ed8 (border)   x=48..512 #ffffff (interior, no fill)
//
// The style side is already cleared: probes/silent-null/FillFromAny.as shows
// `StyleRefinement.from({background: 0x2563EB})` resolves to argb=0xFF2563EB, so
// `style.background` is NOT null. Both fill and border are drawn by ONE function
// (`UiNode.drawBox`), which does:
//
//   g.beginFill(bg.rgb(), bg.alpha());
//   g.lineStyle(nz(border.top), borderColor & 0xFFFFFF, 1.0);   <-- AFTER beginFill
//   g.drawRoundRect(...) / g.drawRect(...)
//   g.endFill();
//
// That ordering puts the suspicion on Graphics itself: does a `lineStyle` call
// after `beginFill` discard the pending fill in our rasterizer? Rasterizing via
// BitmapData.draw + getPixels needs no window, so this probe answers it directly
// with a 2x2 matrix (fill x {with,without} border) x {rect, roundRect}.
//
// Every variant draws a 40x40 blue (#2563EB) square with a 1px #1D4ED8 border and
// reports the CENTRE pixel (must be #2563EB) and the EDGE pixel (must be
// #1D4ED8). A variant whose centre reads background-colour has lost its fill.
import flash.display.BitmapData;
import flash.display.Shape;
import flash.display.Sprite;
import flash.geom.Rectangle;

function hex32(v:uint):String
{
    var s:String = v.toString(16);
    while (s.length < 8) s = "0" + s;
    return "0x" + s;
}

function probe(tag:String, border:Boolean, round:Boolean):void
{
    var sp:Sprite = new Sprite();
    var sh:Shape = new Shape();
    sh.graphics.beginFill(0x2563EB);
    if (border) sh.graphics.lineStyle(1, 0x1D4ED8, 1.0);
    if (round) sh.graphics.drawRoundRect(0, 0, 40, 40, 24, 24);
    else sh.graphics.drawRect(0, 0, 40, 40);
    sh.graphics.endFill();
    sp.addChild(sh);

    var bd:BitmapData = new BitmapData(40, 40, true, 0x00000000);
    bd.draw(sp);

    var centre:uint = bd.getPixel32(20, 20);
    var edge:uint = bd.getPixel32(0, 20);     // left border column
    var outside:uint = bd.getPixel32(39, 39);

    var fillOk:Boolean = (centre & 0xFFFFFF) == 0x2563EB;
    var edgeOk:Boolean = !border || (edge & 0xFFFFFF) == 0x1D4ED8;

    trace(tag
        + "  centre=" + hex32(centre) + (fillOk ? " fill=OK " : " fill=LOST")
        + "  edge=" + hex32(edge) + (edgeOk ? " border=OK " : " border=MISSING")
        + "  far=" + hex32(outside));
}

trace("fill=#2563EB (expect centre), border=#1D4ED8 (expect edge col)");
probe("A fill only      rect     ", false, false);
probe("B fill + border  rect     ", true, false);
probe("C fill only      roundRect", false, true);
probe("D fill + border  roundRect", true, true);