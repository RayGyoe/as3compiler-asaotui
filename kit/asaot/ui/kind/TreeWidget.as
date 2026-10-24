// asaot.ui.kind.TreeWidget -- click routing, twisties and keyboard for TreeNode.
//
// THE ROWS ARE THE TREE'S DIRECT CHILDREN (the factory flattens, see TreeNode), so a
// click is routed by GEOMETRY, exactly like the select dropdown's: `OverlayList.rowAt`
// answers "which row", and `rows[i]` answers "which item key". `e.target` cannot be
// used -- a click on a row's text bubbles up through the row, so the target is the
// TextField, not the row.
//
// TWISTY vs LABEL: within a row, an x inside the left padding (TREE_HIT, measured from
// the row's own left edge) is a TWISTY click -- it calls `onToggle(key)`. Anything
// further right selects. A click on the padding of a LEAF selects too: there is no
// twisty to hit, and swallowing the click would feel broken.
//
// NO STATE OF ITS OWN. `open`/`expanded`/`selectedKey` live in the description; the
// widget only reports. That is what makes `tree` survive a re-render, and it is why
// the twisty is redrawn from `rows[i].open` on every paint instead of being toggled
// in place.
package asaot.ui.kind
{
    import asaot.ui.LayoutConstants;
    import asaot.ui.OverlayChrome;
    import asaot.ui.OverlayList;
    import asaot.ui.PaintKit;
    import asaot.ui.Node;
    import asaot.ui.TreeNode;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetKeys;
    import flash.display.Shape;
    import flash.events.MouseEvent;

    public class TreeWidget implements Widget, WidgetKeys
    {
        private static const TOGGLE_FN:String = "onToggle";
        private static const SELECT_FN:String = "onSelect";
        private static const ROWS_KEY:String = "rows";
        private static const ACT_KEY:String = "actRow";
        private static const HIT_KEY:String = "hit";

        public function build(n:UiNode):void
        {
            n.extra[TOGGLE_FN] = null;
            n.extra[SELECT_FN] = null;
            n.extra[ACT_KEY] = -1;
            n.extra[HIT_KEY] = 0;
            n.extra[ROWS_KEY] = null;
            // Index 0: the panel/row backdrop. The active band is painted into this
            // same shape, i.e. BELOW every row -- the rows are transparent text boxes,
            // so a band drawn there shows through.
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            var self:TreeWidget = this;
            n.listen(n.backing, MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickAt(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var t:TreeNode = TreeNode(desc);
            n.extra[TOGGLE_FN] = t.onToggle;
            n.extra[SELECT_FN] = t.onSelect;
            n.extra[ROWS_KEY] = t.rows;
            n.onChange = t.onSelect;
            // The active row is an index into the CURRENT flat row list. When the list
            // shrinks (a branch collapsed) the index would point at a different item,
            // so it is dropped rather than clamped: a stale highlight is worse than
            // none, and the next arrow key re-establishes it from the top.
            var rows:Array = t.rows == null ? [] : t.rows;
            if (int(Number(n.extra[ACT_KEY])) >= rows.length) n.extra[ACT_KEY] = -1;
            return false;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void { }

        public function arrange(n:UiNode):void { }

        public function paint(n:UiNode):void
        {
            PaintKit.paintBox(n, n.resolved, PaintKit.w1(n), PaintKit.h1(n));
            var rows:Array = n.extra[ROWS_KEY] as Array;
            if (rows == null || n.shapeA == null) return;

            // The active band, under the rows. Same index the keyboard walks.
            var act:int = int(Number(n.extra[ACT_KEY]));
            if (act >= 0 && act < n.children.length)
            {
                var ar:UiNode = n.children[act];
                var ag:Object = n.shapeA.graphics;
                ag.beginFill(OverlayChrome.ITEM_HOVER, 1.0);
                ag.drawRect(ar.absX - n.absX, ar.absY - n.absY, ar.absW, ar.absH);
                ag.endFill();
            }

            // One twisty per BRANCH row. It sits in the row's left padding: the factory
            // set padding-left to TREE_PAD + depth*TREE_INDENT, so the marker's centre is
            // that padding minus 13 (7pt of air on each side of the 6pt triangle).
            var g:Object = n.shapeA.graphics;
            g.beginFill(OverlayChrome.TREE_TWISTY, 1.0);
            for (var i:int = 0; i < rows.length && i < n.children.length; i++)
            {
                var r:Object = rows[i];
                if (!Boolean(r.branch)) continue;
                var c:UiNode = n.children[i];
                var rx:Number = c.absX - n.absX;
                var ry:Number = c.absY - n.absY;
                var left:Number = OverlayChrome.TREE_PAD + int(r.depth) * OverlayChrome.TREE_INDENT;
                var cx:Number = rx + left - 13;
                var cy:Number = ry + Math.floor(c.absH / 2);
                if (Boolean(r.open))
                {
                    // open: a downward triangle
                    g.moveTo(cx - 5, cy - 3);
                    g.lineTo(cx + 5, cy - 3);
                    g.lineTo(cx, cy + 4);
                    g.lineTo(cx - 5, cy - 3);
                }
                else
                {
                    // closed: a rightward triangle
                    g.moveTo(cx - 3, cy - 5);
                    g.lineTo(cx + 4, cy);
                    g.lineTo(cx - 3, cy + 5);
                    g.lineTo(cx - 3, cy - 5);
                }
            }
            g.endFill();
        }

        public function click(n:UiNode):Boolean
        {
            return Number(n.extra[HIT_KEY]) != 0;
        }

        public function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean
        {
            var rows:Array = n.extra[ROWS_KEY] as Array;
            if (rows == null || rows.length == 0) return false;
            var act:int = int(Number(n.extra[ACT_KEY]));

            if (keyCode == 38 || keyCode == 40)
            {
                if (act < 0) act = 0;
                else act = keyCode == 40 ? (act + 1) % rows.length
                                         : (act - 1 + rows.length) % rows.length;
                n.extra[ACT_KEY] = act;
                n.app.markPaint(n);
                return true;
            }
            if (keyCode == 36 || keyCode == 35)   // Home / End
            {
                n.extra[ACT_KEY] = keyCode == 36 ? 0 : rows.length - 1;
                n.app.markPaint(n);
                return true;
            }
            if (keyCode == 39)                    // Right: open the branch under the active row
            {
                if (act < 0) return true;
                var rr:Object = rows[act];
                if (Boolean(rr.branch) && !Boolean(rr.open)) this.toggle(n, String(rr.key));
                return true;
            }
            if (keyCode == 37)                    // Left: close it
            {
                if (act < 0) return true;
                var rl:Object = rows[act];
                if (Boolean(rl.branch) && Boolean(rl.open)) this.toggle(n, String(rl.key));
                return true;
            }
            if (keyCode == 13 || keyCode == 32)   // Enter / Space activate
            {
                if (act < 0) return true;
                var ra:Object = rows[act];
                var f:Function = n.extra[SELECT_FN];
                if (f != null) f(String(ra.key));
                return true;
            }
            return false;
        }

        private function toggle(n:UiNode, key:String):void
        {
            var f:Function = n.extra[TOGGLE_FN];
            if (f != null) f(key);
        }

        private function onClickAt(n:UiNode, e:MouseEvent):void
        {
            n.extra[HIT_KEY] = 0;
            var rows:Array = n.extra[ROWS_KEY] as Array;
            var ly:Number = OverlayList.localYIn(n, e);
            var row:int = OverlayList.rowAt(n, ly);
            if (rows == null || row < 0 || row >= rows.length) return;

            n.extra[HIT_KEY] = 1;
            var r:Object = rows[row];
            var lx:Number = OverlayList.localXIn(n, e);
            var left:Number = OverlayChrome.TREE_PAD + int(r.depth) * OverlayChrome.TREE_INDENT;
            if (Boolean(r.branch) && lx >= 0 && lx < left)
            {
                this.toggle(n, String(r.key));
                return;
            }
            n.extra[ACT_KEY] = row;
            n.app.markPaint(n);
            var f:Function = n.extra[SELECT_FN];
            if (f != null) f(String(r.key));
        }
    }
}