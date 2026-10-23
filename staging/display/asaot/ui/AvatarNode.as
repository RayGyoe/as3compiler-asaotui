// asaot.ui.AvatarNode -- a circular identity chip showing 1-2 initials.
//
// Not focusable (role "img", no press). `name` is the source for the initials;
// `tone` is a DECORATION selecting the circle colour. The diameter is a STYLE
// concern (`style: { size: [48, 48] }`), never derived from the name, so a name
// change must not reflow.
package asaot.ui
{
    import asaot.ui.kind.AvatarWidget;

    public class AvatarNode extends Control
    {
        public var name:String;
        // "neutral" | "info" | "danger"
        public var tone:String;

        private static var registered:Boolean = false;

        public function AvatarNode(nm:String):void
        {
            super("avatar");
            if (!registered) { registered = true; Widgets.register("avatar", new AvatarWidget()); }
            this.role = "img";
            this.tabEnabled = false;
            this.name = nm;
            this.tone = "neutral";
        }
    }
}