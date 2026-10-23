// probes/silent-null/AlphaValue.as -- measure the fill's channel values.
//
// ESTABLISHED BY MEASUREMENT SO FAR:
//   * the demo's card and sign-in button paint their BORDER and no FILL;
//   * Graphics itself is innocent: probes/graphics-order/Order2.as shows all four
//     combinations of {drawRect, drawRoundRect} x {fill-first, line-first} produce
//     a solid #2563eb centre AND a #1d4ed8 border;
//   * the one piece of the demo that DOES paint a fill is the checkbox, and
//     UiNode.paintCheckbox hardcodes the alpha: `g.beginFill(0x2F80ED, 1.0)`.
//     Every piece that does NOT paint goes through UiNode.drawBox, which DERIVES
//     the alpha: `g.beginFill(bg.rgb(), bg.alpha())`.
//
// FILL.ALPHA() reads the top byte of a 0xAARRGGBB number:
//     return Number((uint(this.argb) >>> 24) & 0xFF) / 255.0;
// so a 24-bit RGB literal like `background: 0xF9FAFB` would give alpha 0 --
// invisible -- while the page's `background: 0xFFFFFFFF` gives 255 -> 1.0 and
// paints. That fits every observation EXCEPT one: an earlier probe printed
// `Fill.fromAny(0x2563EB).argb` as 4280640491, i.e. 0xFF2563EB, which would mean
// alpha 1.0. Those two cannot both be true, so this probe prints the value at each
// step (constructor, factory, StyleRefinement.from) for both the 24-bit and the
// 32-bit spelling, plus the derived rgb()/alpha().
import asaot.ui.style.Fill;
import asaot.ui.style.StyleRefinement;

function show(tag:String, f:Fill):void
{
    if (f == null) { trace(tag + " = null"); return; }
    trace(tag + " = argb " + f.argb + " (0x" + f.argb.toString(16) + ")"
        + "  rgb 0x" + f.rgb().toString(16)
        + "  alpha " + f.alpha()
        + (f.alpha() <= 0 ? "   <-- INVISIBLE" : ""));
}

// 1. the field itself, no factory involved
show("Fill.solid(0xF9FAFB).argb  ", Fill.solid(0xF9FAFB));
show("Fill.solid(0x2563EB).argb  ", Fill.solid(0x2563EB));
show("Fill.solid(0xFFFFFFFF)      ", Fill.solid(0xFFFFFFFF));

// 2. the factory actually used by StyleRefinement.from  (number passed directly)
show("Fill.fromAny(0xF9FAFB)      ", Fill.fromAny(0xF9FAFB));
show("Fill.fromAny(0xFFFFFFFF)    ", Fill.fromAny(0xFFFFFFFF));

// 3. the same, through a boxed object property -- what StyleRefinement.from sees
var o:Object = { background: 0xF9FAFB };
show("Fill.fromAny(o.background)  ", Fill.fromAny(o.background));

// 4. end to end: the exact shape of the demo's CARD and SIGNIN declarations
var card:StyleRefinement = StyleRefinement.from({
    flexDirection: "column", padding: 18, gap: 12, size: [0.5, null],
    background: 0xF9FAFB, border: 1, borderColor: 0xE5E7EB, cornerRadii: 12
});
var signin:StyleRefinement = StyleRefinement.from({
    size: [0.5, 46],
    background: 0x2563EB, border: 1, borderColor: 0x1D4ED8, cornerRadii: 8
});
var page:StyleRefinement = StyleRefinement.from({ background: 0xFFFFFFFF, padding: 28 });

show("CARD.background   ", card.background);
show("SIGNIN.background ", signin.background);
show("PAGE.background   ", page.background);
trace("CARD.borderColor  = 0x" + card.borderColor.toString(16)
    + "   cornerRadii.topLeft = " + (card.cornerRadii == null ? "null" : String(card.cornerRadii.topLeft)));