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
    import asaot.ui.style.BoxShadow;
    import asaot.ui.style.Corners;
    import asaot.ui.style.Edges;
    import asaot.ui.style.Fill;
    import asaot.ui.style.Length;
    import asaot.ui.style.LengthEdges;
    import asaot.ui.style.Size;
    import asaot.ui.style.Style;
    import asaot.ui.style.StyleRefinement;
    import asaot.ui.style.TextStyle;

    import asaot.ui.LayoutConstants;
    import asaot.ui.anim.Anim;

    import flash.display.DisplayObject;
    import flash.display.DisplayObjectContainer;
    import flash.display.Shape;
    import flash.display.Sprite;
    import flash.events.EventDispatcher;
    import flash.events.MouseEvent;
    import flash.filters.DropShadowFilter;
    import flash.text.TextField;

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
        // Attached listeners as flat (target, type, fn) triples -- see listen().
        public var wired:Array;
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
        // `extra` key holding the last APPLIED box-shadow stack (see applyShadow).
        private static const SHADOW_LAST:String = "shadowLast";

        // ---- control payload (mirrored from the description node) --------
        public var textContent:String;
        public var label:String;
        public var value:String;
        public var placeholder:String;
        public var password:Boolean;
        public var checked:Boolean;
        public var binding:Binding;
        // WRITTEN BY THE WIDGET, never mirrored from the description: the last
        // failed load's message ("Error #2035: ..."). An image whose `src` cannot be
        // read is not a blank box -- the author's `onError` gets the same text, and a
        // probe can read it back here. null while nothing has failed.
        public var loadError:String;
        // ARITY IS PART OF THE CONTRACT, and getting it wrong is NOT a silent no-op.
        //
        //   onClick()        -- no arguments. Every kind and every container calls it
        //                       like that, so an author closure must declare none.
        //   onCommit(v)      -- exactly one: the committed value (text) or the row.
        //   onChange(v)      -- exactly one: the NEW value (Boolean for
        //                       checkbox/radio/switch, 0..1 Number for slider, the
        //                       text for textField, the index/key for the selection
        //                       kinds -- those factories reuse this slot).
        //
        // AVM2 throws #1063 "Argument count mismatch" when a closure is called with
        // FEWER arguments than it declares (`function (v:Number)` called as `f()`),
        // and the frame guard then swallows it: the handler never runs, the model
        // never changes, and the only trace is a console line. That is exactly how
        // the docs' slider shipped broken -- the widget called `onChange()` and every
        // click on the page threw. Widgets therefore PASS the value even where it is
        // constant (a radio only ever reports `true`). Pin: tools/callback-arity.cjs +
        // probes/widgets/callback.
        public var onClick:Function;
        public var onCommit:Function;
        public var onChange:Function;
        // ---- right button / double click (mirrored from Element) ----------
        // Kept here as well as on the description because the listeners are
        // installed ONCE, at structure time, while the handlers live in a fresh
        // description every frame (see createBacking).
        public var onRightClick:Function;   // Function(stageX, stageY)
        public var onDoubleClick:Function;  // Function()
        // The key context this node contributes while it (or a child) holds the
        // focus -- matched by ActionRegistry's context predicates. Declared with the
        // other identity fields at the top of the class; mirrored from
        // Node.keyContext in applyPayload (the field existed since the first commit
        // and had no consumer until the keymap landed).
        //
        // -1 == "document order" (see UiApp.focusNext).
        public var tabIndex:int;
        public var role:String;
        public var ariaName:String;
        public var directionOverride:String;
        public var visible:Boolean;
        // 1 while a widget is HOLDING this node on screen for an exit animation.
        // It exists because `visible` is normally a MIRROR of `Element.visible`
        // (see applyPayload): a dialog that closes sets `visible: false` in the
        // description, and without this flag that mirror would hide the surface in
        // the same frame it closed -- which is the one-frame vanish the exit motion
        // exists to remove. Only the shell that owns an exit writes it.
        public var visibleHold:int;
        public var action:String;
        // Mirrored from Control.tabEnabled. The TAB RING IS BUILT IN UiApp, not by
        // the runtime's own `as_tab_scan`: that walk is display-list order over
        // every tabEnabled InteractiveObject, so it descends into an INVISIBLE
        // overlay (typed text would land in a closed dialog), it counts this node's
        // own TextField as a second stop, and it stops at 64 objects. Walking the
        // RETAINED tree instead is exact -- a node is a stop iff its own
        // `tabEnabled` is true, it is visible, and nothing above it is disabled.
        public var tabEnabled:Boolean;

        // ---- backing internals ------------------------------------------
        public var shapeA:Shape;
        public var shapeB:Shape;
        // A kind may build ONE display object that belongs ABOVE the UiNode
        // children (scrollView's bars, today the only user). `build()` sets it;
        // `internalCount` -- the base index display-order repairs start from --
        // then leaves it out, so content is ordered BEFORE it and the chrome stays
        // on top without needing a later repaint to raise it again.
        public var aboveContent:DisplayObject;
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

        // ---- floating layer escape (open dropdowns / popup lists) --------
        // An OPEN popup must win over everything the main tree paints after its
        // owner, and this engine deliberately has no z-index (overlay.as says so):
        // DISPLAY ORDER is the stacking order. A popup that is a child node of a
        // card therefore cannot rise above the card's later siblings -- which is
        // exactly what "the dropdown opens UNDER the widget below it" was.
        //
        // `lifted` re-parents just this node's backing onto the stage container and
        // positions it at its ABSOLUTE rect instead of the parent-relative one. The
        // node stays in the layout tree (measure/arrange keep running through the
        // real parent, so absX/absY stay exact) and stays in the description tree
        // (reconcile, keys, focus ring, WidgetKeys), so events, layout and state are
        // untouched -- only the rasterization order changes. It is inserted BELOW the
        // overlay tree's backing so a dialog still covers a dropdown.
        //
        // Cost: while lifted the node no longer inherits an ancestor's clip, alpha
        // or mouseEnabled. That is the point of a popup (a dropdown that escapes a
        // scrolling card must not be clipped), and it only ever applies while the
        // popup is open -- the closed state is byte-for-byte the old behaviour.
        public var lifted:Boolean;

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
            this.loadError = null;
            this.onClick = null;
            this.onCommit = null;
            this.onChange = null;
            this.role = null;
            this.ariaName = null;
            this.directionOverride = null;
            this.visible = true;
            this.visibleHold = 0;
            this.action = null;
            this.tabEnabled = false;
            this.tabIndex = -1;
            this.onRightClick = null;
            this.onDoubleClick = null;
            this.shapeA = null;
            this.shapeB = null;
            this.aboveContent = null;
            this.tf = null;
            this.absX = 0; this.absY = 0; this.absW = 0; this.absH = 0;
            this.matched = false;
            this.lastIndex = 0;
            this.internalCount = 0;
            this.lifted = false;
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
            // Content children are ordered from `internalCount` upward (see
            // Reconciler.fixDisplayOrder), i.e. ABOVE everything build() added --
            // right for a background, wrong for chrome that has to sit on top.
            // Counting such an object would put every content child over it, and
            // the chrome would only reappear when some later repaint happened to
            // raise it again (the scroll bars were buried exactly like that).
            if (this.aboveContent != null && this.aboveContent.parent == this.backing)
            {
                this.internalCount = this.internalCount - 1;
            }
            // Hover is NOT wired here, on purpose. G25 was fixed in v0.4.239, so roll
            // events DO arrive now -- and hover still stays in UiApp, derived from ONE
            // stage MOUSE_MOVE with the same pick test the click uses (see its "hover is
            // DERIVED" block). Two definitions of "under the pointer" is how a control
            // ends up lighting up and not being clickable. What stays here is what a
            // shared listener cannot express: press and click belong to the object under
            // the pointer.
            //
            // CLICK IS INSTALLED FOR EVERY KIND, unlike press: click is a property
            // of a display object (any element may carry a handler), while
            // `pressed` is a CONTROL visual that only some kinds paint. Gating the
            // click on wantsPress() is what made `box({ onClick: f })` dead --
            // a container is the one element whose click region is not its own
            // chrome. handleClick() is safe for every kind: it drops an inert node
            // first, then gives the widget first refusal, then runs the handler.
            if (this.widget.wantsPress())
            {
                this.listen(this.backing, MouseEvent.MOUSE_DOWN, function (e:MouseEvent):void { self.setPressed(1); });
                this.listen(this.backing, MouseEvent.MOUSE_UP, function (e:MouseEvent):void { self.setPressed(0); });
            }
            this.listen(this.backing, MouseEvent.CLICK, function (e:MouseEvent):void { self.handleClick(); });
            // RIGHT BUTTON. A normal (bubbling) listener on the backing: an event
            // aimed at a child or at this node's own TextField still arrives, which
            // is exactly how `box({ onClick })` already works -- and it is why an
            // ancestor receives the right-clicks of its rows.
            this.listen(this.backing, MouseEvent.RIGHT_MOUSE_DOWN,
                function (e:MouseEvent):void { self.handleRightClick(e); });
            // DOUBLE CLICK. The runtime only produces it when the HIT TARGET's own
            // `doubleClickEnabled` is true (emit.ts:26439), so the flag is set from
            // applyPayload the moment a description carries a handler.
            this.listen(this.backing, MouseEvent.DOUBLE_CLICK,
                function (e:MouseEvent):void { self.handleDoubleClick(); });
            // Hover needs to FIND this node from a hit target (which may be this
            // node's own TextField or a descendant's backing), so the app keeps
            // backing -> node. Registered last: a backing that never made it this
            // far must not be in the map.
            this.app.nodeBackingBuilt(this);
        }

        // ---- backing listeners (detachable BY CONSTRUCTION) ---------------
        // Every listener a node installs on its own display objects goes through here,
        // because `destroySubtree` has to be able to take it back off. An anonymous
        // closure cannot be removed by reference afterwards, and "a dead node still
        // receives events" is not hypothetical: AIR finishes the frame that removed a
        // display object BEFORE it recomputes which object the pointer is over, so the
        // object that WAS under the pointer gets its `mouseOut` one beat after the node
        // was torn down. Measured on adl 51.4.1 -- TypeError #1009 on every click that
        // tore down the control it was made on (accordion 1x, dialog 4x, drawer 3x,
        // menu 3x), at `UiNode/setHover` and at every widget handler that reads the
        // nulled scratch bag.
        //
        // The AOT could not see that class of bug while G25 was open (no roll events at
        // all); the guard predates the fix, `probes/lifecycle` pins it now, and a
        // per-object roll listener added later inherits the same protection by going
        // through this method.
        //
        // `target` is the backing for pointer events and the node's TextField for the
        // editing ones. STAGE listeners are deliberately NOT wired here: they belong to
        // the gesture that installed them and keep their explicit add/remove pair in
        // the widget's own WidgetTeardown.teardown.
        public function listen(target:EventDispatcher, type:String, fn:Function):void
        {
            if (target == null) return;
            target.addEventListener(type, fn);
            if (this.wired == null) this.wired = [];
            this.wired.push(target, type, fn);
        }

        private function releaseListeners():void
        {
            if (this.wired == null) return;
            for (var i:int = 0; i < this.wired.length; i += 3)
            {
                var t:EventDispatcher = this.wired[i] as EventDispatcher;
                if (t == null) continue;
                t.removeEventListener(String(this.wired[i + 1]), this.wired[i + 2] as Function);
            }
            this.wired.length = 0;
            this.wired = null;
        }

        // ---- transient state changes (paint-only, never a reflow) --------
        public function setHover(v:int):void
        {
            if (this.state.hover == v) return;
            this.state.hover = v;
            // A destroyed node cannot repaint, and `app` is the field
            // destroySubtree nulls first. The app clears its hover chain before
            // tearing a node down (UiApp.nodeBackingGone), so reaching this line
            // with a null app means something else handed us a dead node: drop the
            // state change instead of throwing #1009 inside a mouse move, where
            // the frame guard would swallow it into a console line.
            if (this.app == null) return;
            // Section 3.3: a hover DECORATES only; it must never reflow.
            this.app.markPaint(this);
        }

        public function setPressed(v:int):void
        {
            if (this.state.pressed == v) return;
            this.state.pressed = v;
            this.app.markPaint(this);
        }

        // Focus is library state, not display-list state (see tabEnabled above):
        // the ring is painted by PaintKit and the TAB order is a walk of THIS tree.
        public function setFocused(v:int):void
        {
            if (this.state.focused == v) return;
            this.state.focused = v;
            this.app.markPaint(this);
        }

        // Disabled is INHERITED: a disabled container makes its whole subtree
        // inert, which is the only reading of "disable this form" that does not
        // require every factory to copy the flag down.
        public function inert():Boolean
        {
            var n:UiNode = this;
            while (n != null)
            {
                if (n.state.disabled != 0) return true;
                n = n.parent;
            }
            return false;
        }

        public function handleClick():void
        {
            // Direct dispatch (a test, a programmatic click on a child) bypasses the
            // runtime's hit test, so the inert check belongs HERE and not only in
            // the pick walk: a disabled control must never run its handler.
            if (this.inert()) return;
            this.setPressed(0);
            if (this.widget.click(this)) return;
            if (this.onClick != null) this.onClick();
        }

        // The object that should take `stage.focus` (see WidgetFocus). Null for
        // every non-editable kind, which is what keeps a ring-only focus from
        // stealing the keyboard from a text field that another node owns.
        public function focusTarget():DisplayObject
        {
            if (this.widget is WidgetFocus) return WidgetFocus(this.widget).focusTarget(this);
            return null;
        }

        // ---- the two button channels the library used to ignore -------------
        //
        // RIGHT BUTTON. Dispatched by the runtime on the ORDINARY event timeline
        // (emit.ts:26457 -- the native menu, if any, comes up AFTER the dispatch),
        // so a handler that just flips a flag sees the same coordinates the popup
        // would. stageX/stageY are what a caller needs: the floating layer is laid
        // out in stage space, so handing the author local coordinates would force
        // every handler to convert them.
        public function handleRightClick(e:MouseEvent):void
        {
            if (this.inert()) return;
            var f:Function = this.onRightClick;
            if (f == null) return;
            f(e.stageX, e.stageY);
        }

        // DOUBLE CLICK. Zero arguments, exactly like onClick: the targeting rule is
        // "the object under the pointer", and a double-click handler that needs the
        // point can read it from the stage.
        public function handleDoubleClick():void
        {
            if (this.inert()) return;
            if (this.onDoubleClick != null) this.onDoubleClick();
        }

        private function applyDisabledAlpha():void
        {
            if (this.backing == null) return;
            var base:Number = isNaN(this.resolved.opacity) ? 1.0 : this.resolved.opacity;
            this.backing.alpha = this.state.disabled != 0 ? base * PaintKit.DISABLED_ALPHA : base;
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
            // A VISIBILITY FLIP MUST REACH THE DISPLAY OBJECT. `visible` is written
            // onto backing.visible by arrangeSelf, which only runs inside an arrange
            // sweep -- so a payload that changed nothing else (a dropdown reopening
            // with a label that already matched, say) left the node's `visible`
            // correct in the tree and the Sprite stale on screen. Opening worked the
            // first time (the subtree was new) and closing worked (the label changed
            // and forced a relayout); reopening did nothing. Raising the arrange bit
            // is the honest fix: it is also what makes a hidden subtree stop picking.
            var vis:Boolean = Element(desc).visible;
            if (this.visibleHold != 0) vis = true;
            if (vis != this.visible)
            {
                this.visible = vis;
                this.dirty |= Dirty.M_ARRANGE | Dirty.M_PAINT;
                this.markLayoutDirty();
            }

            // ---- interaction state (mirrored, never authored on the retained
            // node) -------------------------------------------------------
            // `tabEnabled` only exists on Control. The `is` test is on a library
            // class, so a plain Element (a box, a text) is simply not tabbable.
            var tab:Boolean = (desc is Control) ? Control(desc).tabEnabled : false;
            if (tab != this.tabEnabled) this.tabEnabled = tab;
            // tabIndex orders the Tab ring (UiApp.focusNext); -1 means "document
            // order", which is what every node without an explicit index uses.
            var ti:int = (desc is Control) ? Control(desc).tabIndex : -1;
            if (ti != this.tabIndex) this.tabIndex = ti;
            // `action` is generic too (UiApp dispatches it on Enter/Space). ButtonWidget
            // used to be the only writer, which is why a radio or a switch could not
            // name an action at all.
            var act:String = (desc is Control) ? Control(desc).action : null;
            if (act != this.action) this.action = act;

            // A disabled flip is a PAINT change (the alpha and the dropped
            // hover/press win) -- plus it has to reach the display object in the
            // same frame it flips, exactly like `visible` above: a disabled
            // control that still looks enabled for one frame is the bug the whole
            // feature exists to prevent.
            var dis:int = Element(desc).disabled ? 1 : 0;
            if (dis != this.state.disabled)
            {
                this.state.disabled = dis;
                this.dirty |= Dirty.M_ARRANGE | Dirty.M_PAINT;
                this.applyDisabledAlpha();
                if (dis != 0 && this.state.focused != 0)
                {
                    // A control that becomes inert cannot hold the keyboard.
                    this.setFocused(0);
                    if (this.app != null) this.app.dropFocus(this);
                }
            }

            // ONE PLACE for the generic click handler, so every kind honours
            // `opts.onClick` -- including a plain container, whose handler used to be
            // stored on the description and never copied (the docs index rows are
            // exactly that shape: full-width, left-aligned, no control chrome).
            // The kinds that own a click assign the SAME descriptor field in their
            // own payload below, so this line is a no-op for them.
            this.onClick = Element(desc).onClick;
            // SAME PLACE, SAME REASON for the other two button channels: the
            // listeners are permanent, the handlers are per-frame. A node whose
            // handler disappears stops responding on the next frame without
            // leaking a closure (the behaviour the whole `listen` design buys).
            this.onRightClick = Element(desc).onRightClick;
            this.onDoubleClick = Element(desc).onDoubleClick;
            // `doubleClickEnabled` is what the RUNTIME reads to decide whether the
            // second click becomes `doubleClick` at all, and it must be on the HIT
            // TARGET (an ancestor does not help -- measured on adl 51.4.1).
            if (this.backing != null)
                this.backing.doubleClickEnabled = this.onDoubleClick != null;
            // The context string this node contributes to a keymap predicate. A
            // plain field on the retained node: only the focus path reads it.
            this.keyContext = desc.keyContext;

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
            //
            // A GRADIENT is deliberately not animated: the animator only knows how to
            // interpolate one packed colour (`lerpArgb`), and re-deriving N stops per
            // frame would allocate. Passing NaN drops the tween, which is the honest
            // reading of "there is nothing here to interpolate" -- not a fallback to
            // the first stop, which would silently paint a solid fill.
            var toGrad:Boolean = this.resolved.background != null && this.resolved.background.ratios != null;
            var prevGrad:Boolean = this.previous.background != null && this.previous.background.ratios != null;
            var toBg:Number = (this.resolved.background != null && !toGrad) ? this.resolved.background.argb : NaN;
            var prevBg:Number = (this.previous.background != null && !prevGrad) ? this.previous.background.argb : NaN;
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

            // textColor: the inherited text colour. A kind whose theme sets none
            // (a bare box) has NaN here, and retargeting to NaN DROPS any tween --
            // which is the honest reading of "there is no target".
            var toTc:Number = this.resolved.text.color;
            var curTc:Number = Anim.value(this, Anim.FIELD_TEXT, this.previous.text.color);
            if (active || curTc != toTc)
            {
                Anim.retarget(this, Anim.FIELD_TEXT, curTc, toTc, ms, ease);
            }

            // cornerRadius: UNIFORM radii only (Anim's header explains why a
            // non-uniform set does not animate: the box drawer honours topLeft).
            var toR:Number = uniformRadius(this.resolved.cornerRadii);
            var curR:Number = Anim.value(this, Anim.FIELD_RADIUS, uniformRadius(this.previous.cornerRadii));
            if (active || curR != toR)
            {
                Anim.retarget(this, Anim.FIELD_RADIUS, curR, toR, ms, ease);
            }

            // ---- layout fields (see Anim's header) ---------------------
            // Sizes animate only as POINT lengths; padding and gap animate as
            // numbers. An unset side / a percent length resolves to NaN, which
            // retarget() reads as "drop the tween and snap" -- never a made-up
            // interpolation between `auto` and a number.
            retargetLen(Anim.FIELD_WIDTH, true, ms, ease, active);
            retargetLen(Anim.FIELD_HEIGHT, false, ms, ease, active);
            retargetPad(Anim.FIELD_PAD_T, 0, ms, ease, active);
            retargetPad(Anim.FIELD_PAD_R, 1, ms, ease, active);
            retargetPad(Anim.FIELD_PAD_B, 2, ms, ease, active);
            retargetPad(Anim.FIELD_PAD_L, 3, ms, ease, active);
            retargetNum(Anim.FIELD_GAP_X, this.resolved.gapX, this.previous.gapX, ms, ease, active);
            retargetNum(Anim.FIELD_GAP_Y, this.resolved.gapY, this.previous.gapY, ms, ease, active);
        }

        // Uniform radius, or NaN when the corners differ (= "not animatable").
        private function uniformRadius(c:Corners):Number
        {
            if (c == null) return NaN;
            if (isNaN(c.topLeft)) return NaN;
            if (c.topLeft == c.topRight && c.topLeft == c.bottomRight && c.topLeft == c.bottomLeft)
            {
                return c.topLeft;
            }
            return NaN;
        }

        private function retargetLen(field:String, width:Boolean, ms:Number, ease:String,
                                     active:Boolean):void
        {
            retargetNum(field, pointValue(this.resolved.size, width),
                pointValue(this.previous.size, width), ms, ease, active);
        }

        private function pointValue(sz:Size, width:Boolean):Number
        {
            if (sz == null) return NaN;
            var l:Length = width ? sz.width : sz.height;
            if (l == null || l.unit != Length.UNIT_POINT) return NaN;
            return l.value;
        }

        private function retargetPad(field:String, side:int, ms:Number, ease:String, active:Boolean):void
        {
            var e:Edges = this.resolved.padding;
            var p:Edges = this.previous.padding;
            var to:Number = NaN;
            var prev:Number = NaN;
            if (e != null) to = side == 0 ? e.top : (side == 1 ? e.right : (side == 2 ? e.bottom : e.left));
            if (p != null) prev = side == 0 ? p.top : (side == 1 ? p.right : (side == 2 ? p.bottom : p.left));
            retargetNum(field, to, prev, ms, ease, active);
        }

        private function retargetNum(field:String, to:Number, prev:Number, ms:Number,
                                     ease:String, active:Boolean):void
        {
            var cur:Number = Anim.value(this, field, prev);
            if (active || cur != to) Anim.retarget(this, field, cur, to, ms, ease);
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
            // backing is normally a child of the parent's backing, so its own x/y
            // must be the LOCAL offset the engine reported -- using the absolute
            // value here double-applies every ancestor offset.
            this.backing.x = out[0];
            this.backing.y = out[1];
            this.applyLift();

            var s:Style = this.resolved;
            this.backing.visible = this.visible && s.visibility != "hidden";
            this.backing.alpha = isNaN(s.opacity) ? 1.0 : s.opacity;
            if (this.state.disabled != 0) this.backing.alpha = this.backing.alpha * PaintKit.DISABLED_ALPHA;

            // The inner display objects are placed by the kind, which reads the
            // solved rect back through PaintKit (insetX/insetY/contentW/H).
            this.widget.arrange(this);
        }

        // Move the backing between the parent's backing (normal) and the stage
        // container (lifted), and give it the x/y that space needs. Idempotent;
        // runs at the end of arrange AND at the start of paint, because a lift
        // usually flips in a descriptor payload -- a paint-only frame that never
        // re-arranges still has to move the display object this frame.
        private function applyLift():void
        {
            if (this.backing == null || this.app == null) return;
            var host:DisplayObjectContainer = this.app.stageContainer;
            if (!this.lifted)
            {
                // Back to the ordinary parent-relative slot. Nothing to do in the
                // steady state; a node that was lifted last frame is re-attached at
                // the END of the parent's display list, which the reconciler's
                // fixDisplayOrder corrects on the next describe.
                if (this.parent != null && this.parent.backing != null
                    && this.backing.parent != this.parent.backing)
                {
                    this.parent.backing.addChild(this.backing);
                    this.backing.x = this.absX - this.parent.absX;
                    this.backing.y = this.absY - this.parent.absY;
                }
                return;
            }
            if (host == null) return;
            if (this.backing.parent != host) host.addChild(this.backing);
            // Stay UNDER the overlay tree: a dialog must still cover a dropdown.
            var ov:DisplayObject = this.app.overlayDisplay();
            if (ov != null && ov != this.backing && ov.parent == host)
            {
                var iOv:int = host.getChildIndex(ov);
                if (host.getChildIndex(this.backing) > iOv) host.setChildIndex(this.backing, iOv);
            }
            this.backing.x = this.absX;
            this.backing.y = this.absY;
        }

        // ---- pass 3: paint ----------------------------------------------
        public function paintSelf():void
        {
            // A paint-only frame does not re-arrange, so this is where a lift that
            // flipped in a descriptor payload this frame actually takes effect.
            this.applyLift();
            // Box shadow is a property of the SURFACE, not of the drawing, so it is
            // re-applied on every paint (idempotent when unchanged) rather than on
            // every layout -- a paint-only frame is the common one.
            this.applyShadow();
            // Re-apply alpha on the PAINT side. `arrangeSelf` also writes it, but
            // a paint-only repaint (a dirty frame with no layout change) is the
            // common animation frame, and an alpha animated there would otherwise
            // never reach the display object. Idempotent with arrangeSelf.
            if (this.backing != null)
            {
                this.backing.alpha = isNaN(this.resolved.opacity) ? 1.0 : this.resolved.opacity;
                if (this.state.disabled != 0) this.backing.alpha = this.backing.alpha * PaintKit.DISABLED_ALPHA;
            }
            this.widget.paint(this);
        }

        // ---- pass 3b: the box shadow -----------------------------------
        // The resolved shadow STACK lands on the background shape's `filters[]`.
        //
        // WHY NOT THE BACKING: a filter on `backing` shades its whole subtree --
        // the label, the icons, every child -- which is a drop shadow on the text,
        // not on the box. Widgets that own a background shape (the overwhelming
        // majority, see `shapeA`) therefore shadow that shape alone. A node with no
        // background shape but a text field is a text-only kind (text/label) and the
        // filter goes on the field: that IS a text shadow, and it is what a box
        // shadow means for a node with no box. A node with neither THROWS rather
        // than dropping the shadow on the floor.
        //
        // Idempotent: the applied stack is remembered in `extra` and compared BY
        // VALUE (a re-describe parses a fresh array every time, so identity would
        // rebuild the filter list every frame).
        public function applyShadow():void
        {
            if (this.extra == null) return;
            var want:Array = this.resolved.boxShadow;
            var last:Array = null;
            if (this.extra[SHADOW_LAST] != null) last = this.extra[SHADOW_LAST] as Array;
            var target:DisplayObject = this.shapeA != null ? this.shapeA
                                                    : (this.tf != null ? this.tf : null);
            if (want == null || want.length == 0)
            {
                if (last != null && target != null)
                {
                    target.filters = [];
                    this.extra[SHADOW_LAST] = null;
                }
                return;
            }
            if (target == null)
            {
                throw new Error("asaot.ui: boxShadow needs a background shape or a text field on kind \""
                    + this.kind + "\" (it has neither, so the shadow would be invisible)");
            }
            if (Style.shadowsEqual(last, want)) return;
            var list:Array = [];
            for (var i:int = 0; i < want.length; i++)
            {
                var b:BoxShadow = BoxShadow(want[i]);
                // distance/angle is coarser than x/y ONLY in absolute terms: atan2
                // keeps the quadrant, so (0,-2) and (0,2) stay different.
                var dist:Number = Math.sqrt(b.offsetX * b.offsetX + b.offsetY * b.offsetY);
                var ang:Number = Math.atan2(b.offsetY, b.offsetX) * 180.0 / Math.PI;
                list.push(new DropShadowFilter(dist, ang, b.color, b.alpha, b.blur, b.blur,
                    1.0, 1, false, false, false));
            }
            target.filters = list;
            this.extra[SHADOW_LAST] = want;
        }

        public function destroySubtree():void
        {
            // Stop listening FIRST. Everything below assumes nothing else will call
            // into this node; AIR can still deliver a roll-out to a display object it
            // removed (see listen()).
            this.releaseListeners();
            // …and leave the pointer registry, which is the OTHER way an event can
            // still reach this node: the app holds backing -> node, so a stale entry
            // keeps the whole node alive and lets the next mouse move paint a dead
            // node (see UiApp.nodeBackingGone).
            if (this.app != null) this.app.nodeBackingGone(this);
            // Drop any in-flight tweens for this subtree BEFORE the node's scratch
            // bag is nulled, so the animator's active list never holds a dead node.
            Anim.clear(this);
            // A kind that attached something OUTSIDE the node -- a stage listener, a
            // timer -- releases it here, while extra/app/backing are still readable.
            // (Without this a destroyed menu kept its stage CLICK listener and the
            // next click in the window threw #1009 on the nulled scratch bag.)
            if (this.widget is WidgetTeardown) WidgetTeardown(this.widget).teardown(this);
            for (var i:int = 0; i < this.children.length; i++)
            {
                this.children[i].destroySubtree();
            }
            this.children.length = 0;
            if (this.backing != null && this.backing.parent != null)
            {
                // Unconditional: a LIFTED node's parent is the stage container, not
                // the parent node's backing, and leaving it there would keep a dead
                // popup on screen forever (the old `parent.backing` test skipped it).
                DisplayObjectContainer(this.backing.parent).removeChild(this.backing);
            }
            this.backing = null;
            this.desc = null;
            this.extra = null;
            this.tf = null;
            this.shapeA = null;
            this.shapeB = null;
            this.aboveContent = null;
            this.app = null;
            this.parent = null;
        }

        public function token():int
        {
            return this.keyId >= 0 ? this.keyId : -(this.lastIndex + 1);
        }
    }
}