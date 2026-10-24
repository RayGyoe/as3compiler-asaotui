// demo/DocPage.as -- one component's place in the docs index: what the sidebar
// shows and what the content pane's header reads. The SECTIONS are not here: they
// are built on demand (DocsCatalog.sections), so describing the sidebar never
// constructs 40 widgets.
package demo
{
    public class DocPage
    {
        public var id:String;       // the model's `doc` value, and the node key prefix
        public var title:String;    // the factory spelling: `button`, `textField`, ...
        public var group:int;       // index into DocsCatalog.GROUPS
        public var blurb:String;    // one line under the title

        public function DocPage(i:String, t:String, g:int, b:String):void
        {
            this.id = i;
            this.title = t;
            this.group = g;
            this.blurb = b;
        }
    }
}
