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

            // Reset the match flags on the CURRENT children (recursion-safe:
            // `matched` is a per-node field, not a shared scratch).
            var i:int;
            for (i = 0; i < n.children.length; i++) n.children[i].matched = false;

            if (count == 0)
            {
                for (i = 0; i < n.children.length; i++) this.destroyMounted(n.children[i]);
                n.children.length = 0;
                return;
            }

            // Duplicate-key check. Index tokens are all negative and key ids are
            // all positive, so only two explicit keys can collide.
            for (i = 0; i < count; i++)
            {
                if (kids[i].key == null) continue;
                for (var j:int = i + 1; j < count; j++)
                {
                    if (kids[j].key == null) continue;
                    if (this.internKey(kids[i].key) == this.internKey(kids[j].key))
                    {
                        throw new Error('asaot.ui: duplicate key "' + String(kids[i].key)
                            + '" under parent kind "' + n.kind + '" (api-design section 1.2)');
                    }
                }
            }

            var next:Vector.<UiNode> = new Vector.<UiNode>();
            for (i = 0; i < count; i++)
            {
                var child:Node = kids[i];
                var token:int = child.key != null ? this.internKey(child.key) : -(i + 1);
                var hit:UiNode = this.findChild(n, token);
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
            var reordered:Boolean = orderChanged(n, next);
            n.children = next;
            if (reordered) n.markLayoutDirty();
            this.fixEngineOrder(n, next);
            this.fixDisplayOrder(n, next);
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

        private function findChild(n:UiNode, token:int):UiNode
        {
            for (var i:int = 0; i < n.children.length; i++)
            {
                var c:UiNode = n.children[i];
                if (c.matched) continue;
                if (c.token() == token)
                {
                    c.matched = true;
                    return c;
                }
            }
            return null;
        }

        // Reorder the retained backings to match the description order. We move
        // existing display objects (addChildAt semantics, which already carries the
        // gc write barrier in the compiler) instead of rebuilding them.
        private function fixDisplayOrder(n:UiNode, next:Vector.<UiNode>):void
        {
            var base:int = n.internalCount;
            for (var i:int = 0; i < next.length; i++)
            {
                var c:UiNode = next[i];
                c.lastIndex = i;
                if (c.backing != null && c.backing.parent == n.backing)
                {
                    n.backing.setChildIndex(c.backing, base + i);
                }
            }
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