// demo/DocsModel.as -- the docs app's model.
//
// TWO KINDS OF STATE, deliberately in one place:
//   * `doc`      -- which component page is selected (a sidebar click writes it);
//   * `demo`     -- the LIVE state of the example widgets on the pages.
//
// The second one is the point: every widget in this toolkit is "report it, the
// author re-renders". A checkbox does not keep its own `checked`, a select does
// not keep its own `open` -- they report, this model stores, and the next render
// re-describes the tree from here. A demo that kept its state inside the widget
// would look right and be wrong: the docs are showing the contract.
package demo
{
    import asaot.ui.Dirty;
    import asaot.ui.Observable;

    public class DocsModel extends Observable
    {
        public var doc:String = "start";
        private var demo:Object;

        public function DocsModel():void
        {
            super();
            this.demo = {};
        }

        // A demo's value, with the page's own default when it was never touched.
        public function val(key:String, dflt:*):*
        {
            var v:Object = this.demo[key];
            return v == null ? dflt : v;
        }

        public function num(key:String, dflt:Number):Number
        {
            var v:Object = this.demo[key];
            return v == null || isNaN(Number(v)) ? dflt : Number(v);
        }

        public function bool(key:String, dflt:Boolean):Boolean
        {
            var v:Object = this.demo[key];
            return v == null ? dflt : Boolean(v);
        }

        // A demo interaction: value changed, repaint (no relayout needed).
        public function put(key:String, v:*):void
        {
            this.demo[key] = v;
            this.notify(Dirty.VALUE);
        }

        // A page switch: the body slot, the header and the sidebar highlight all
        // change, so this is a full invalidation (and it is what makes the local
        // per-demo keys safe -- they are all "untouched" again on a fresh page).
        public function pick(id:String):void
        {
            if (this.doc == id) return;
            this.doc = id;
            this.notify(Dirty.ALL);
        }
    }
}
