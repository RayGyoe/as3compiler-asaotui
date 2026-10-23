// asaot.ui.UiNode -- the RETAINED tree node (design doc section 1.3).
//
// One UiNode owns exactly ONE top-level backing DisplayObject (section 4.1); the
// control may hold several display objects INSIDE it (a button's shape + label),
// but those are not UiNodes and never participate in layout or focus.
//
// Retained is the whole point: the pointer IS the identity, so hover / scroll /
// measurement / focus survive a reconcile with no external state map -- unlike
// GPUI, which stores element state in a window-level map keyed by a hashed
// GlobalElementId (asaotui/gpui-src/crates/gpui/src/element.rs:220-231). Our
// `state` is right here, inline, and never hashed.
//
// measure / arrange / paint are the three passes of section 3.1:
//   measure  <-> GPUI Element::request_layout (element.rs:74)
//   arrange  <-> GPUI Element::prepaint       (element.rs:84, takes final bounds)
//   paint    <-> GPUI Element::paint          (element.rs:96)
package asaot.ui
{
    import asaot.ui.style.Style;
    import asaot.ui.style.StyleRefinement;
    import asaot.ui.style.Length;
    import asaot.ui.style.Edges;
    import asaot.ui.style.LengthEdges;
    import asaot.ui.style.Corners;
    import asaot.ui.style.Fill;
    import asaot.ui.style.TextStyle;

    import asaot.ui.LayoutConstants;
    import asaot.ui.anim.Anim;

    import flash.display.Sprite;
    import flash.display.Shape;
    import flash.text.TextField;
    import flash.events.MouseEvent;

    public class UiNode
    {
        // ---- identity ---------------------------------------------------
        public var kind:String;
        public var key:Object;
        public var keyId:int;          // interned key id; -1 == index identity
        public var keyContext:String;

        // ---- tree -------------------------------------------------------
        public var app:UiApp;
        public var parent:UiNode;
        public var children:Vector.<UiNode>;

        // ---- retained backing + state -----------------------------------
        public var backing:Sprite;
        public var resolved:Style;     // node-owned resolved buffer
        public var previous:Style;     // snapshot of the previous resolve (diff)
        public var lastStyle:StyleRefinement;
        public var lastStyleStale:Boolean;
        public var state:ElementState;
        public var dirty:int;
        public var engineNode:Object;
        // The per-kind behaviour (Widget.as). Resolved once, at structure time,
        // from Widgets.require(kind); a miss THROWS (never an invisible hole).
        public var widget:Widget;
        // The description Node this frame was reconciled from. Widgets cast it
        // to their own Node type to read kind-specific fields (never null while
        // reconciling). Held by reference only -- render() builds a fresh tree
        // every frame and this is overwritten, never accumulated.
        public var desc:Node;
        // Per-node scratch for widget-private state (last-seen payload values, so
        // `payload` can report a change without reflowing on every frame).
        // Allocated ONCE per node at structure time -- steady state allocates
        // nothing (AGENTS.md memory rule).
        public var extra:Object;

        // ---- control payload (mirrored from the description node) --------
        public var textContent:String;
        public var label:String;
        public var value:String;
        public var placeholder:String;
        public var password:Boolean;
        public var checked:Boolean;
        public var binding:Binding;
        public var onClick:Function;
        public var onCommit:Function;
        public var onChange:Function;
        public var role:String;
        public var ariaName:String;
        public var directionOverride:String;
        public var visible:Boolean;
        public var action:String;

        // ---- backing internals ------------------------------------------
        public var shapeA:Shape;
        public var shapeB:Shape;
        public var tf:TextField;

        // ---- last final rect (absolute, in the root's coordinate space) --
        public var absX:Number;
        public var absY:Number;
        public var absW:Number;
        public var absH:Number;

        // Reconcile scratch (no allocation): `matched` marks a child already
        // claimed by a keyed match in THIS pass; `lastIndex` is the sibling index
        // used to derive an index-based identity token; `internalCount` is how
        // many internal display objects come before the UiNode children in the
        // backing, so display-order fixes use the right base index.
        public var matched:Boolean;
        public var lastIndex:int;
        public var internalCount:int;

        public function UiNode(kind:String, app:UiApp):void
        {
            this.kind = kind;
            this.app = app;
            this.key = null;
            this.keyId = -1;
            this.keyContext = null;
            this.parent = null;
            this.children = new Vector.<UiNode>();
            this.resolved = new Style();
            this.previous = new Style();
            this.lastStyle = null;
            this.lastStyleStale = true;
            this.state = new ElementState();
            this.dirty = 0;
            this.engineNode = null;
            this.widget = null;
            this.desc = null;
            this.extra = {};
            this.textContent = null;
            this.label = null;
            this.value = null;
            this.placeholder = null;
            this.password = false;
            this.checked = false;
            this.binding = null;
            this.onClick = null;
            this.onCommit = null;
            this.onChange = null;
            this.role = null;
            this.ariaName = null;
            this.directionOverride = null;
            this.visible = true;
            this.action = null;
            this.shapeA = null;
            this.shapeB = null;
            this.tf = null;
            this.absX = 0; this.absY = 0; this.absW = 0; this.absH = 0;
            this.matched = false;
            this.lastIndex = 0;
            this.internalCount = 0;
            createBacking();
        }

        // ---- backing construction (only at structure time) ---------------
        private function createBacking():void
        {
            this.backing = new Sprite();
            var self:UiNode = this;

            // Everything that DIFFERS per kind lives behind one Widget instance
            // (see Widget.as). The display objects are created by build(), lowest
            // layer first, so the UiNode children keep a stable base index for
            // display-order repair.
            this.widget = Widgets.require(this.kind);
            this.widget.build(this);

            this.internalCount = this.backing.numChildren;
            // Hover / press / click are handled on the backing object, so the
            // hit region is the control's drawn region -- the same region the
            // existing pick test (as_pick_hit_local) walks.
            this.backing.addEventListener(MouseEvent.MOUSE_OVER, function (e:MouseEvent):void { self.setHover(1); });
            this.backing.addEventListener(MouseEvent.MOUSE_OUT, function (e:MouseEvent):void { self.setHover(0); });
            if (this.widget.wantsPress())
            {
                this.backing.addEventListener(MouseEvent.MOUSE_DOWN, function (e:MouseEvent):void { self.setPressed(1); });
                this.backing.addEventListener(MouseEvent.MOUSE_UP, function (e:MouseEvent):void { self.setPressed(0); });
                this.backing.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void { self.handleClick(); });
            }
        }

        // ---- transient state changes (paint-only, never a reflow) --------
        public function setHover(v:int):void
        {
            if (this.state.hover == v) return;
            this.state.hover = v;
            // Section 3.3: a hover DECORATES only; it must never reflow.
            this.app.markPaint(this);
        }

        public function setPressed(v:int):void
        {
            if (this.state.pressed == v) return;
            this.state.pressed = v;
            this.app.markPaint(this);
        }

        public function handleClick():void
        {
            this.setPressed(0);
            if (this.widget.click(this)) return;
            if (this.onClick != null) this.onClick();
        }

        // ---- payload mirroring (called by the reconciler) ---------------
        // The generic Element part is copied here; everything kind-specific is
        // the widget's business (Widget.payload), which returns true when the
        // change forces a re-measure.
        // Returns true when a payload change forced a re-measure.
        public function applyPayload(desc:Node):Boolean
        {
            this.desc = desc;
            this.role = Element(desc).role;
            this.ariaName = Element(desc).ariaName;
            this.visible = Element(desc).visible;

            var dirBefore:String = this.directionOverride;
            var relayout:Boolean = this.widget.payload(this, desc);
            if (relayout)
            {
                this.dirty |= Dirty.M_MEASURE | Dirty.M_ARRANGE | Dirty.M_PAINT;
                this.markLayoutDirty();
                // `directionOverride` (BoxNode's row/column) feeds Theme.resolve,
                // and the resolve for this pass ALREADY ran -- the reconciler
                // resolves, then applies the payload. Re-running it here is what
                // makes a direction change take effect in the same frame; without
                // it the node keeps laying out in its old direction FOREVER, because
                // the style pointer is unchanged on later renders so nothing would
                // ever re-resolve it. (Found by the multi-page demo: a swapped page
                // body kept the previous page's direction and laid its children out
                // along the wrong axis.) `true` keeps `previous` untouched -- it is
                // the animator's "from" value and re-basing it would silently cancel
                // a tween that happens to land on a direction-change frame.
                if (this.directionOverride != dirBefore) this.resolveStyle(true);
            }
            return relayout;
        }

        // ---- resolve -----------------------------------------------------

        // Raise measure+arrange dirty on THIS node and every ancestor that does not
        // already carry it.
        //
        // WHY THIS EXISTS: the layout gate in UiApp.reflow reads the ROOT's bits
        // only (`root.dirty & (M_MEASURE|M_ARRANGE)`), and a change deep in the
        // tree raises its bits locally. So a subtree that was created, reordered or
        // restyled on any frame AFTER the first one was attached to the engine tree
        // but NEVER solved -- it kept the layoutGet defaults of 0,0,0,0 forever,
        // endlessly re-painted as an invisible node. The first multi-page demo
        // found this the day a page swap replaced a subtree: the swap worked, the
        // nodes existed, and the whole page rendered as an empty sheet.
        //
        // Stopping the climb at the first ancestor that already has BOTH bits is
        // safe because this method is the only writer: if a node has both, every
        // ancestor of it has both (measurePass/arrangePass clear the bits on every
        // node during a pass, and every raise goes through here).
        //
        // The PAINT bit is deliberately NOT raised along the chain: an ancestor
        // whose own decoration did not change must not be repainted, and a
        // paint-only change must still not re-solve layout (probes/redraw pins
        // exactly that).
        public function markLayoutDirty():void
        {
            this.dirty |= Dirty.M_MEASURE | Dirty.M_ARRANGE;
            var n:UiNode = this.parent;
            while (n != null)
            {
                if ((n.dirty & (Dirty.M_MEASURE | Dirty.M_ARRANGE)) == (Dirty.M_MEASURE | Dirty.M_ARRANGE)) return;
                n.dirty |= Dirty.M_MEASURE | Dirty.M_ARRANGE;
                n = n.parent;
            }
        }
        public function resolveStyle(keepPrevious:Boolean = false):void
        {
            // `previous` is the animator's "from" state and the diff baseline. A
            // second resolve inside the SAME pass must not re-base it on the value
            // the first resolve just produced, or the diff collapses to zero and a
            // tween's start value becomes its end value (see applyPayload).
            if (!keepPrevious) this.resolved.copyInto(this.previous);
            Theme.resolve(this.resolved, this.kind, this.parent != null ? this.parent.resolved : null,
                this.lastStyle, this.directionOverride);
            var f:int = Style.diffFlags(this.previous, this.resolved);
            if ((f & 1) != 0) { this.dirty |= Dirty.M_MEASURE | Dirty.M_ARRANGE | Dirty.M_PAINT; this.markLayoutDirty(); }
            if ((f & 2) != 0) { this.dirty |= Dirty.M_MEASURE | Dirty.M_PAINT; this.markLayoutDirty(); }
            if ((f & 4) != 0) this.dirty |= Dirty.M_PAINT;
            // A change to the INHERITED subset must invalidate every descendant's
            // resolve, because their `lastStyle` pointers did not change but the
            // parent contribution they inherit did (section 2.3 / 2.4, the same
            // reason `setTheme()` stales the whole tree).
            if (Style.diffFlags(this.previous, this.resolved) != 0 && inheritedChanged(this.previous, this.resolved))
            {
                staleDescendants();
            }
            // ANIMATION SEAM: re-aim the animatable fields AFTER the resolver has
            // produced the target. This is the ONE interception point -- every
            // widget paints from `resolved`, so post-processing it animates every
            // widget with no widget-file change. A NaN `transitionMs` with no live
            // tween makes this a no-op (the default snap path).
            this.applyAnim();
            this.applyEngineStyle();
            this.lastStyleStale = false;
        }

        // Post-resolve animation hook (see the call site in resolveStyle). It
        // retargets the three animatable fields toward the freshly resolved
        // values, interpolating from the currently DISPLAYED value so a change
        // mid-flight stays continuous. `transitionMs` is the duration; unset
        // (NaN) means snap, and if nothing is animating we return before
        // touching anything -- the settled-tree invariant is preserved.
        private function applyAnim():void
        {
            var ms:Number = this.resolved.transitionMs;
            var animate:Boolean = !isNaN(ms) && ms > 0;
            var active:Boolean = Anim.isActive(this);
            if (!animate && !active) return;

            var ease:String = this.resolved.transitionEase;

            // opacity: displayed default when unset is 1 (backing.alpha).
            var toOp:Number = isNaN(this.resolved.opacity) ? 1 : this.resolved.opacity;
            var prevOp:Number = isNaN(this.previous.opacity) ? 1 : this.previous.opacity;
            var curOp:Number = Anim.value(this, Anim.FIELD_OPACITY, prevOp);
            if (active || curOp != toOp)
            {
                Anim.retarget(this, Anim.FIELD_OPACITY, curOp, toOp, ms, ease);
            }

            // background: the packed 0xAARRGGBB of a SOLID fill.
            var toBg:Number = this.resolved.background != null ? this.resolved.background.argb : NaN;
            var prevBg:Number = this.previous.background != null ? this.previous.background.argb : NaN;
            var curBg:Number = Anim.value(this, Anim.FIELD_BACKGROUND, prevBg);
            if (active || curBg != toBg)
            {
                Anim.retarget(this, Anim.FIELD_BACKGROUND, curBg, toBg, ms, ease);
            }

            // borderColor: the packed 0xRRGGBB.
            var toBc:Number = this.resolved.borderColor;
            var curBc:Number = Anim.value(this, Anim.FIELD_BORDER, this.previous.borderColor);
            if (active || curBc != toBc)
            {
                Anim.retarget(this, Anim.FIELD_BORDER, curBc, toBc, ms, ease);
            }
        }

        private function inheritedChanged(a:Style, b:Style):Boolean
        {
            if (a.visibility != b.visibility) return true;
            return textDiffers(a, b);
        }

        private function textDiffers(a:Style, b:Style):Boolean
        {
            var ta:TextStyle = a.text;
            var tb:TextStyle = b.text;
            return ta.fontFamily != tb.fontFamily || isNaN(ta.fontSize) != isNaN(tb.fontSize)
                || ta.fontSize != tb.fontSize || ta.fontWeight != tb.fontWeight
                || ta.fontStyle != tb.fontStyle || ta.color != tb.color
                || ta.leading != tb.leading || ta.letterSpacing != tb.letterSpacing
                || ta.textAlign != tb.textAlign;
        }

        public function staleDescendants():void
        {
            for (var i:int = 0; i < this.children.length; i++)
            {
                this.children[i].lastStyleStale = true;
                this.children[i].staleDescendants();
            }
        }

        // Push the SUPPORTED style surface onto the layout engine. Uses ONLY the
        // seam surface listed as implemented (seam/README.md section 4): row /
        // column, point + percent size, min/max, flex grow/shrink/basis, point
        // padding, point border, point gap, box-sizing. Every other GPUI field is
        // absent from Style on purpose, and the seam throws if anything reaches
        // for an unimplemented setter.
        public function applyEngineStyle():void
        {
            if (this.engineNode == null) return;
            var eng:LayoutEngine = this.app.engine;
            var n:Object = this.engineNode;
            var s:Style = this.resolved;

            var dir:int = (s.flexDirection == "row") ? LayoutConstants.FLEX_DIR_ROW
                : LayoutConstants.FLEX_DIR_COLUMN;
            eng.setFlexDirection(n, dir);

            applyAxis(eng, n, LayoutConstants.AXIS_WIDTH, s.size != null ? s.size.width : null);
            applyAxis(eng, n, LayoutConstants.AXIS_HEIGHT, s.size != null ? s.size.height : null);

            var minW:Length = s.minSize != null ? s.minSize.width : null;
            var minH:Length = s.minSize != null ? s.minSize.height : null;
            var maxW:Length = s.maxSize != null ? s.maxSize.width : null;
            var maxH:Length = s.maxSize != null ? s.maxSize.height : null;
            eng.setMinMax(n, LayoutConstants.AXIS_WIDTH, false, lenVal(minW), lenUnit(minW));
            eng.setMinMax(n, LayoutConstants.AXIS_HEIGHT, false, lenVal(minH), lenUnit(minH));
            eng.setMinMax(n, LayoutConstants.AXIS_WIDTH, true, lenVal(maxW), lenUnit(maxW));
            eng.setMinMax(n, LayoutConstants.AXIS_HEIGHT, true, lenVal(maxH), lenUnit(maxH));

            var anyFlex:Boolean = !isNaN(s.flexGrow) || !isNaN(s.flexShrink) || s.flexBasis != null;
            if (anyFlex)
            {
                var grow:Number = isNaN(s.flexGrow) ? 0 : s.flexGrow;
                var shrink:Number = isNaN(s.flexShrink) ? 1 : s.flexShrink;
                var bu:int = LayoutConstants.UNIT_UNDEFINED;
                var bv:Number = 0;
                if (s.flexBasis != null)
                {
                    bu = s.flexBasis.toEngineUnit();
                    bv = s.flexBasis.toEngineValue();
                }
                eng.setFlex(n, grow, shrink, bv, bu);
            }

            if (s.padding != null) applyEdges(eng, n, s.padding, false, 0);
            if (s.borderWidths != null) applyEdges(eng, n, s.borderWidths, true, 0);

            if (!isNaN(s.gapX) || !isNaN(s.gapY))
            {
                var gx:Number = isNaN(s.gapX) ? 0 : s.gapX;
                var gy:Number = isNaN(s.gapY) ? 0 : s.gapY;
                if (gx == gy) eng.setGap(n, LayoutConstants.GUTTER_ALL, gx, LayoutConstants.UNIT_POINT);
                else
                {
                    eng.setGap(n, LayoutConstants.GUTTER_COLUMN, gx, LayoutConstants.UNIT_POINT);
                    eng.setGap(n, LayoutConstants.GUTTER_ROW, gy, LayoutConstants.UNIT_POINT);
                }
            }

            eng.setBoxSizing(n, s.boxSizing == "contentBox"
                ? LayoutConstants.BOX_SIZING_CONTENT_BOX : LayoutConstants.BOX_SIZING_BORDER_BOX);

            // Alignment / wrap / margin / inset / position / overflow / display /
            // aspect-ratio. Each setter is called ONLY when its field is set, so
            // an unset field leaves the engine's own default alone -- that is the
            // whole point of the unset sentinel. An unknown STRING value throws
            // (see the *Const helpers below).
            if (s.justifyContent != null) eng.setJustifyContent(n, justifyConst(s.justifyContent));
            if (s.alignItems != null) eng.setAlignItems(n, childAlignConst(s.alignItems, "alignItems"));
            if (s.alignSelf != null) eng.setAlignSelf(n, childAlignConst(s.alignSelf, "alignSelf"));
            if (s.alignContent != null) eng.setAlignContent(n, contentAlignConst(s.alignContent));
            if (s.flexWrap != null) eng.setFlexWrap(n, wrapConst(s.flexWrap));
            if (s.margin != null) applyLengthEdges(eng, n, s.margin, false);
            if (s.inset != null) applyLengthEdges(eng, n, s.inset, true);
            if (s.position != null) eng.setPositionType(n, positionConst(s.position));
            if (s.overflow != null) eng.setOverflow(n, overflowConst(s.overflow));
            if (s.display != null) eng.setDisplay(n, displayConst(s.display));
            // aspectRatio <= 0 (and NaN) is the unset sentinel: no call at all.
            if (!isNaN(s.aspectRatio) && s.aspectRatio > 0) eng.setAspectRatio(n, s.aspectRatio);
        }

        private function applyAxis(eng:LayoutEngine, n:Object, axis:int, l:Length):void
        {
            if (l == null || l.isAuto()) eng.setSize(n, axis, 0, LayoutConstants.UNIT_UNDEFINED);
            else eng.setSize(n, axis, l.toEngineValue(), l.toEngineUnit());
        }

        private function applyEdges(eng:LayoutEngine, n:Object, e:Edges, isBorder:Boolean, basis:Number):void
        {
            applySide(eng, n, e.top, LayoutConstants.EDGE_TOP, isBorder);
            applySide(eng, n, e.right, LayoutConstants.EDGE_RIGHT, isBorder);
            applySide(eng, n, e.bottom, LayoutConstants.EDGE_BOTTOM, isBorder);
            applySide(eng, n, e.left, LayoutConstants.EDGE_LEFT, isBorder);
        }

        private function applySide(eng:LayoutEngine, n:Object, v:Number, edge:int, isBorder:Boolean):void
        {
            if (isNaN(v)) return;
            if (isBorder) eng.setBorder(n, edge, v);
            else eng.setPadding(n, edge, v, LayoutConstants.UNIT_POINT);
        }

        private function lenVal(l:Length):Number { return l == null ? 0 : l.toEngineValue(); }
        private function lenUnit(l:Length):int
        {
            return l == null ? LayoutConstants.UNIT_UNDEFINED : l.toEngineUnit();
        }

        // ---- new style fields -> seam setter value maps -------------------
        // Every map below THROWS on an unknown value, naming the field, the
        // offending value and the accepted set (AGENTS.md 2.5: never a silent
        // fallback). The constants are the exact LayoutConstants names.
        private function justifyConst(v:String):int
        {
            if (v == "flex-start") return LayoutConstants.JUSTIFY_FLEX_START;
            if (v == "flex-end") return LayoutConstants.JUSTIFY_FLEX_END;
            if (v == "center") return LayoutConstants.JUSTIFY_CENTER;
            if (v == "space-between") return LayoutConstants.JUSTIFY_SPACE_BETWEEN;
            if (v == "space-around") return LayoutConstants.JUSTIFY_SPACE_AROUND;
            if (v == "space-evenly") return LayoutConstants.JUSTIFY_SPACE_EVENLY;
            throw badValue("justifyContent", v,
                "flex-start | flex-end | center | space-between | space-around | space-evenly");
        }

        // align-items / align-self share one set. `baseline` maps to
        // ALIGN_BASELINE -- a native-only value the pure-AS3 subset rejects
        // loudly rather than silently aliasing.
        private function childAlignConst(v:String, field:String):int
        {
            if (v == "flex-start") return LayoutConstants.ALIGN_FLEX_START;
            if (v == "flex-end") return LayoutConstants.ALIGN_FLEX_END;
            if (v == "center") return LayoutConstants.ALIGN_CENTER;
            if (v == "stretch") return LayoutConstants.ALIGN_STRETCH;
            if (v == "baseline") return LayoutConstants.ALIGN_BASELINE;
            throw badValue(field, v, "flex-start | flex-end | center | stretch | baseline");
        }

        private function contentAlignConst(v:String):int
        {
            if (v == "flex-start") return LayoutConstants.ALIGN_FLEX_START;
            if (v == "flex-end") return LayoutConstants.ALIGN_FLEX_END;
            if (v == "center") return LayoutConstants.ALIGN_CENTER;
            if (v == "stretch") return LayoutConstants.ALIGN_STRETCH;
            if (v == "space-between") return LayoutConstants.ALIGN_SPACE_BETWEEN;
            if (v == "space-around") return LayoutConstants.ALIGN_SPACE_AROUND;
            throw badValue("alignContent", v,
                "flex-start | flex-end | center | stretch | space-between | space-around");
        }

        private function wrapConst(v:String):int
        {
            if (v == "nowrap") return LayoutConstants.WRAP_NO_WRAP;
            if (v == "wrap") return LayoutConstants.WRAP_WRAP;
            if (v == "wrap-reverse") return LayoutConstants.WRAP_WRAP_REVERSE;
            throw badValue("flexWrap", v, "nowrap | wrap | wrap-reverse");
        }

        private function positionConst(v:String):int
        {
            if (v == "relative") return LayoutConstants.POSITION_RELATIVE;
            if (v == "absolute") return LayoutConstants.POSITION_ABSOLUTE;
            if (v == "static") return LayoutConstants.POSITION_STATIC;
            throw badValue("position", v, "relative | absolute | static");
        }

        private function overflowConst(v:String):int
        {
            if (v == "visible") return LayoutConstants.OVERFLOW_VISIBLE;
            if (v == "hidden") return LayoutConstants.OVERFLOW_HIDDEN;
            if (v == "scroll") return LayoutConstants.OVERFLOW_SCROLL;
            throw badValue("overflow", v, "visible | hidden | scroll");
        }

        private function displayConst(v:String):int
        {
            if (v == "flex") return LayoutConstants.DISPLAY_FLEX;
            if (v == "none") return LayoutConstants.DISPLAY_NONE;
            throw badValue("display", v, "flex | none");
        }

        private function badValue(field:String, v:String, accepted:String):Error
        {
            return new Error("Style." + field + ": unknown value '" + v + "' (accepted: " + accepted + ")");
        }

        // margin / inset: one (value, unit) pair per side. An `auto` side maps
        // to the seam's UNIT_AUTO (Yoga's centring mechanism); the pure-AS3
        // subset rejects an auto margin loudly, so we forward it rather than
        // silently dropping it.
        private function applyLengthEdges(eng:LayoutEngine, n:Object, le:LengthEdges, isInset:Boolean):void
        {
            applyLengthSide(eng, n, le.top, LayoutConstants.EDGE_TOP, isInset);
            applyLengthSide(eng, n, le.right, LayoutConstants.EDGE_RIGHT, isInset);
            applyLengthSide(eng, n, le.bottom, LayoutConstants.EDGE_BOTTOM, isInset);
            applyLengthSide(eng, n, le.left, LayoutConstants.EDGE_LEFT, isInset);
        }

        private function applyLengthSide(eng:LayoutEngine, n:Object, l:Length, edge:int, isInset:Boolean):void
        {
            if (l == null) return;
            var v:Number = l.isAuto() ? 0 : l.toEngineValue();
            var u:int = l.isAuto() ? LayoutConstants.UNIT_AUTO : l.toEngineUnit();
            if (isInset) eng.setPosition(n, edge, v, u);
            else eng.setMargin(n, edge, v, u);
        }

        // ---- pass 1: measure (intrinsic sizing for auto-sized leaves) ----
        // The pure-AS3 engine has NO measure callback (setMeasure throws, see
        // seam/README.md section 4), so intrinsic text sizing is a TWO-STEP
        // approximation: this pass measures the text through a real TextField and
        // writes the result as an EXPLICIT point size, then the engine solves the
        // whole tree. That is the same split the design doc lists as open question
        // 10 ("two passes: intrinsic first, then solve").
        public function measureSelf():void
        {
            if (this.engineNode == null) return;
            var eng:LayoutEngine = this.app.engine;
            var s:Style = this.resolved;
            var autoW:Boolean = s.size == null || s.size.width == null || s.size.width.isAuto();
            var autoH:Boolean = s.size == null || s.size.height == null || s.size.height.isAuto();

            this.widget.measure(this);
        }

        // ---- pass 2: arrange (final rect already solved by the engine) ---
        public function arrangeSelf(px:Number, py:Number):void
        {
            var eng:LayoutEngine = this.app.engine;
            var out:Array = this.app.rectScratch;
            eng.layoutGet(this.engineNode, out);
            var x:Number = px + out[0];
            var y:Number = py + out[1];
            var w:Number = out[2];
            var h:Number = out[3];
            this.absX = x; this.absY = y; this.absW = w; this.absH = h;
            this.state.arrangedX = x; this.state.arrangedY = y;
            this.state.arrangedW = w; this.state.arrangedH = h;
            this.state.hitValid = 1;
            // absX/absY are ABSOLUTE (for tests and the AIR evidence dump), but the
            // backing is a child of the parent's backing, so its own x/y must be
            // the LOCAL offset the engine reported -- using the absolute value here
            // double-applies every ancestor offset.
            this.backing.x = out[0];
            this.backing.y = out[1];

            var s:Style = this.resolved;
            this.backing.visible = this.visible && s.visibility != "hidden";
            this.backing.alpha = isNaN(s.opacity) ? 1.0 : s.opacity;

            // The inner display objects are placed by the kind, which reads the
            // solved rect back through PaintKit (insetX/insetY/contentW/H).
            this.widget.arrange(this);
        }

        // ---- pass 3: paint ----------------------------------------------
        public function paintSelf():void
        {
            // Re-apply alpha on the PAINT side. `arrangeSelf` also writes it, but
            // a paint-only repaint (a dirty frame with no layout change) is the
            // common animation frame, and an alpha animated there would otherwise
            // never reach the display object. Idempotent with arrangeSelf.
            if (this.backing != null)
            {
                this.backing.alpha = isNaN(this.resolved.opacity) ? 1.0 : this.resolved.opacity;
            }
            this.widget.paint(this);
        }

        public function destroySubtree():void
        {
            // Drop any in-flight tweens for this subtree BEFORE the node's scratch
            // bag is nulled, so the animator's active list never holds a dead node.
            Anim.clear(this);
            for (var i:int = 0; i < this.children.length; i++)
            {
                this.children[i].destroySubtree();
            }
            this.children.length = 0;
            if (this.backing != null && this.parent != null && this.parent.backing != null)
            {
                if (this.backing.parent == this.parent.backing)
                {
                    this.parent.backing.removeChild(this.backing);
                }
            }
            this.backing = null;
            this.desc = null;
            this.extra = null;
            this.tf = null;
            this.shapeA = null;
            this.shapeB = null;
            this.app = null;
            this.parent = null;
        }

        public function token():int
        {
            return this.keyId >= 0 ? this.keyId : -(this.lastIndex + 1);
        }
    }
}