// probes/silent-null/FillFromAny.as -- why does `background` never paint?
//
// MEASURED SYMPTOM (tools/pngread.cjs on ui-demo/UiDemo-shot-3.png): the demo's
// card (`background: 0xF9FAFB`) and sign-in button (`background: 0x2563EB`) paint
// their 1px BORDER and nothing else -- the interiors are pure #ffffff:
//
//   row y=284   x 47 = #1d4ed8 (button border) ... x 48..512 = #ffffff (no fill!)
//   col x=280   y 261 = #1d4ed8 ... y 262..306 = #ffffff
//
// `UiNode.drawBox` reads fill and border from the SAME resolved Style, so "border
// yes, fill no" means `style.background == null` while `style.borderColor` is
// fine. Diffing the two code paths in StyleRefinement.from narrows it to one line:
//
//   r.background  = Fill.fromAny(o.background);   // dispatch is `o is Number`
//   r.borderColor = Number(o.borderColor);        // an explicit cast
//
// A numeric property of a boxed object literal may not satisfy `is Number`
// depending on which box tag the frontend gives it, and Fill.fromAny returns null
// for anything it does not recognise -- silently. This probe prints, in order:
// the box tag of the property, each `is` answer, what Fill.fromAny returns, and
// what ends up in the resolved Style.
import asaot.ui.style.Fill;
import asaot.ui.style.StyleRefinement;

var o:Object = { background: 0x2563EB, borderColor: 0x1D4ED8, border: 1 };
var raw:Object = o.background;

trace("typeof raw          = " + typeof raw);
trace("raw is Number       = " + (raw is Number));
trace("raw is int          = " + (raw is int));
trace("raw is uint         = " + (raw is uint));
trace("raw is Object       = " + (raw is Object));
trace("Number(raw)         = " + Number(raw));

var f:Fill = Fill.fromAny(raw);
trace("Fill.fromAny(raw)   = " + (f == null ? "null   <-- SILENT NULL" : ("ok argb=" + f.argb)));

var r:StyleRefinement = StyleRefinement.from(o);
trace("r.background        = " + (r.background == null ? "null   <-- SILENT NULL" : ("ok argb=" + r.background.argb)));
trace("r.borderColor       = " + r.borderColor);
trace("r.borderWidths      = " + (r.borderWidths == null ? "null" : String(r.borderWidths.top)));

// Control: a directly typed Number (not reached through a boxed property).
var direct:Fill = Fill.fromAny(0x2563EB);
trace("Fill.fromAny(int)   = " + (direct == null ? "null   <-- SILENT NULL" : ("ok argb=" + direct.argb)));
