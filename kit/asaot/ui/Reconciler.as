// asaot.ui.Reconciler -- the KEYED diff that turns a fresh description tree into
// mutations of the retained UiNode tree (design doc section 1.3).
//
// The identity of a node relative to its parent is
//     (kind, key)       when an explicit key is present, else
//     (kind, siblingIndex)
// `kind` participates so a control at the same slot is never reused as a
// DIFFERENT control. This is our version of GPUI's `GlobalElementId`
// (asaotui/gpui-src/crates/gpui/src/element.rs:220): but GPUI hashes a path of
// `ElementId`s into a window-level state map every frame, whereas our identity is
// the parent/child relationship itself -- the retained pointer IS the identity,
// so nothing is hashed and no external map is consulted.
//
// KEY INTERNING: an explicit key (String or int) is mapped to a stable int the
// first time it is seen and compared as an int afterwards. That avoids a string
// compare (and any string building) in the match loop -- the discipline the
// `as_disp_key` leak in the compiler's history was about.
//
// DUPLICATE KEYS ARE A HARD ERROR: two siblings with the same key would silently
// make one node shadow the other (state would "stick" to the wrong row), so we
// throw instead of overwriting.
package asaot.ui
{
    import asaot.ui.style.StyleRefinement;

    import flash.display.DisplayObject;

    public class Reconciler
    {
        private var app:UiApp;
        private var keyIds:Object;     // keyToCaption -> int
        private var keySeq:int;

        public function Reconciler(app:UiApp):void
        {
            this.app = app;
            this.keyIds = {};
            this.keySeq = 0;
        }

        private function internKey(k:Object):int
        {
            var name:String;
            if (k is String) name = "s:" + String(k);
            else name = "i:" + String(int(k));
            var id:Object = this.keyIds[name];
            if (id == null)
            {
                this.keySeq = this.keySeq + 1;
                this.keyIds[name] = this.keySeq;
                return this.keySeq;
            }
            return int(id);
        }

        public function reconcile(old:UiNode, desc:Node, parent:UiNode):UiNode
        {
            this.app.reconcileVisits = this.app.reconcileVisits + 1;
            // View.memo returns the SAME explicitly marked immutable Node on a
            // hit. If the retained node still owns that object, neither its
            // payload nor any descendant description can have changed, so walking
            // the subtree would only repeat key interning, payload comparisons
            // and child scans for every component kind. Keep state and return.
            // The marker is essential: legacy probes/apps also retain ordinary
            // Nodes and mutate fields such as scroll offset in place; their same
            // object identity does NOT mean unchanged and must take the full path.
            // A stale style is the explicit exception: theme/inherited/safe-area
            // propagation marks the affected root AND its descendants stale, so
            // the full path still re-resolves them instead of hiding the change.
            if (old != null && desc.memoRoot && old.desc === desc && !old.lastStyleStale) return old;
            var n:UiNode;
            if (old == null || old.kind != desc.kind)
            {
                // kind changed (or no old node): destroy and rebuild, never reuse
                // a control's backing as a different control.
                if (old != null) this.destroyMounted(old);
                n = new UiNode(desc.kind, this.app);
                n.parent = parent;
                n.engineNode = this.app.engine.createNode(this.app.cfg);
                if (parent != null)
                {
                    parent.backing.addChild(n.backing);
                    this.app.engine.insertChild(parent.engineNode, n.engineNode, parent.children.length);
                }
                else if (this.app.stageContainer != null)
                {
                    this.app.stageContainer.addChild(n.backing);
                }
                n.dirty = Dirty.M_MEASURE | Dirty.M_ARRANGE | Dirty.M_PAINT;
                // A brand-new node carries its own bits, but the layout gate only
                // looks at the ROOT's bits -- without this climb the whole new
                // subtree would never be solved (see UiNode.markLayoutDirty).
                n.markLayoutDirty();
                n.lastStyleStale = true;
            }
            else
            {
                // ★ POINTER-LEVEL REUSE: hover/scroll/measure/focus all survive.
                n = old;
            }

            n.key = desc.key;
            n.keyId = desc.key != null ? this.internKey(desc.key) : -1;
            n.keyContext = desc.keyContext;

            var st:StyleRefinement = desc.style;
            if (n.lastStyle !== st || n.lastStyleStale)
            {
                n.lastStyle = st;
                n.resolveStyle();
            }

            n.applyPayload(desc);

            if (n.role == null)
            {
                throw new Error('asaot.ui: node kind "' + n.kind
                    + '" has no role; every Element must set role/ariaName (api-design section 4.3)');
            }

            this.reconcileChildren(n, desc);
            return n;
        }

        private function reconcileChildren(n:UiNode, desc:Node):void
        {
            var kids:Vector.<Node> = desc.children;
            var count:int = kids != null ? kids.length : 0;

            // ---- FAST PATH: same count, same tokens, same slots -----------
            // This is the overwhelmingly common describe: a value changed, so the
            // view returned a structurally identical tree. The general path below
            // does three O(children) things PER CHILD that the fast path can skip:
            // a linear `findChild` scan (O(n^2) for a column of keyed rows -- the
            // same shape as the duplicate-key scan fixed in 2026-10-27), a
            // `insertChild` per child (As3LayoutEngine.remove uses indexOf+splice,
            // so O(n) each => O(n^2)) and a `setChildIndex` per child (a display
            // list splice, also O(n)). Measured on probes/frame at 1000 rows:
            // reconcile was 8.3 ms of a 29 ms frame, and it did not depend on
            // WHICH row changed -- it was the re-placement itself.
            //
            // The tokens are compared, not just the indices, so a keyed reorder
            // can never slip through here: an unkeyed child's token is its slot,
            // a keyed child's is its interned key id.
            var i:int;
            if (n.children.length == count)
            {
                var positional:Boolean = true;
                for (i = 0; i < count; i++)
                {
                    var ftok:int = kids[i].key != null ? this.internKey(kids[i].key) : -(i + 1);
                    if (n.children[i].token() != ftok) { positional = false; break; }
                    var fb:DisplayObject = n.children[i].backing;
                    // A LIFTED child (an open popup) is not in this backing; the
                    // general path's slot counter is what re-seats it, so a
                    // displaced child disqualifies the fast path.
                    if (fb != null && fb.parent != n.backing) { positional = false; break; }
                }
                if (positional)
                {
                    // In place: no Vector allocation, no matched flags, no
                    // destroy sweep (every slot was matched by construction).
                    // A KIND CHANGE at a slot is a rebuild: `reconcile` then
                    // returns a NEW node, whose backing/engine node were APPENDED
                    // to the end of their lists -- so the order really did change
                    // even though the tokens did not, and the slot repair has to
                    // run after all.
                    var replaced:Boolean = false;
                    for (i = 0; i < count; i++)
                    {
                        var before:UiNode = n.children[i];
                        var nn:UiNode = this.reconcile(before, kids[i], n);
                        n.children[i] = nn;
                        if (nn != before) replaced = true;
                    }
                    if (replaced)
                    {
                        this.fixEngineOrder(n, n.children);
                        this.fixDisplayOrder(n, n.children);
                    }
                    return;
                }
            }

            // Reset the match flags on the CURRENT children (recursion-safe:
            // `matched` is a per-node field, not a shared scratch).
            for (i = 0; i < n.children.length; i++) n.children[i].matched = false;

            if (count == 0)
            {
                for (i = 0; i < n.children.length; i++) this.destroyMounted(n.children[i]);
                n.children.length = 0;
                return;
            }

            // Duplicate-key check. Index tokens are all negative and key ids are
            // all positive, so only two explicit keys can collide.
            //
            // THIS MUST STAY O(n). It used to be the obvious nested loop, which
            // cost n(n-1)/2 internings PER PARENT PER DESCRIBE -- measured at
            // 39.3ms of a 39.7ms frame for a single column of 300 keyed buttons
            // (probes/perf, 2026-10-27): 98% of the whole describe pass, spent
            // on a check that almost never fires. The interned id is already a
            // unique positive int, so a seen-set answers the same question in
            // one pass. The error and its text are unchanged.
            var seen:Object = {};
            for (i = 0; i < count; i++)
            {
                if (kids[i].key == null) continue;
                var seenId:int = this.internKey(kids[i].key);
                if (seen[seenId])
                {
                    throw new Error('asaot.ui: duplicate key "' + String(kids[i].key)
                        + '" under parent kind "' + n.kind + '" (api-design section 1.2)');
                }
                seen[seenId] = true;
            }

            var next:Vector.<UiNode> = new Vector.<UiNode>();
            // TOKEN -> NODE IN ONE PASS. `findChild` used to scan the current
            // children per described child, i.e. n(n+1)/2 token comparisons per
            // parent per describe -- invisible at 10 rows, 8 ms at 1000 (a keyed
            // list that reorders, a virtual list that shifts). Tokens are unique
            // per parent (duplicate keys throw just above, unkeyed tokens are
            // negative slots), so a map answers each lookup in one probe.
            var byToken:Object = {};
            for (i = 0; i < n.children.length; i++)
            {
                var oc0:UiNode = n.children[i];
                byToken[oc0.token()] = oc0;
            }
            for (i = 0; i < count; i++)
            {
                var child:Node = kids[i];
                var token:int = child.key != null ? this.internKey(child.key) : -(i + 1);
                var cand:Object = byToken[token];
                var hit:UiNode = cand != null ? UiNode(cand) : null;
                // The destroy sweep below trusts `matched`, and this is its only
                // writer now that the linear findChild is gone.
                if (hit != null) hit.matched = true;
                var c:UiNode = this.reconcile(hit, child, n);
                next.push(c);
            }

            // Anything still unmatched is gone from the new description.
            for (i = 0; i < n.children.length; i++)
            {
                var oldc:UiNode = n.children[i];
                if (!oldc.matched) this.destroyMounted(oldc);
            }

            // A reorder keeps every node but changes every position, so the parent
            // has to be re-solved. The comparison must happen BEFORE `n.children` is
            // replaced: assigning it makes the two arrays the same object, so the
            // check would compare an array with itself and always report "no
            // reorder" -- which is exactly what happened (CheckUi's "reorder moved
            // 'a' down" / "'b' up" went red: the nodes moved in the engine's child
            // list but nothing ever re-arranged them). It is computed here, next to
            // the destroy sweep that still needs the old array. A pure
            // style/payload re-describe reaches this point with the same nodes in
            // the same slots and costs one loop.
            // RE-PLACEMENT IS A STRUCTURE REPAIR, NOT A PER-FRAME RITUAL.
            // `insertChild` on As3LayoutEngine is remove(indexOf+splice)+splice and
            // `setChildIndex` is a display-list splice, so doing either for every
            // child every describe is O(n^2) and was the whole of the reconcile
            // cost at 1000 rows. They are only needed when the description's order
            // actually changed, or when a child is out of its parent's backing
            // (a lifted popup that came back, which applyLift re-appends at the
            // END of the display list).
            var reordered:Boolean = orderChanged(n, next);
            n.children = next;
            if (reordered)
            {
                n.markLayoutDirty();
                this.fixEngineOrder(n, next);
            }
            if (reordered || this.displayDisplaced(n, next)) this.fixDisplayOrder(n, next);
        }

        // Is any child absent from the parent's backing? `applyLift` re-attaches a
        // returning popup at the END of the display list, so the z-order has to be
        // repaired even when the description order did not change.
        private function displayDisplaced(n:UiNode, next:Vector.<UiNode>):Boolean
        {
            for (var i:int = 0; i < next.length; i++)
            {
                var b:DisplayObject = next[i].backing;
                if (b != null && b.parent != n.backing) return true;
            }
            return false;
        }

        private function orderChanged(n:UiNode, next:Vector.<UiNode>):Boolean
        {
            if (next.length != n.children.length) return true;
            for (var i:int = 0; i < next.length; i++)
            {
                if (next[i] != n.children[i]) return true;
            }
            return false;
        }

        // Put the engine's child list in the same order as the description. A
        // fresh node was inserted at a stale index and a keyed move changes the
        // slot, so we simply re-place every child at its final index (insertChild
        // removes from the old slot first). Structure changes only.
        private function fixEngineOrder(n:UiNode, next:Vector.<UiNode>):void
        {
            var eng:LayoutEngine = this.app.engine;
            for (var i:int = 0; i < next.length; i++)
            {
                if (next[i].engineNode != null) eng.insertChild(n.engineNode, next[i].engineNode, i);
            }
        }

        // Reorder the retained backings to match the description order. We move
        // existing display objects (addChildAt semantics, which already carries the
        // gc write barrier in the compiler) instead of rebuilding them.
        //
        // THE INDEX IS A SLOT COUNTER, NOT `base + <description index>`. A LIFTED child
        // (an open popup, see UiNode.lifted) has LEFT the backing -- it lives on the
        // stage container so it can out-stack its owner's later siblings -- but it still
        // holds its slot in the description. Counting description positions therefore
        // overshoots by one per lifted sibling, and an index >= numChildren is a
        // RangeError #2006 on AIR ("The supplied index is out of bounds."). That error
        // took down the whole reconcile of the frame, once per frame, the moment a
        // dropdown opened: select, combobox and datePicker showed a frozen page and a
        // console stream. The counter below only advances for children that ARE in the
        // backing, so the last one lands at most on numChildren-1 (one lower when
        // `aboveContent` occupies the top).
        //
        // This is also why no AOT probe saw it at the time: our runtime CLAMPED an
        // out-of-range index instead of throwing (asaotui/compiler-gaps.md G24), and a
        // clamped index happens to be the right place for the LAST child -- the visible
        // result was identical while the reference runtime threw. G24 was fixed in
        // v0.4.239 (an index past the end now raises RangeError #2006 on our builds too),
        // so this counter is not only right by construction: the runtime now GUARDS it.
        // tools/air-sweep.cjs stays the gate that runs the reference runtime.
        private function fixDisplayOrder(n:UiNode, next:Vector.<UiNode>):void
        {
            var slot:int = n.internalCount;
            for (var i:int = 0; i < next.length; i++)
            {
                var c:UiNode = next[i];
                // `lastIndex` stays the DESCRIPTION index: it is the identity token of
                // an unkeyed sibling (`UiNode.token`), not a display position.
                c.lastIndex = i;
                if (c.backing != null && c.backing.parent == n.backing)
                {
                    n.backing.setChildIndex(c.backing, slot);
                    slot = slot + 1;
                }
            }
        }

        // Tear a whole root down (the overlay root, when View.renderOverlay()
        // starts returning null). Same path as any other removal -- engine
        // detach, display detach, tween cancel -- just addressed from the root.
        public function destroyRoot(n:UiNode):void
        {
            // A ROOT has no parent NODE, so destroySubtree's "remove me from my
            // parent's backing" step never runs for it: the overlay host would stay
            // attached to the stage container -- invisible and empty, but above the
            // main tree -- for the rest of the session, one per teardown.
            // Detach the display object here, BEFORE destroySubtree nulls n.backing.
            var b:DisplayObject = n.backing;
            this.destroyMounted(n);
            if (b != null && b.parent != null) b.parent.removeChild(b);
        }

        private function destroyMounted(n:UiNode):void
        {
            // Detach this node (and its subtree) from the engine tree and the
            // display list; the objects themselves are simply dropped for the GC.
            this.destroyEngine(n);
            n.destroySubtree();
            // The siblings that stay behind shift into the gap, so their parent
            // needs a fresh solve (and the root needs to know about it).
            if (n.parent != null) n.parent.markLayoutDirty();
        }

        private function destroyEngine(n:UiNode):void
        {
            var eng:LayoutEngine = this.app.engine;
            for (var i:int = 0; i < n.children.length; i++) this.destroyEngine(n.children[i]);
            if (n.parent != null && n.parent.engineNode != null && n.engineNode != null)
            {
                eng.removeChild(n.parent.engineNode, n.engineNode);
            }
            if (n.engineNode != null) eng.destroyNode(n.engineNode);
            n.engineNode = null;
        }
    }
}