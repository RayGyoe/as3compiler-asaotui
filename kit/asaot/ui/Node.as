// asaot.ui.Node -- a DESCRIPTION node (design doc section 1.1). Pure data with a
// lifetime of one describe pass: `render()` builds it, the reconciler reads it,
// then it is dropped. It is NOT the retained tree (that is UiNode) and it
// deliberately has NO lifecycle hooks -- hooks belong on the retained side.
//
// `kind` is the discriminator that pairs a description with a control factory;
// `key` is the explicit identity (String or int; null means "use my sibling
// index"); `style` is a PARTIAL refinement handed to the resolver.
package asaot.ui
{
    import asaot.ui.style.StyleRefinement;

    public class Node
    {
        public var kind:String;
        public var key:Object;
        public var style:StyleRefinement;
        public var keyContext:String;
        public var children:Vector.<Node>;

        public function Node(kind:String):void
        {
            this.kind = kind;
            this.key = null;
            this.style = null;
            this.keyContext = null;
            this.children = null;
        }

        public function addChild(c:Node):void
        {
            if (this.children == null) this.children = new Vector.<Node>();
            this.children.push(c);
        }
    }
}