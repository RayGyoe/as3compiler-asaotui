// air-check/KitFns.as -- does mxmlc resolve every package-level factory function
// of the toolkit BY FILE NAME?
//
// AS3 rule (measured, not read): `import a.b.f` is resolved by looking for the
// FILE a/b/f.as and requiring a top-level `f` inside it. mxmlc does NOT scan the
// source tree, and -- this is the part my earlier probe got wrong -- the filename
// match is CASE SENSITIVE even on Windows: probes/case-rule/ proved that a file
// `p/Mixed.as` holding `public function mixed()` is rejected for `import p.mixed`
// ("找不到定义 p.mixed"), while `p/lower.as` holding `lower()` compiles.
//
// So this file names every public factory of the toolkit as a function value and
// nothing else, which turns "is each factory reachable by its own name?" into a
// compile-time yes/no per symbol.
//
// EXPECTED (prediction to falsify): the eight factories whose file keeps the
// capitalised name of the class that used to live there -- box(Box.as),
// button(Button.as), checkbox(Checkbox.as), text(Text.as), corners(Corners.as),
// edges(Edges.as), fill(Fill.as), textStyle(TextStyle.as) -- must FAIL, while the
// ones whose file is already lowercase (row, column, label, textField, bindTo,
// px, pct, rem, rems, auto) must succeed.
//
// RUN:
//   AIRSDK_HOME=<AIR SDK root> node tools/mxmlc-check.cjs \
//     --root air-check/KitFns.as --src kit --src seam --out air-check/kit-fns.swf
package
{
    import asaot.ui.bindTo;
    import asaot.ui.box;
    import asaot.ui.button;
    import asaot.ui.checkbox;
    import asaot.ui.column;
    import asaot.ui.label;
    import asaot.ui.row;
    import asaot.ui.text;
    import asaot.ui.textField;
    import asaot.ui.style.auto;
    import asaot.ui.style.corners;
    import asaot.ui.style.edges;
    import asaot.ui.style.fill;
    import asaot.ui.style.pct;
    import asaot.ui.style.px;
    import asaot.ui.style.rem;
    import asaot.ui.style.rems;
    import asaot.ui.style.textStyle;

    public class KitFns
    {
        public function run():Array
        {
            var out:Array = [];
            out.push(box);       out.push(button);   out.push(checkbox);
            out.push(column);    out.push(label);    out.push(row);
            out.push(text);      out.push(textField);out.push(bindTo);
            out.push(auto);      out.push(corners);  out.push(edges);
            out.push(fill);      out.push(pct);      out.push(px);
            out.push(rem);       out.push(rems);     out.push(textStyle);
            return out;
        }
    }
}