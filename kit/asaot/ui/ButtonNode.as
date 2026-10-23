// asaot.ui.ButtonNode -- the description node for a push button (design doc
// section 4.2). `onClick`/`action` come from Control. See BoxNode for why the
// class has the `Node` suffix while the factory is still `button(...)`.
package asaot.ui
{
    import asaot.ui.kind.ButtonWidget;

    public class ButtonNode extends Control
    {
        public var label:String;

        private static var registered:Boolean = false;

        public function ButtonNode(l:String):void
        {
            super("button");
            if (!registered) { registered = true; Widgets.register("button", new ButtonWidget()); }
            this.role = "button";
            this.label = l;
        }
    }
}