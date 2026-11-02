// asaot.ui.BoxNode -- the description node for a flex container (design doc
// section 4.2, the `Box` row of the hierarchy table).
//
// CLASS NAME NOTE: the doc calls this class `Box`, but mxmlc requires every
// externally-visible definition to live in a file named after it, and the
// top-level factory `box()` needs `box.as`, which cannot coexist with `Box.as`
// on a case-insensitive (Windows) filesystem. The AUTHOR-facing factory is still
// `box(...)`; only this internal class gained the `Node` suffix.
package asaot.ui
{
    import asaot.ui.kind.BoxWidget;

    public class BoxNode extends Element
    {
        // null means "no override": the axis is whatever the resolved style says
        // (a refinement may set `flexDirection`, and a box with no such refinement
        // resolves to the platform default, a column). `row()` and `column()` set it
        // explicitly, and THAT wins over the style -- see the note in BoxWidget.
        public var direction:String;

        private static var registered:Boolean = false;

        public function BoxNode():void
        {
            super("box");
            // Self-registration. The Node class IS the kind, so loading it is
            // exactly when the kind becomes reachable. Done from the constructor
            // (not a static initializer) so there is no class-init-order
            // dependency; the guard costs one bool test per constructed node.
            if (!registered) { registered = true; Widgets.register("box", new BoxWidget()); }
            this.role = "group";
            // NOT "column": a hard default here is what silently overwrote every
            // `style: {flexDirection: "row"}` handed to box() -- the row laid its
            // children out as a COLUMN while the style, the docs and the author all
            // said row. `Theme.resolve` applies this field LAST (it is the override),
            // so a non-null default made the style's axis unobservable. Measured on
            // the select dropdown: `MENU_ITEM` (row, alignItems centre, height 26)
            // put its labels at the ROW TOP, horizontally centred -- the signature of
            // a column, not a row.
            this.direction = null;
        }
    }
}