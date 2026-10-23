// asaot.ui.OverlayList -- the shared ROW MATH of the two item surfaces in the
// floating layer (the `menu` popup and the `select` dropdown).
//
// WHY A CLASS AND NOT PACKAGE FUNCTIONS: mxmlc resolves a package-level function
// only from a file NAMED after it (compiler-gaps.md G7), so two widgets cannot
// share a free function. Grouping the geometry as statics is the established
// escape hatch (see OptionSupport).
//
// EVERYTHING HERE READS THE CHILDREN'S SOLVED RECTS -- never arithmetic over
// "itemHeight * index". That is the same rule TableWidget follows, and it is what
// lets a probe assert a band lands exactly where the engine put the row: if the
// engine and the painter ever disagreed, the painter would be wrong, not the
// reference.
package asaot.ui
{
    import flash.display.DisplayObject;
    import flash.events.MouseEvent;

    public final class OverlayList
    {
        public static const HOVER_KEY:String = "hoverRow";
        public static const SEL_KEY:String = "selRow";
        public static const HIT_KEY:String = "hitRow";

        // The ONE definition of "an option is a string or { label, value }". Both
        // the menu and the select accept that shape, so the parsing lives here.
        // A missing `value` falls back to the INDEX as a string -- an item list
        // without values is still addressable by position.
        public static function labelOf(item:Object):String
        {
            if (item == null) return "";
            if (item is String) return String(item);
            return item.label == null ? "" : String(item.label);
        }

        public static function valueOf(item:Object, index:int):String
        {
            if (item == null) return String(index);
            if (item is String) return String(item);
            return item.value == null ? String(index) : String(item.value);
        }

        // Which child row contains `ly` (the point in the CONTAINER's local space)?
        // -1 when the point is in the padding. Rects come from the engine's arrange
        // pass (absX/absY), never from `rowHeight * index`.
        public static function rowAt(n:UiNode, ly:Number):int
        {
            for (var i:int = 0; i < n.children.length; i++)
            {
                var c:UiNode = n.children[i];
                var top:Number = c.absY - n.absY;
                if (ly >= top && ly < top + c.absH) return i;
            }
            return -1;
        }

        // The click's Y in `n`'s own space, WHICHEVER node inside it was hit.
        //
        // MouseEvent.localX/localY are TARGET-relative and stay that way while the
        // event bubbles (the runtime matches AIR here), so a click that lands on a
        // ROW reports row-local coordinates. Reading `e.localY` as if it were the
        // container's own silently broke row routing: the value is always inside
        // 0..rowHeight, which can only ever land on the first rows. Walking the
        // parent offsets up to `n.backing` is exact for a real click, for a
        // programmatic dispatch and for an event dispatched straight at `n.backing`
        // alike -- and it needs no stage coordinates, which a dispatched event
        // leaves at 0.
        //
        // NaN when the point is NOT inside `n` (the chain never reaches it): every
        // comparison in rowAt is then false, so the caller gets the same -1 it gets
        // for padding, without a second guard.
        public static function localYIn(n:UiNode, e:MouseEvent):Number
        {
            var y:Number = e.localY;
            var t:DisplayObject = e.target as DisplayObject;
            while (t != null && t != n.backing)
            {
                y += t.y;
                t = t.parent;
            }
            if (t == null) return Number.NaN;
            return y;
        }
        // Paint a highlight band behind row `row` (0-based child index), in the
        // container's local coordinates. A negative index paints nothing, which is
        // how "no hover" is spelled.
        public static function band(n:UiNode, row:int, argb:uint):void
        {
            if (n.shapeA == null) return;
            if (row < 0 || row >= n.children.length) return;
            var c:UiNode = n.children[row];
            var g:Object = n.shapeA.graphics;
            g.beginFill(argb, 1.0);
            g.drawRect(c.absX - n.absX, c.absY - n.absY, c.absW, c.absH);
            g.endFill();
        }

        public function OverlayList() { }
    }
}