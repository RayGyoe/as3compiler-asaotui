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
    import flash.geom.Rectangle;

    public class TreeWidget implements Widget, WidgetKeys
    {
        private static const TOGGLE_FN:String = "onToggle";
        private static const SELECT_FN:String = "onSelect";
        private static const ROWS_KEY:String = "rows";
        private static const ACT_KEY:String = "actRow";
        private static const HIT_KEY:String = "hit";
        private static const VIRT_KEY:String = "tv";     // 1 while the tree is windowed
        private static const FIRST_KEY:String = "tf";    // index into `rows` of child 0
        private static const OFF_KEY:String = "to";      // row-aligned offset reported
        private static const RH_KEY:String = "th";       // row height
        private static const FIT_KEY:String = "tfit";    // rows that fit
        private static const CLIP_KEY:String = "tclip";  // applied [w,h] pair
        private static const WHEEL_STEP:int = 3;

        public function build(n:UiNode):void
        {
            n.extra[TOGGLE_FN] = null;
            n.extra[SELECT_FN] = null;
            n.extra[ACT_KEY] = -1;
            n.extra[HIT_KEY] = 0;
            n.extra[ROWS_KEY] = null;
            n.extra[VIRT_KEY] = 0;
            n.extra[FIRST_KEY] = 0;
            n.extra[OFF_KEY] = 0;
            n.extra[RH_KEY] = 0;
            n.extra[FIT_KEY] = 0;
            n.extra[CLIP_KEY] = null;
            // Index 0: the panel/row backdrop. The active band is painted into this
            // same shape, i.e. BELOW every row -- the rows are transparent text boxes,
            // so a band drawn there shows through.
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            var self:TreeWidget = this;
            n.listen(n.backing, MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickAt(n, e); });
            n.listen(n.backing, MouseEvent.MOUSE_WHEEL,
                function (e:MouseEvent):void { self.onWheel(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var t:TreeNode = TreeNode(desc);
            n.extra[TOGGLE_FN] = t.onToggle;
            n.extra[SELECT_FN] = t.onSelect;
            n.extra[ROWS_KEY] = t.rows;
            n.extra[VIRT_KEY] = t.virtual ? 1 : 0;
            n.extra[FIRST_KEY] = t.firstRow;
            n.extra[OFF_KEY] = t.offsetY;
            n.extra[RH_KEY] = t.rowHeight;
            n.extra[FIT_KEY] = t.visibleRows;
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
            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);
            PaintKit.paintBox(n, n.resolved, w, h);
            if (Number(n.extra[VIRT_KEY]) != 0) this.applyClip(n, w, h);
            var rows:Array = n.extra[ROWS_KEY] as Array;
            if (rows == null || n.shapeA == null) return;
            var first:int = int(Number(n.extra[FIRST_KEY]));

            // The active band, under the rows. Same index the keyboard walks -- which is
            // ABSOLUTE under `virtual`, so the mounted child is act - first and an
            // off-window active row paints nothing (there is no rect to paint).
            var act:int = int(Number(n.extra[ACT_KEY]));
            var actChild:int = act - first;
            if (act >= 0 && actChild >= 0 && actChild < n.children.length)
            {
                var ar:UiNode = n.children[actChild];
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
            for (var i:int = 0; i < n.children.length; i++)
            {
                var ri:int = first + i;
                if (ri < 0 || ri >= rows.length) break;
                var r:Object = rows[ri];
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
                // A highlight on an unmounted row is a selection nobody can see, so the
                // window follows the active row -- exactly what a scrolled listbox does.
                if (Number(n.extra[VIRT_KEY]) != 0) this.reveal(n, act);
                return true;
            }
            if (keyCode == 36 || keyCode == 35)   // Home / End
            {
                var edge:int = keyCode == 36 ? 0 : rows.length - 1;
                n.extra[ACT_KEY] = edge;
                n.app.markPaint(n);
                if (Number(n.extra[VIRT_KEY]) != 0) this.reveal(n, edge);
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
            if (rows == null || row < 0) return;
            // ABSOLUTE row: `row` is the MOUNTED child, and under `virtual` the mounted
            // slice starts at `firstRow`. Without this the tree selects the wrong key --
            // and the twisty toggles the wrong branch -- after any scroll.
            var abs:int = row + int(Number(n.extra[FIRST_KEY]));
            if (abs >= rows.length) return;

            n.extra[HIT_KEY] = 1;
            // Same as ListWidget: a click on a row is a focus claim, or the arrows
            // are dead after the first mouse selection.
            n.app.focusNode(n);
            var r:Object = rows[abs];
            var lx:Number = OverlayList.localXIn(n, e);
            var left:Number = OverlayChrome.TREE_PAD + int(r.depth) * OverlayChrome.TREE_INDENT;
            if (Boolean(r.branch) && lx >= 0 && lx < left)
            {
                this.toggle(n, String(r.key));
                return;
            }
            n.extra[ACT_KEY] = abs;
            n.app.markPaint(n);
            var f:Function = n.extra[SELECT_FN];
            if (f != null) f(String(r.key));
        }

        // ---- virtual scrolling -----------------------------------------------
        private function applyClip(n:UiNode, w:Number, h:Number):void
        {
            var applied:Array = n.extra[CLIP_KEY] as Array;
            if (applied == null) { applied = [0, 0]; n.extra[CLIP_KEY] = applied; }
            if (applied[0] == w && applied[1] == h) return;
            // PURE clip: the mounted rows are already inside the viewport.
            n.backing.scrollRect = new Rectangle(0, 0, w, h);
            applied[0] = w;
            applied[1] = h;
        }

        private function onWheel(n:UiNode, e:MouseEvent):void
        {
            if (Number(n.extra[VIRT_KEY]) == 0) return;
            var rh:Number = Number(n.extra[RH_KEY]);
            if (!(rh > 0)) return;
            var d:Number = e.delta;
            if (isNaN(d)) d = 0;
            if (d == 0) return;
            // Positive delta scrolls toward the START -- the same convention as the
            // list, the table and ScrollViewWidget.
            var step:int = d > 0 ? -WHEEL_STEP : WHEEL_STEP;
            this.request(n, int(Number(n.extra[OFF_KEY]) / rh) + step);
            e.stopPropagation();
        }

        // Least-move reveal: only when the row is outside, and only as far as the near edge.
        private function reveal(n:UiNode, row:int):void
        {
            var first:int = int(Number(n.extra[FIRST_KEY]));
            var fit:int = int(Number(n.extra[FIT_KEY]));
            if (fit < 1) fit = 1;
            if (row >= first && row < first + fit) return;
            this.request(n, row < first ? row : row - fit + 1);
        }

        private function request(n:UiNode, firstWanted:int):void
        {
            var rh:Number = Number(n.extra[RH_KEY]);
            if (!(rh > 0)) return;
            var rows:Array = n.extra[ROWS_KEY] as Array;
            var count:int = rows == null ? 0 : rows.length;
            var fit:int = int(Number(n.extra[FIT_KEY]));
            if (fit < 1) fit = 1;
            var maxFirst:int = count - fit;
            if (maxFirst < 0) maxFirst = 0;
            var f:int = firstWanted;
            if (f > maxFirst) f = maxFirst;
            if (f < 0) f = 0;
            var y:Number = f * rh;
            if (y == Number(n.extra[OFF_KEY])) return;
            n.extra[OFF_KEY] = y;
            var t:TreeNode = n.desc == null ? null : TreeNode(n.desc);
            if (t != null)
            {
                t.offsetY = y;
                if (t.onScroll != null) t.onScroll(y);
            }
            n.app.markPaint(n);
        }
    }
}