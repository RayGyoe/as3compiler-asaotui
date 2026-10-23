// asaot.ui.Control -- an Element that can be focused and can carry an action id
// (design doc section 4.2). `action` is the string id the keyboard layer would
// dispatch; mouse behaviour is `onClick`.
package asaot.ui
{
    public class Control extends Element
    {
        public var tabEnabled:Boolean;
        public var tabIndex:int;
        public var onClick:Function;
        public var action:String;

        public function Control(kind:String):void
        {
            super(kind);
            this.tabEnabled = true;
            this.tabIndex = -1;
            this.onClick = null;
            this.action = null;
        }
    }
}