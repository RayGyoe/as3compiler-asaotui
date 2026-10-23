// demo/GalleryModel.as -- the multi-page demo's model.
//
// One Observable that every page reads from. The page INDEX lives here rather
// than in the view, because the tabs widget writes its selectedIndex back through
// a Binding: a page switch is a model mutation, so it flows through exactly the
// same notify -> invalidate -> re-render path as every other change (design doc
// section 5.1). Nothing in the view keeps "which page am I on" state.
package demo
{
    import asaot.ui.Observable;

    public class GalleryModel extends Observable
    {
        // 0 Home, 1 Widgets, 2 Data, 3 Motion. Number (not int) because it is
        // bound to a widget's selectedIndex, which is a Number slot.
        public var page:Number = 1;

        // Home page -- the sign-in card carried over from the first demo.
        public var account:String = "";
        public var password:String = "";
        public var remember:Boolean = true;
        public var status:String = "ready";

        // Data page -- the list's selection.
        public var listIndex:Number = 0;
        public var items:Array;

        // Widgets page -- live control values.
        public var plan:Number = 1;        // radio group: 0 Basic, 1 Pro, 2 Team
        public var wifi:Boolean = true;
        public var volume:Number = 40;
        public var notify:Boolean = false;

        // Motion page -- flipped by the view's per-frame tick(), NOT by a timer.
        public var phase:int = 0;

        // Catalog page (page 4) -- the media/feedback/data widgets' own live state.
        public var compRow:Number = 1;    // table selection (body row)
        public var compOpen:Number = 0;   // accordion open section
        public var compPage:Number = 3;   // pagination page (1-based)

        public function GalleryModel():void
        {
            super();
            this.items = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"];
        }
    }
}
