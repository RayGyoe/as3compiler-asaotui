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
        // null means "use the resolver's default direction" (column); `row()`
        // and `column()` set it explicitly.
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
            this.direction = "column";
        }
    }
}