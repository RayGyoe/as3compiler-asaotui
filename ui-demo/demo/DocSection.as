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
        // PARAGRAPHS, not display lines. The view wraps them at the reading pane's
        // live width (DocsWrap); a hand-broken line would be a guess about a width
        // the window has not decided yet.
        public var prose:Array;
        public var code:Array;      // source lines, monospace
        public var demoH:Number;    // height of the live-demo surface
        public var build:Function;  // ():Node
        // EDGE TO EDGE. The demo surface normally carries the docs' own frame
        // (12pt padding, a tint and a border) so a widget that paints nothing
        // still shows where the demo IS. A page that shows an APP -- the live
        // board -- wants that frame out of the way, so `wide` swaps in
        // DocsStyle.DEMO_BLEED: same height, same slot, no padding and no tint.
        // It is a layout-neutral switch on purpose: demoH is still the block's
        // height, so DocSection.height() and the tour's arithmetic are unchanged.
        public var wide:Boolean;

        public function DocSection(h:String, p:Array, c:Array, dh:Number, b:Function,
                                   w:Boolean = false):void
        {
            this.heading = h;
            this.prose = p == null ? [] : p;
            this.code = c == null ? [] : c;
            this.demoH = dh;
            this.build = b;
            this.wide = w;
        }

        // The block's height, from the SAME numbers DocsStyle gives the engine.
        // DocsView gives every block exactly this, and the tour then proves the
        // arithmetic by requiring that no child's rect escapes its block.
        public function height(wrapW:Number = NaN):Number
        {
            var h:Number = DocsStyle.SEC_HEAD_H + DocsStyle.SEC_INNER_GAP;
            var lines:Array = this.proseLines(wrapW);
            if (lines.length > 0)
            {
                h = h + lines.length * DocsStyle.SEC_PROSE_H + DocsStyle.SEC_INNER_GAP;
            }
            h = h + this.demoH + DocsStyle.SEC_INNER_GAP;
            return h + codeHeight();
        }

        // THE DISPLAY LINES, wrapped at `wrapW` and remembered. A page is described
        // whenever the model changes, and the wrapper is a shaping pass per word, so
        // the answer is cached against the width it was computed for -- the same
        // width the solve has already fixed for this frame, unchanged between two
        // describes unless the window moved.
        private var _wrapW:Number = NaN;
        private var _lines:Array;

        public function proseLines(wrapW:Number):Array
        {
            if (this._lines != null && (this._wrapW == wrapW
                || (isNaN(this._wrapW) && isNaN(wrapW))))
            {
                return this._lines;
            }
            this._wrapW = wrapW;
            this._lines = DocsWrap.lines(this.prose, wrapW, DocsStyle.PROSE);
            return this._lines;
        }

        public function codeHeight():Number
        {
            return DocsStyle.CODE_PAD_H * 2 + this.code.length * DocsStyle.CODE_LINE_H;
        }
    }
}
