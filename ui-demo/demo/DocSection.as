// demo/DocSection.as -- one documented section: a heading, prose, a LIVE demo,
// and the source that produced it.
//
// This is the unit of the docs app, and it is data-only on purpose: `build` is a
// factory closure, not a Node, because the demo subtree has to be rebuilt from
// the model on every render (a widget's `open`/`value` is author-owned here --
// see the pages' callbacks). Everything else is text.
package demo
{
    import asaot.ui.Node;

    public class DocSection
    {
        public var heading:String;
        public var prose:Array;     // body lines (each one rendered as its own TextField)
        public var code:Array;      // source lines, monospace
        public var demoH:Number;    // height of the live-demo surface
        public var build:Function;  // ():Node

        public function DocSection(h:String, p:Array, c:Array, dh:Number, b:Function):void
        {
            this.heading = h;
            this.prose = p == null ? [] : p;
            this.code = c == null ? [] : c;
            this.demoH = dh;
            this.build = b;
        }

        // The block's height, from the SAME numbers DocsStyle gives the engine.
        // DocsView gives every block exactly this, and the tour then proves the
        // arithmetic by requiring that no child's rect escapes its block.
        public function height():Number
        {
            var h:Number = DocsStyle.SEC_HEAD_H + DocsStyle.SEC_INNER_GAP;
            if (this.prose.length > 0)
            {
                h = h + this.prose.length * DocsStyle.SEC_PROSE_H + DocsStyle.SEC_INNER_GAP;
            }
            h = h + this.demoH + DocsStyle.SEC_INNER_GAP;
            return h + codeHeight();
        }

        public function codeHeight():Number
        {
            return DocsStyle.CODE_PAD_H * 2 + this.code.length * DocsStyle.CODE_LINE_H;
        }
    }
}
