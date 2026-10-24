// asaot.ui.anim.Anim -- the tween core: per (node, field) animation on WALL TIME.
//
// THE ONE SEAM IT EXPLOITS
// ------------------------
// Every widget paints from `n.resolved` (a Style). UiNode.resolveStyle computes
// `resolved` and then calls the animator, which re-aims the animatable fields
// while a tween is in flight. So EVERY widget animates with ZERO changes to any
// widget file -- the interception point is `resolved`, and `resolved` is the
// single source every paint reads.
//
// TWO FIELD CLASSES, ONE MECHANISM, DIFFERENT CONSEQUENCES
// -------------------------------------------------------
//   PAINT fields  (opacity / background / borderColor / textColor / cornerRadius)
//       Writing one changes pixels only. This is the default and stays
//       zero-reflow: the redraw probe pins that a paint-only change never
//       re-solves layout, and a paint tween honours it.
//   LAYOUT fields (width / height / padding x4 / gapX / gapY)
//       Writing one changes what FLEXBOX must compute, so every animated frame
//       re-solves the tree (`applyEngineStyle` + `markLayoutDirty`). That is not
//       a violation of the redraw rule -- the rule is about DECORATION never
//       reflowing; an author who animates `width` is explicitly asking the layout
//       to move each frame. The cost is honest and bounded by the tween's
//       duration, and it is why layout fields are opt-in per node: they only
//       animate when an author set `transitionMs` AND the field actually changes.
// Only POINT lengths animate. A percent/auto size has no meaningful interpolation
// (what is half of `auto`?), so those fields snap -- reported, not silently
// approximated. Uniform corner radii only: the box drawer honours `topLeft` and
// the toolkit always authors radii through `Corners.all(r)` (see
// PaintKit.drawBox); animating four divergent corners would animate a value this
// backend does not draw.
//
// WALL TIME, NOT FRAME COUNT
// --------------------------
// A tween advances by `(nowMs - startMs) / durMs`. A frame-counted tween runs at
// a different speed on a 60Hz and a 120Hz display; `getTimer()` is monotonic ms
// since program start (see View.tick), so the animation is speed-independent.
//
// STEADY STATE IS ZERO-ALLOCATION
// -------------------------------
// Tween records live in the node's `AnimState` (in `UiNode.extra`) and are
// rewritten in place on retarget. `advance` walks the static active list and
// writes numbers; it allocates nothing. The only allocations happen when a tween
// actually STARTS.
//
// DEFAULT IS UNCHANGED
// --------------------
// If a node's `resolved.transitionMs` is NaN (unset) and it has no live tween,
// UiNode never calls in here at all -- a settled tree still snaps, and the
// "zero describe/reflow work" invariant (pinned by CheckUi) is untouched.
package asaot.ui.anim
{
    import asaot.ui.Dirty;
    import asaot.ui.UiNode;
    import asaot.ui.style.Corners;
    import asaot.ui.style.Edges;
    import asaot.ui.style.Fill;
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;

    import flash.utils.getTimer;

    public final class Anim
    {
        // The fields the toolkit animates. The API is generic (any field string),
        // but only these have an apply/write-back path in applyField.
        public static const FIELD_OPACITY:String = "opacity";
        public static const FIELD_BACKGROUND:String = "background";
        public static const FIELD_BORDER:String = "borderColor";
        public static const FIELD_TEXT:String = "textColor";
        public static const FIELD_RADIUS:String = "cornerRadius";
        public static const FIELD_WIDTH:String = "width";
        public static const FIELD_HEIGHT:String = "height";
        public static const FIELD_PAD_T:String = "paddingTop";
        public static const FIELD_PAD_R:String = "paddingRight";
        public static const FIELD_PAD_B:String = "paddingBottom";
        public static const FIELD_PAD_L:String = "paddingLeft";
        public static const FIELD_GAP_X:String = "gapX";
        public static const FIELD_GAP_Y:String = "gapY";

        // Is this a field flexbox consumes (see the header)?
        public static function isLayoutField(field:String):Boolean
        {
            return field == FIELD_WIDTH || field == FIELD_HEIGHT
                || field == FIELD_PAD_T || field == FIELD_PAD_R
                || field == FIELD_PAD_B || field == FIELD_PAD_L
                || field == FIELD_GAP_X || field == FIELD_GAP_Y;
        }

        private static const ST_KEY:String = "__anim";

        // Static active list, walked by advance(). Swap-removed; order is
        // irrelevant. Never cleared wholesale (that would drop live tweens on a
        // scene change before their node is destroyed).
        private static var ACTIVE:Array = [];

        // ------------------------------------------------------------------
        // retarget: "this field should now be `to`". `from` is used only when
        // there is no record yet (first appearance); a live tween restarts from
        // its current interpolated value so a mid-flight retarget is continuous.
        // ------------------------------------------------------------------
        public static function retarget(node:UiNode, field:String, from:Number,
                                        to:Number, ms:int, ease:String):void
        {
            var st:AnimState = stateOf(node);
            var tw:Tween = tweenOf(st, field);

            // No target (unset style value): drop any tween and leave `resolved`
            // exactly as the resolver left it. Snapping to a sentinel would be a
            // silent wrong value.
            if (isNaN(to))
            {
                if (tw != null && tw.active) dropActive(tw);
                if (tw != null) st.tweens[field] = null;
                return;
            }

            var cur:Number;
            if (tw != null && tw.active)
            {
                if (tw.to == to)
                {
                    // Same target, still running: re-assert the interpolated
                    // value, because a resolve may have overwritten `resolved`
                    // with the raw target since the last advance.
                    applyField(node, field, tw.cur, st);
                    return;
                }
                cur = tw.cur;                 // retarget mid-flight
            }
            else
            {
                cur = tw != null ? tw.cur : from;
            }

            // Nothing meaningful to animate FROM (first frame after mount, or an
            // unset previous): snap rather than ease out of a bogus origin.
            if (isNaN(cur)) cur = to;

            if (cur == to)
            {
                // Already at the target: keep `resolved` as the resolver set it.
                if (tw != null)
                {
                    if (tw.active) dropActive(tw);
                    tw.cur = to;
                    tw.to = to;
                    tw.active = false;
                    tw.done = true;
                }
                return;
            }

            // Duration unset/zero: the documented default SNAP. Byte-for-byte
            // today's behaviour.
            if (isNaN(ms) || ms <= 0)
            {
                if (tw != null)
                {
                    if (tw.active) dropActive(tw);
                    st.tweens[field] = null;
                }
                applyField(node, field, to, st);
                return;
            }

            if (tw == null)
            {
                tw = new Tween();
                tw.node = node;
                tw.field = field;
                st.tweens[field] = tw;
                st.list.push(tw);
            }
            tw.node = node;
            tw.field = field;
            tw.from = cur;
            tw.to = to;
            tw.cur = cur;
            tw.startMs = Number(getTimer());
            tw.durMs = Number(ms);
            tw.ease = ease == null ? "linear" : ease;
            tw.done = false;
            Ease.apply(tw.ease, 0);   // validate the name eagerly (throws on typo)
            if (!tw.active)
            {
                tw.active = true;
                ACTIVE.push(tw);
            }
            applyField(node, field, cur, st);
        }

        // Current DISPLAYED value: the live tween's value, else `fallback`.
        public static function value(node:UiNode, field:String, fallback:Number):Number
        {
            var st:AnimState = stateOfIfAny(node);
            if (st == null) return fallback;
            var tw:Tween = tweenOf(st, field);
            if (tw == null) return fallback;
            return tw.cur;
        }

        // Advance every active tween to `nowMs`. Returns true while ANYTHING is
        // still animating (the caller uses that to keep repainting). A tween that
        // just landed still counts as "animating" for one more frame so its exact
        // final value gets painted.
        public static function advance(nowMs:Number):Boolean
        {
            var any:Boolean = false;
            var i:int = 0;
            while (i < ACTIVE.length)
            {
                var tw:Tween = Tween(ACTIVE[i]);
                if (!tw.active)
                {
                    removeAt(i);
                    continue;
                }
                var t:Number = (nowMs - tw.startMs) / tw.durMs;
                if (t < 0) t = 0;
                if (t >= 1)
                {
                    tw.cur = tw.to;                     // land EXACTLY on target
                    applyField(tw.node, tw.field, tw.cur, stateOf(tw.node));
                    if (!tw.done)
                    {
                        tw.done = true;
                        any = true;
                        i = i + 1;
                        continue;
                    }
                    tw.active = false;
                    removeAt(i);
                    continue;
                }
                var e:Number = Ease.apply(tw.ease, t);
                tw.cur = interpolate(tw.field, tw.from, tw.to, e);
                applyField(tw.node, tw.field, tw.cur, stateOf(tw.node));
                any = true;
                i = i + 1;
            }
            return any;
        }

        public static function isActive(node:UiNode):Boolean
        {
            var st:AnimState = stateOfIfAny(node);
            if (st == null) return false;
            var m:int = st.list.length;
            for (var i:int = 0; i < m; i++)
            {
                if (Tween(st.list[i]).active) return true;
            }
            return false;
        }

        // Drop this node's tweens (called from UiNode.destroySubtree). The record
        // objects are simply dropped for the GC; the node's bag is emptied so a
        // recycled node cannot inherit a dead tween.
        public static function clear(node:UiNode):void
        {
            var st:AnimState = stateOfIfAny(node);
            if (st == null) return;
            var m:int = st.list.length;
            for (var i:int = 0; i < m; i++)
            {
                var tw:Tween = Tween(st.list[i]);
                if (tw.active) dropActive(tw);
                tw.active = false;
                tw.node = null;
            }
            st.list.length = 0;
            st.tweens = {};
            st.bgFill = null;
            st.corners = null;
            st.sizeOwned = null;
            st.padOwned = null;
            if (node.extra != null) node.extra[ST_KEY] = null;
        }

        // The active-tween list, returned BY REFERENCE (no copy). UiApp walks it
        // after advance() to mark exactly the affected nodes paint-dirty.
        public static function activeList():Array
        {
            return ACTIVE;
        }

        // ------------------------------------------------------------------
        // internals
        // ------------------------------------------------------------------

        private static function stateOf(node:UiNode):AnimState
        {
            var st:AnimState = stateOfIfAny(node);
            if (st == null)
            {
                st = new AnimState();
                node.extra[ST_KEY] = st;
            }
            return st;
        }

        private static function stateOfIfAny(node:UiNode):AnimState
        {
            if (node == null || node.extra == null) return null;
            var raw:* = node.extra[ST_KEY];
            if (raw == null) return null;
            return AnimState(raw);
        }

        private static function tweenOf(st:AnimState, field:String):Tween
        {
            var raw:* = st.tweens[field];
            if (raw == null) return null;
            return Tween(raw);
        }

        private static function dropActive(tw:Tween):void
        {
            var m:int = ACTIVE.length;
            for (var i:int = 0; i < m; i++)
            {
                if (ACTIVE[i] === tw)
                {
                    removeAt(i);
                    return;
                }
            }
        }

        private static function removeAt(i:int):void
        {
            var last:int = ACTIVE.length - 1;
            if (i != last) ACTIVE[i] = ACTIVE[last];
            ACTIVE.pop();
        }

        private static function isColorField(field:String):Boolean
        {
            return field == FIELD_BACKGROUND || field == FIELD_BORDER || field == FIELD_TEXT;
        }

        private static function interpolate(field:String, from:Number, to:Number, e:Number):Number
        {
            if (isColorField(field)) return lerpArgb(from, to, e);
            return from + (to - from) * e;
        }

        // Per-CHANNEL ARGB interpolation. Interpolating the packed 32-bit number
        // as one integer is WRONG: a carry from the low byte bleeds into the
        // green/red channels (blue->red would swing green up then down). Each
        // channel is monotone on its own, which is what the probe's "each channel
        // must not go backwards" assertion pins.
        private static function lerpArgb(from:Number, to:Number, e:Number):Number
        {
            var f:uint = uint(from);
            var t:uint = uint(to);
            var a:Number = Number((f >>> 24) & 0xFF) + Number(((t >>> 24) & 0xFF) - ((f >>> 24) & 0xFF)) * e;
            var r:Number = Number((f >>> 16) & 0xFF) + Number(((t >>> 16) & 0xFF) - ((f >>> 16) & 0xFF)) * e;
            var g:Number = Number((f >>> 8) & 0xFF) + Number(((t >>> 8) & 0xFF) - ((f >>> 8) & 0xFF)) * e;
            var b:Number = Number(f & 0xFF) + Number((t & 0xFF) - (f & 0xFF)) * e;
            var out:uint = (uint(a) << 24) | (uint(r) << 16) | (uint(g) << 8) | uint(b);
            return Number(out);
        }

        // Write the animated value back into the node's resolved Style. These are
        // exactly the fields every widget paints from, so this is the whole
        // reason no widget file needs to change.
        private static function applyField(node:UiNode, field:String, v:Number, st:AnimState):void
        {
            if (node == null || node.resolved == null) return;
            if (field == FIELD_OPACITY)
            {
                node.resolved.opacity = v;
                return;
            }
            if (field == FIELD_BACKGROUND)
            {
                var f:Fill = st.bgFill;
                if (f == null)
                {
                    f = new Fill(0xFF000000);
                    st.bgFill = f;
                }
                f.argb = v;
                node.resolved.background = f;
                return;
            }
            if (field == FIELD_BORDER)
            {
                node.resolved.borderColor = v;
                return;
            }
            if (field == FIELD_TEXT)
            {
                // `resolved.text` is the node's OWN TextStyle (Style.copyInto and
                // Theme.resolve both copy INTO it), so this needs no owned copy.
                node.resolved.text.color = v;
                return;
            }
            if (field == FIELD_RADIUS)
            {
                var c:Corners = st.corners;
                if (c == null)
                {
                    var rc:Corners = node.resolved.cornerRadii;
                    c = new Corners(rc != null ? rc.topLeft : NaN, rc != null ? rc.topRight : NaN,
                                    rc != null ? rc.bottomRight : NaN, rc != null ? rc.bottomLeft : NaN);
                    st.corners = c;
                }
                c.topLeft = v; c.topRight = v; c.bottomRight = v; c.bottomLeft = v;
                node.resolved.cornerRadii = c;
                return;
            }

            // ---- layout fields (see the header) -------------------------
            // Guarded: a typo'd field name must be a no-op, not a silent engine write.
            if (!isLayoutField(field)) return;
            if (field == FIELD_WIDTH || field == FIELD_HEIGHT)
            {
                var sz:Size = st.sizeOwned;
                if (sz == null)
                {
                    var cur:Size = node.resolved.size;
                    sz = new Size(cur != null ? cur.width : null, cur != null ? cur.height : null);
                    st.sizeOwned = sz;
                }
                if (field == FIELD_WIDTH) sz.width = Length.px(v);
                else sz.height = Length.px(v);
                node.resolved.size = sz;
            }
            else if (field == FIELD_GAP_X)
            {
                node.resolved.gapX = v;
            }
            else if (field == FIELD_GAP_Y)
            {
                node.resolved.gapY = v;
            }
            else
            {
                var e:Edges = st.padOwned;
                if (e == null)
                {
                    var cp:Edges = node.resolved.padding;
                    e = new Edges(cp != null ? cp.top : NaN, cp != null ? cp.right : NaN,
                                  cp != null ? cp.bottom : NaN, cp != null ? cp.left : NaN);
                    st.padOwned = e;
                }
                if (field == FIELD_PAD_T) e.top = v;
                else if (field == FIELD_PAD_R) e.right = v;
                else if (field == FIELD_PAD_B) e.bottom = v;
                else e.left = v;
                node.resolved.padding = e;
            }
            // THE LAYOUT HALF OF THE SEAM. Push the new numbers into the engine and
            // raise the bits reflow reads, in the same call: the animation frame may
            // land outside any resolve (the author changed nothing), so nothing else
            // would ever tell the engine or the dirty gate about it.
            node.applyEngineStyle();
            node.markLayoutDirty();
            node.dirty = node.dirty | Dirty.M_PAINT;
        }
    }
}