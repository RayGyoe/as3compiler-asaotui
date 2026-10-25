// asaot.ui.kind.TableWidget -- the container for TableNode.
//
// The rows and cells are NOT this widget's display objects: they are child
// UiNodes the factory made and the reconciler mounted, and the layout ENGINE
// places them. So `build` only owns the background shape, and `measure`/`arrange`
// do nothing (a container's intrinsic size is the engine's job; see BoxWidget).
//
// EVERYTHING PAINTED HERE IS A FILL, WHICH IS WHY THE PIXELS ARE EXACT. A filled rect
// rasterises exactly at the declared pixel box, so a 1px grid line is really 1px and the
// probe can assert its colour. (The note this file carried until 2026-10-25 -- that
// `lineStyle` stroke width is "not honoured" -- was wrong: re-measured, a stroke is
// exactly as wide as it is declared, see probes/widgets/icon. The hairlines, the zebra
// stripes and the selection highlight stay fills because a fill is integer-exact, not
// because a stroke is broken.)
//
// The geometry comes from the CHILDREN's laid-out rects (absX/absY/absW/absH,
// resolved by the engine in the arrange pass), never from arithmetic over the
// column list -- so a grid line lands exactly where the engine put the column
// boundary, and a widget bug cannot silently drift from the layout.
//
// THREE INTERACTIONS, all "report, never mutate the model":
//
//   * SELECT -- a click's y selects a BODY row (the header is skipped) through a
//     listener added at structure time. `selectedIndex` is a DECORATION: a
//     selection change raises only Dirty.M_PAINT and never reflows. The index is
//     ABSOLUTE (the window's first row is added back), because a virtualised table
//     that reported "the second mounted row" would select the wrong record as soon
//     as the author scrolled.
//   * SORT -- a click on a header cell asks `onSort(columnIndex, descending)` and
//     nothing else. The widget does NOT reorder anything: order comes from the
//     description (`sortColumn`), which is the author's model. The cycle is the
//     browser's: another column -> ascending, same column -> descending, same
//     column again -> "unsorted", reported as columnIndex -1 (the same vocabulary
//     `sortColumn` uses).
//   * RESIZE -- a press within RESIZE_GRAB px of a header column boundary drags a
//     1px PREVIEW line and, on release, asks `onColumnResize(index, width)`. It
//     never writes into `columns`: that array is the author's model (usually an
//     inline literal rebuilt per render), so a width written there would vanish on
//     the next pass. The preview is a paint, not a reflow: the engine owns the cell
//     geometry, so a live resize would need a full solve per pointer move.
//
// WHY A STAGE LISTENER FOR THE DRAG: the runtime dispatches motion to whatever is
// under the POINTER, so a resize that leaves the header would stop receiving events.
// Listening on the STAGE for the duration is the pointer capture this runtime does
// not have (same trick as SliderWidget / ScrollViewWidget). The closures live in
// `n.extra` so they can be removed BY REFERENCE, and `teardown` removes them: a
// stage listener pointing at a destroyed node's scratch bag is exactly the bug the
// gallery's popups had: a listener that outlived its node.
//
// KEYBOARD (2026-10-26): the table is ONE tab stop and the arrows walk the BODY rows
// -- Up/Down one row, PageUp/PageDown one window, Home/End the ends, all CLAMPED
// (a grid stops at its ends). Under `virtual` the selected row is also brought INTO
// THE WINDOW, through the same `request()` the wheel uses, because the rows are not
// mounted: a highlight on row 40 of 200 that never scrolls there is a selection
// nobody can see. Both the click and the keys end in `select()`.
package asaot.ui.kind
{
    import asaot.ui.TableNode;
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetKeys;
    import asaot.ui.WidgetTeardown;

    import flash.display.DisplayObject;
    import flash.display.Shape;
    import flash.display.Stage;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import flash.geom.Rectangle;

    public class TableWidget implements Widget, WidgetKeys, WidgetTeardown
    {
        public static const DEFAULT_H:Number = 200;   // same viewport default as vlist
        public static const MIN_COL_W:Number = 24;    // narrowest a drag may leave a column
        public static const RESIZE_GRAB:Number = 4;   // half-width of the boundary hit band
        private static const WHEEL_STEP:int = 3;      // rows per wheel notch

        private static const SEL_KEY:String = "sel";    // selected BODY row (-1 = none)
        private static const HIT_KEY:String = "hit";    // 1 when the last click hit a body row
        private static const HDR_KEY:String = "hdr";    // 1 when a header row exists
        private static const STR_KEY:String = "str";    // stripes on
        private static const GRID_KEY:String = "grid";  // grid lines on
        private static const FIRST_KEY:String = "first";// absolute index of the first mounted row
        private static const RH_KEY:String = "rh";      // rowHeight (window arithmetic)
        private static const OFF_KEY:String = "off";    // the offset this description was built for
        private static const VIRT_KEY:String = "virt";  // windowing on (=> clip)
        private static const SCOL_KEY:String = "scol";  // sortColumn (-1 = unsorted)
        private static const SDESC_KEY:String = "sdesc";// sortDescending
        private static const RESZ_KEY:String = "resz";  // resizable (boundary drag armed)
        private static const PREV_KEY:String = "prev";  // preview line x, -1 = none
        private static const RCOL_KEY:String = "rcol";  // column index being resized
        private static const SWAL_KEY:String = "swal";  // swallow the click after a resize
        // ^ the marker is set when a resize starts and cleared by the first click (or by
        //   the next press). Without it, releasing a resize ON A COLUMN BOUNDARY would
        //   also sort that column: the window glue sends a real CLICK after every
        //   release, and for a resize that click lands exactly on the divider.
        private static const MOVE_FN:String = "reszmv"; // stage MOUSE_MOVE closure
        private static const UP_FN:String = "reszup";   // stage MOUSE_UP closure
        private static const CLIP_KEY:String = "clip";  // [w, h] last applied scrollRect

        public function build(n:UiNode):void
        {
            // shapeA sits at backing child index 0, i.e. BEHIND every row/cell
            // backing, so the stripes/grid/selection show through a transparent row.
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.extra[SEL_KEY] = -1;
            n.extra[HIT_KEY] = 0;
            n.extra[HDR_KEY] = 0;
            n.extra[STR_KEY] = 0;
            n.extra[GRID_KEY] = 1;
            n.extra[FIRST_KEY] = 0;
            n.extra[RH_KEY] = 0;
            n.extra[OFF_KEY] = 0;
            n.extra[VIRT_KEY] = 0;
            n.extra[SCOL_KEY] = -1;
            n.extra[SDESC_KEY] = 0;
            n.extra[RESZ_KEY] = 0;
            n.extra[PREV_KEY] = -1;
            n.extra[RCOL_KEY] = -1;
            n.extra[SWAL_KEY] = 0;

            var self:TableWidget = this;
            n.listen(n.backing, MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickY(n, e); });
            n.listen(n.backing, MouseEvent.MOUSE_DOWN,
                function (e:MouseEvent):void { self.onPress(n, e); });
            n.listen(n.backing, MouseEvent.MOUSE_WHEEL,
                function (e:MouseEvent):void { self.onWheel(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var t:TableNode = TableNode(desc);
            n.binding = t.binding;
            // UiNode has no dedicated onSelect slot; reuse onChange (same
            // Function(Number) contract as the other selectable controls).
            n.onChange = t.onSelect;
            n.extra[HDR_KEY] = t.header ? 1 : 0;
            n.extra[STR_KEY] = t.stripes ? 1 : 0;
            n.extra[GRID_KEY] = t.grid ? 1 : 0;
            n.extra[FIRST_KEY] = t.firstRow;
            n.extra[RH_KEY] = t.rowHeight;
            n.extra[OFF_KEY] = t.offsetY;
            n.extra[VIRT_KEY] = t.virtual ? 1 : 0;
            n.extra[SCOL_KEY] = t.sortColumn;
            n.extra[SDESC_KEY] = t.sortDescending ? 1 : 0;
            n.extra[RESZ_KEY] = t.resizable ? 1 : 0;

            var sv:Number = t.selectedIndex;
            if (t.binding != null)
            {
                // `*`, NOT `Object`: an `Object` slot would box the value once per read.
                // Number() never depended on the G9 fix (阶段二四八) and the G14 Array-identity
                // hazard (阶段二百五十三) is closed too, so `*` is now purely the cheaper default.
                var bv:* = t.binding.get();
                sv = bv == null ? -1 : Number(bv);
            }
            var prev:Object = n.extra[SEL_KEY];
            if (prev == null || Number(prev) != sv)
            {
                n.extra[SEL_KEY] = sv;
                n.dirty |= Dirty.M_PAINT;   // decoration only: never a reflow
            }
            // Structure (columns / rows / rowHeight / the window) is carried by the
            // child nodes the factory built; the reconciler diffs them, so this node
            // never reports a re-measure itself.
            return false;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            // The engine sizes the container from its rows (see BoxWidget).
        }

        public function arrange(n:UiNode):void
        {
            // Rows are placed by the engine; nothing internal to position.
        }

        public function paint(n:UiNode):void
        {
            // Clears shapeA, so every fill below is redrawn from scratch.
            PaintKit.paintBox(n, n.resolved, PaintKit.w1(n), PaintKit.h1(n));
            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);

            // A windowed table clips: the factory mounts one row PAST the viewport
            // (the partial last row), and with a header the clip must not eat it. A
            // PURE clip (0,0,w,h) -- the rows are already positioned inside the
            // viewport, unlike ScrollViewWidget which slides its content.
            if (Number(n.extra[VIRT_KEY]) != 0)
            {
                var applied:Array = n.extra[CLIP_KEY] as Array;
                if (applied == null) { applied = [0, 0]; n.extra[CLIP_KEY] = applied; }
                if (applied[0] != w || applied[1] != h)
                {
                    n.backing.scrollRect = new Rectangle(0, 0, w, h);
                    applied[0] = w;
                    applied[1] = h;
                }
            }

            if (n.shapeA == null) return;
            var g:Object = n.shapeA.graphics;

            // A TRANSPARENT HIT RECT, drawn first so the table is pickable EVERYWHERE
            // and not just on its hairlines and glyphs. The runtime picks a mouse target
            // by PAINTED REGION (as_pick_hit -> as_obj_region_hit_local, emit.ts:17382),
            // and a table paints only 1px grid lines and text -- measured here: a click
            // in the middle of an empty cell targeted the ROOT behind the table, so a row
            // could only be selected on a one-pixel line. alpha 0 is still a region (the
            // pick ignores object and fill alpha, emit.ts:17401), and the comment in the
            // runtime names this very idiom: "every Flash 'catch the clicks over this
            // panel' idiom draws a transparent fill first". It changes no pixel.
            g.beginFill(0x000000, 0.0);
            g.drawRect(0, 0, w, h);
            g.endFill();
            var hdr:Boolean = Number(n.extra[HDR_KEY]) != 0;
            var stripes:Boolean = Number(n.extra[STR_KEY]) != 0;
            var sel:int = int(Number(n.extra[SEL_KEY]));
            var first:int = int(Number(n.extra[FIRST_KEY]));

            // ---- stripes + selection (behind the cells) ----------------------
            var body:int = 0;
            for (var i:int = 0; i < n.children.length; i++)
            {
                var c:UiNode = n.children[i];
                var isHdr:Boolean = hdr && i == 0;
                if (!isHdr && stripes && ((first + body) % 2) == 1)
                {
                    g.beginFill(TableNode.STRIPE_BG, 1.0);
                    g.drawRect(c.absX - n.absX, c.absY - n.absY, c.absW, c.absH);
                    g.endFill();
                }
                if (!isHdr && first + body == sel)
                {
                    g.beginFill(TableNode.SEL_BG, 1.0);
                    g.drawRect(c.absX - n.absX, c.absY - n.absY, c.absW, c.absH);
                    g.endFill();
                }
                if (!isHdr) body = body + 1;
            }

            // ---- the resize preview (a 1px fill, see the header) -------------
            var prevX:Number = Number(n.extra[PREV_KEY]);
            if (prevX >= 0)
            {
                var last:UiNode = n.children[n.children.length - 1];
                var top:Number = n.children[0].absY - n.absY;
                var bottom:Number = last.absY - n.absY + last.absH;
                g.beginFill(0x2563EB, 1.0);
                g.drawRect(Math.round(prevX), top, 1, bottom - top);
                g.endFill();
            }

            // ---- grid -------------------------------------------------------
            if (Number(n.extra[GRID_KEY]) == 0) return;
            var count:int = n.children.length;
            if (count == 0) return;
            g.beginFill(TableNode.GRID_LINE, 1.0);
            // Horizontal hairlines on the bottom edge of every row but the last.
            for (var r:int = 0; r < count - 1; r++)
            {
                var rr:UiNode = n.children[r];
                g.drawRect(0, rr.absY - n.absY + rr.absH, w, 1);
            }
            // Vertical hairlines at the column boundaries, taken from the FIRST
            // row's cells (all rows share the same basis, so they agree; the probe
            // asserts exactly that).
            var firstRow:UiNode = n.children[0];
            var vtop:Number = firstRow.absY - n.absY;
            var lastRow:UiNode = n.children[count - 1];
            var vbottom:Number = lastRow.absY - n.absY + lastRow.absH;
            for (var j:int = 1; j < firstRow.children.length; j++)
            {
                var cell:UiNode = firstRow.children[j];
                g.drawRect(cell.absX - n.absX, vtop, 1, vbottom - vtop);
            }
            g.endFill();
        }

        // Consume the click only when it did something of the widget's own: a body
        // row was selected, a header cell asked for a sort, or the click is the tail
        // of a resize gesture. A click in the container's own padding still falls
        // through to the author's onClick.
        public function click(n:UiNode):Boolean
        {
            if (Number(n.extra[SWAL_KEY]) != 0)
            {
                n.extra[SWAL_KEY] = 0;
                return true;
            }
            var hit:* = n.extra[HIT_KEY];
            return hit != null && Boolean(hit);
        }

        // ---- coordinates ---------------------------------------------------
        // The event's point in THIS container's own space. Neither pair alone is
        // enough, and both failures are real:
        //   * `localX`/`localY` are relative to the event TARGET (AS3 semantics), and a
        //     real click's target is often a cell's text node, not the container;
        //   * `stageX`/`stageY` are 0.0 for an event built by hand --
        //     `new MouseEvent(CLICK, true, false, lx, ly)` leaves them at zero in AIR
        //     and in this runtime (emit.ts:12842) -- which is exactly how probes and
        //     app tests dispatch a click.
        // So: take the target-relative pair (always populated), lift it into global
        // space and drop it here. For a hand-built event dispatched on this very
        // backing that is the identity; for a real click it undoes the target's offset.
        // ONE rule covers both, which is why this is not `e.stageX - n.absX`.
        private function localOf(n:UiNode, e:MouseEvent):Point
        {
            var p:Point = new Point(e.localX, e.localY);
            var d:DisplayObject = e.target as DisplayObject;
            if (d == null) return p;
            if (d == n.backing) return p;        // already container-local
            return n.backing.globalToLocal(d.localToGlobal(p));
        }

        // WidgetTeardown: a table destroyed mid-resize must not leave its stage
        // listeners pointing at a nulled scratch bag.
        public function teardown(n:UiNode):void
        {
            this.endResize(n, false);
        }

        // ---- click: header sorts, body selects ------------------------------
        private function onClickY(n:UiNode, e:MouseEvent):void
        {
            n.extra[HIT_KEY] = 0;
            var hdr:Boolean = Number(n.extra[HDR_KEY]) != 0;
            var lp:Point = this.localOf(n, e);
            var localX:Number = lp.x;
            var localY:Number = lp.y;
            var head:UiNode = hdr ? n.children[0] : null;

            // A press that started a resize already decided what this click means.
            if (Number(n.extra[SWAL_KEY]) != 0) return;

            if (head != null && localY >= head.absY - n.absY && localY < head.absY - n.absY + head.absH)
            {
                var col:int = this.columnAt(head, n, localX);
                if (col < 0) return;
                var desc:Boolean = Boolean(Number(n.extra[SDESC_KEY]) != 0);
                var cur:int = int(Number(n.extra[SCOL_KEY]));
                // The browser's cycle. -1 is "unsorted", i.e. the same vocabulary
                // `sortColumn` uses -- not a null key, which the author would have to
                // translate back into an index themselves.
                var nextCol:int = col;
                var nextDesc:Boolean = false;
                if (cur == col) nextDesc = !desc;
                if (cur == col && desc) { nextCol = -1; nextDesc = false; }

                var t:TableNode = TableNode(n.desc);
                // Called through the FIELD, not through a local copy: the static gate
                // (tools/callback-arity.cjs) grades `.onSort(` call sites, and a local
                // `var cb:Function` would make this the one call the gate cannot see.
                if (t.onSort == null) return;         // not sortable: the header is inert
                n.extra[HIT_KEY] = 1;
                n.app.markPaint(n);
                t.onSort(nextCol, nextDesc);
                n.app.invalidate(Dirty.VALUE);
                return;
            }

            var target:int = -1;
            var body:int = 0;
            for (var i:int = 0; i < n.children.length; i++)
            {
                if (hdr && i == 0) continue;   // the header selects nothing
                var c:UiNode = n.children[i];
                var top:Number = c.backing.y;
                var bot:Number = top + c.absH;
                if (localY >= top && localY < bot) { target = body; break; }
                body = body + 1;
            }
            if (target < 0) return;

            // ABSOLUTE row index: under `virtual` the mounted slice starts at
            // `firstRow`, and a window-relative index would select the wrong record.
            target = target + int(Number(n.extra[FIRST_KEY]));

            n.extra[HIT_KEY] = 1;
            this.select(n, target);
        }

        // ---- keyboard -------------------------------------------------------
        // The COUNT comes from the description (`TableNode.rowCount`, published by the
        // factory after sorting), not from the mounted children: under `virtual` the
        // children are one window of a longer list, and the selection is an ABSOLUTE
        // row index for exactly that reason.
        public function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean
        {
            var t:TableNode = n.desc as TableNode;
            if (t == null) return false;
            var count:int = t.rowCount;
            if (count <= 0) return false;
            if (keyCode != 38 && keyCode != 40 && keyCode != 36 && keyCode != 35
                && keyCode != 33 && keyCode != 34) return false;

            var cur:int = this.currentIndex(n);
            var fit:int = t.visibleRows > 0 ? t.visibleRows : 1;
            var next:int;
            if (keyCode == 36) next = 0;
            else if (keyCode == 35) next = count - 1;
            else if (cur < 0 || cur >= count) next = keyCode == 38 ? count - 1 : 0;
            else if (keyCode == 33) next = cur - fit;
            else if (keyCode == 34) next = cur + fit;
            else next = keyCode == 40 ? cur + 1 : cur - 1;
            if (next < 0) next = 0;
            if (next >= count) next = count - 1;
            if (next != cur) this.select(n, next);
            if (t.virtual) this.reveal(n, t, next, fit);
            return true;
        }

        // The row the keys move FROM. The BINDING wins when there is one: it is the
        // freshest intent, and payload has not run yet inside the frame that received
        // the key -- two keys in one frame (a held arrow, a fast repeat) must step
        // twice. Without a binding, fall back to what payload last APPLIED, i.e. what
        // is actually on screen.
        private function currentIndex(n:UiNode):int
        {
            if (n.binding != null)
            {
                var bv:* = n.binding.get();
                if (bv != null) return int(Number(bv));
            }
            return int(Number(n.extra[SEL_KEY]));
        }
        // Bring `sel` into the mounted window, by the least it can move: only when the
        // row is outside it, and then only far enough to touch the near edge.
        private function reveal(n:UiNode, t:TableNode, sel:int, fit:int):void
        {
            var first:int = t.firstRow;
            if (sel >= first && sel < first + fit) return;
            this.request(n, sel < first ? sel : sel - fit + 1);
        }

        // The ONE write path, shared by the click and the keys. Do NOT write
        // n.extra[SEL_KEY]: payload must observe the change and
        // raise Dirty.M_PAINT (same reason as TabsWidget.onClickX).
        private function select(n:UiNode, idx:int):void
        {
            if (n.binding != null) n.binding.set(idx);
            n.app.markPaint(n);
            if (n.onChange != null) n.onChange(idx);
            n.app.invalidate(Dirty.VALUE);
        }

        // Which header cell holds `localX`. The cells are the engine's geometry, so
        // this cannot disagree with the grid lines the paint pass drew.
        private function columnAt(head:UiNode, n:UiNode, localX:Number):int
        {
            for (var j:int = 0; j < head.children.length; j++)
            {
                var cell:UiNode = head.children[j];
                var left:Number = cell.absX - n.absX;
                if (localX >= left && localX < left + cell.absW) return j;
            }
            return -1;
        }

        // ---- resize ---------------------------------------------------------
        private function onPress(n:UiNode, e:MouseEvent):void
        {
            this.endResize(n, false);          // a previous gesture that never saw its release
            // A new press ends any previous gesture, so a click the runtime dropped
            // cannot leave the header deaf forever (see the SWAL_KEY note in build()).
            n.extra[SWAL_KEY] = 0;
            if (Number(n.extra[RESZ_KEY]) == 0) return;
            var hdr:Boolean = Number(n.extra[HDR_KEY]) != 0;
            if (!hdr) return;
            var head:UiNode = n.children[0];
            if (head == null || head.children.length < 2) return;

            var lp:Point = this.localOf(n, e);
            var localX:Number = lp.x;
            var localY:Number = lp.y;
            if (localY >= head.absY - n.absY + head.absH) return;   // below the header

            // The boundary AFTER column i, for every column but the last.
            var col:int = -1;
            var bx:Number = -1;
            for (var i:int = 0; i < head.children.length - 1; i++)
            {
                var cell:UiNode = head.children[i];
                var x:Number = cell.absX - n.absX + cell.absW;
                if (Math.abs(localX - x) <= RESIZE_GRAB) { col = i; bx = x; break; }
            }
            if (col < 0) return;

            var st:Stage = n.app != null ? n.app.stage : null;
            if (st == null) return;
            n.extra[RCOL_KEY] = col;
            n.extra[PREV_KEY] = bx;
            n.extra[SWAL_KEY] = 1;             // the release's click is not a sort
            var self:TableWidget = this;
            var mv:Function = function (ev:MouseEvent):void { self.onResizeMove(n, ev); };
            var upFn:Function = function (ev:MouseEvent):void { self.endResize(n, true); };
            n.extra[MOVE_FN] = mv;
            n.extra[UP_FN] = upFn;
            st.addEventListener(MouseEvent.MOUSE_MOVE, mv);
            st.addEventListener(MouseEvent.MOUSE_UP, upFn);
            n.app.markPaint(n);
        }

        private function onResizeMove(n:UiNode, e:MouseEvent):void
        {
            var col:int = int(Number(n.extra[RCOL_KEY]));
            if (col < 0) return;
            var head:UiNode = n.children[0];
            if (head == null || col >= head.children.length) return;
            var left:Number = head.children[col].absX - n.absX;
            var rightEdge:Number = n.absW - 1;
            // Clamp inside the table AND above the minimum width: a preview line that
            // can leave the control would show a width the commit will not honour.
            var x:Number = this.localOf(n, e).x;
            if (x < left + MIN_COL_W) x = left + MIN_COL_W;
            if (x > rightEdge) x = rightEdge;
            if (x == Number(n.extra[PREV_KEY])) return;
            n.extra[PREV_KEY] = x;
            n.app.markPaint(n);
        }

        // `commit` is false for every path that is not the pointer's own release: a
        // previous gesture cancelled by a new press, or a teardown, must not write a
        // width into the author's model.
        private function endResize(n:UiNode, commit:Boolean):void
        {
            var st:Stage = n.app != null ? n.app.stage : null;
            var mv:Function = n.extra[MOVE_FN] as Function;
            var upFn:Function = n.extra[UP_FN] as Function;
            if (st != null)
            {
                if (mv != null) st.removeEventListener(MouseEvent.MOUSE_MOVE, mv);
                if (upFn != null) st.removeEventListener(MouseEvent.MOUSE_UP, upFn);
            }
            n.extra[MOVE_FN] = null;
            n.extra[UP_FN] = null;

            var col:int = int(Number(n.extra[RCOL_KEY]));
            var prevX:Number = Number(n.extra[PREV_KEY]);
            n.extra[RCOL_KEY] = -1;
            n.extra[PREV_KEY] = -1;
            if (col < 0) return;

            var head:UiNode = n.children[0];
            if (commit && head != null && col < head.children.length && prevX >= 0)
            {
                var left:Number = head.children[col].absX - n.absX;
                var w:Number = Math.round(prevX - left);
                if (w < MIN_COL_W) w = MIN_COL_W;
                var t:TableNode = TableNode(n.desc);
                if (t.onColumnResize != null)
                {
                    t.onColumnResize(col, w);
                    n.app.invalidate(Dirty.VALUE);
                }
            }
            n.app.markPaint(n);
        }

        // ---- wheel (only under `virtual`) -----------------------------------
        private function onWheel(n:UiNode, e:MouseEvent):void
        {
            if (Number(n.extra[VIRT_KEY]) == 0) return;
            var rh:Number = Number(n.extra[RH_KEY]);
            if (!(rh > 0)) return;
            var d:Number = e.delta;
            if (isNaN(d)) d = 0;
            if (d == 0) return;
            // Positive delta scrolls toward the START (Stage.dispatchWheel,
            // emit.ts:21504) -- the same convention as ScrollViewWidget and
            // VirtualListWidget, so a table inside a scrollView cannot fight it.
            var rows:int = d > 0 ? -WHEEL_STEP : WHEEL_STEP;
            this.request(n, int(Number(n.extra[OFF_KEY]) / rh) + rows);
            e.stopPropagation();   // a nested viewport must not also scroll
        }

        private function request(n:UiNode, firstWanted:int):void
        {
            var rh:Number = Number(n.extra[RH_KEY]);
            if (!(rh > 0)) return;
            var t:TableNode = TableNode(n.desc);
            var count:int = t.rowCount;
            var fit:int = t.visibleRows > 0 ? t.visibleRows : 1;
            var maxFirst:int = count - fit;
            if (maxFirst < 0) maxFirst = 0;
            var f:int = firstWanted;
            if (f > maxFirst) f = maxFirst;
            if (f < 0) f = 0;
            var y:Number = f * rh;
            // Already there: do not call back (an onScroll on every notch at the end
            // of the table would re-render the author's tree for nothing).
            if (y == Number(n.extra[OFF_KEY])) return;
            n.extra[OFF_KEY] = y;
            t.offsetY = y;
            if (t.onScroll != null) t.onScroll(y);
            n.app.markPaint(n);
        }
    }
}