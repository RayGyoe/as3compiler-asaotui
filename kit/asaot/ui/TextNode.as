// asaot.ui.TextNode -- the description node for a run of text (design doc
// section 4.2). See BoxNode for why the class has the `Node` suffix while the
// author-facing factory is still `text(...)`.
package asaot.ui
{
    import asaot.ui.kind.TextWidget;

    public class TextNode extends Element
    {
        public var content:String;

        private static var registered:Boolean = false;

        public function TextNode(c:String):void
        {
            super("text");
            if (!registered) { registered = true; Widgets.register("text", new TextWidget()); }
            this.role = "text";
            this.content = c;
        }
    }
}