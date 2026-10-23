// asaot.ui.Element -- a `Node` that carries accessibility metadata (design doc
// section 4.2/4.3). The metadata is only a SHAPE for now: we store role/name/value
// on the retained node so a future flash.accessibility / U6 pass can materialise
// a real tree. The doc's rule is that a control must SET its role and name; the
// reconciler asserts that rather than silently accepting a nameless control.
package asaot.ui
{
    public class Element extends Node
    {
        public var role:String;
        public var ariaName:String;
        public var ariaValue:*;
        // The design doc's `visible:` opt (section 8) -- an element that is not
        // drawn but still OCCUPIES its laid-out space. That is CSS
        // `visibility:hidden`, not `display:none`, and it maps straight onto the
        // backing object's `visible` flag.
        public var visible:Boolean;

        public function Element(kind:String):void
        {
            super(kind);
            this.role = null;
            this.ariaName = null;
            this.ariaValue = null;
            this.visible = true;
        }
    }
}