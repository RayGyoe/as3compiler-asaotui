// asaot.ui.as3.As3LayoutEngine -- a PURE-AS3 implementation of the layout seam.
//
// SCOPE: a deliberately small flexbox SUBSET, INCREMENTALLY grown. It started
// as "enough for the U1 acceptance cases" (u1-prototype/check-layout.md
// section 3) and now also covers the P1..P8 feature set (see seam/README.md
// section 4 for the exact, item-by-item gap list -- it is kept in lock-step
// with what this file really does).
//
// Implemented:
//   * flex-direction: row / column AND the reverse variants
//   * explicit width / height as points or percent (percent basis = the
//     PARENT'S CONTENT BOX)
//   * padding (point / percent), border (point), gap (point / percent) with
//     the row-gap / column-gap split preserved
//   * border-box (default) and content-box
//   * setFlex grow / shrink / basis (point / percent / explicit 0)
//   * setMinMax point / percent, clamped onto the final size after the flex
//   * justify-content: flex-start / center / flex-end / space-between /
//     space-around / space-evenly
//   * align-items / align-self: flex-start / center / flex-end / stretch
//     (auto = inherit the parent's align-items)
//   * align-content: flex-start / center / flex-end / space-between /
//     space-around / stretch
//   * flex-wrap: nowrap / wrap / wrap-reverse
//   * margin (point / percent), all edges incl. START / END
//   * position-type relative / absolute + inset (point / percent)
//   * overflow (stored only; clipping happens in the painter)
//   * direction LTR / RTL + EDGE_START / EDGE_END
//
// EVERYTHING ELSE throws `new Error('... 未实现')`; the full gap list is in
// `seam/README.md`. This is NOT a home-grown flexbox: the reference for the
// numbers is Yoga through NativeLayoutEngine, and the two engines are kept in
// step by differential testing (seam/README.md -> "差分测试",
// diff-check/spec/cases.txt). Where Yoga's behaviour is surprising, the
// surprise is written down here rather than "fixed".
//
// AS3-vs-Yoga semantics worth stating explicitly (measured, not guessed):
//   * Explicit width/height are BORDER-BOX (Yoga's default, the OPPOSITE of
//     CSS content-box). A percent resolves against the PARENT'S CONTENT BOX
//     (parent size minus its padding AND border), case d.
//   * ALL percentages of padding / margin / gap resolve on the containing
//     block's WIDTH -- even vertical padding/margin (CSS 8.4). An inset is the
//     exception: a horizontal inset resolves on the owner WIDTH and a vertical
//     inset on the owner HEIGHT (Node::setPosition).
//   * A child's origin is the parent's border + padding origin.
//   * gap is added ONLY between adjacent items (never at the ends), and a row
//     container uses column-gap on its main axis while a column container uses
//     row-gap.
//   * Justify::Start / Justify::End are NO-OPS in Yoga's switch (they behave
//     like flex-start); Align::Start / Align::End are "not yet implemented"
//     for children. We do not accept them.
//   * Align::Baseline in a COLUMN container is downgraded to FlexStart
//     (resolveChildAlignment); in a row container it would need real text
//     baselines, so it still throws.
//   * web defaults set exactly TWO style defaults: flexDirection = Row and
//     alignContent = Stretch (Node::useWebDefaults); everything else keeps
//     Yoga's own default (alignItems = stretch, alignSelf = auto,
//     justifyContent = flex-start, flexWrap = nowrap, position = relative,
//     flexShrink = 1, flexGrow = 0).
//   * RTL flips row<->row-reverse (resolveDirection) and makes a COLUMN
//     container's cross axis row-reverse (resolveCrossDirection).
//   * wrap-reverse does not re-run the algorithm: it computes the layout as
//     usual and then mirrors every in-flow child along the cross axis.
package asaot.ui.as3
{
    import asaot.ui.LayoutEngine;
    import asaot.ui.LayoutConstants;

    public class As3LayoutEngine implements LayoutEngine
    {
        private var pointScale:Number = 0;
        private var useWebDefaults:Boolean = false;

        public function As3LayoutEngine() { }

        // ---- Config: <-> as_ui_yg_config_new / as_ui_yg_config_free --------

        public function createConfig(pointScale:Number, useWebDefaults:Boolean):Object
        {
            this.pointScale = pointScale;
            this.useWebDefaults = useWebDefaults;
            return { pointScale: pointScale, useWebDefaults: useWebDefaults };
        }

        public function destroyConfig(cfg:Object):void
        {
            // Nothing to release -- the AS3 objects are GC-managed.
        }

        // ---- Node lifecycle: <-> as_ui_yg_node_new / _free / _free_recursive /
        //      _insert / _remove ---------------------------------------------

        public function createNode(cfg:Object):Object
        {
            var n:As3LayoutNode = new As3LayoutNode();
            // Style defaults come from the CONFIG, not from a constant: this is
            // the AS3 counterpart of YGNodeNewWithConfig applying the config's
            // style defaults (YGNode's useWebDefaults() step). Reading the flag
            // off `cfg` here is deliberate -- a node made from a non-web config
            // must default to column even in the same engine instance.
            //
            // useWebDefaults touches EXACTLY TWO properties (Node.h): the flex
            // direction (row) and align-content (stretch). In particular
            // align-items stays stretch and flex-shrink stays 1 in BOTH modes.
            var web:Boolean = (cfg != null) && Boolean(cfg.useWebDefaults);
            n.flexDirection = web ? LayoutConstants.FLEX_DIR_ROW : LayoutConstants.FLEX_DIR_COLUMN;
            n.alignContent = web ? LayoutConstants.ALIGN_STRETCH : LayoutConstants.ALIGN_FLEX_START;
            return n;
        }

        public function destroyNode(node:Object):void
        {
            if (node == null) return;
            var n:As3LayoutNode = As3LayoutNode(node);
            if (n.parent != null) removeChild(n.parent, n);
        }

        public function destroyNodeRecursive(node:Object):void
        {
            if (node == null) return;
            var n:As3LayoutNode = As3LayoutNode(node);
            var i:int = n.children.length - 1;
            while (i >= 0) { destroyNodeRecursive(n.children[i]); i--; }
            destroyNode(n);
        }

        public function insertChild(parent:Object, child:Object, index:int):void
        {
            if (parent == null || child == null) return;
            var p:As3LayoutNode = As3LayoutNode(parent);
            var c:As3LayoutNode = As3LayoutNode(child);
            if (c.parent != null) removeChild(c.parent, c);
            if (index < 0) index = 0;
            if (index > p.children.length) index = p.children.length;
            p.children.splice(index, 0, c);
            c.parent = p;
        }

        public function removeChild(parent:Object, child:Object):void
        {
            if (parent == null || child == null) return;
            var p:As3LayoutNode = As3LayoutNode(parent);
            var c:As3LayoutNode = As3LayoutNode(child);
            var i:int = p.children.indexOf(c);
            if (i >= 0) { p.children.splice(i, 1); c.parent = null; }
        }

        // ---- Style setters -------------------------------------------------

        // <-> as_ui_yg_set_flex_direction. All four values.
        public function setFlexDirection(node:Object, direction:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setFlexDirection');
            if (direction != LayoutConstants.FLEX_DIR_ROW
                && direction != LayoutConstants.FLEX_DIR_COLUMN
                && direction != LayoutConstants.FLEX_DIR_ROW_REVERSE
                && direction != LayoutConstants.FLEX_DIR_COLUMN_REVERSE)
            {
                throw new Error('As3LayoutEngine.setFlexDirection: 非法 flex-direction=' + direction);
            }
            n.flexDirection = direction;
        }

        // <-> as_ui_yg_set_flex_wrap.
        public function setFlexWrap(node:Object, wrap:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setFlexWrap');
            if (wrap != LayoutConstants.WRAP_NO_WRAP
                && wrap != LayoutConstants.WRAP_WRAP
                && wrap != LayoutConstants.WRAP_WRAP_REVERSE)
            {
                throw new Error('As3LayoutEngine.setFlexWrap: 非法 flex-wrap=' + wrap);
            }
            n.flexWrap = wrap;
        }

        // <-> as_ui_yg_set_justify. The six values Yoga's justifyMainAxis
        // actually implements. Justify::Start / End / Auto / Stretch are
        // no-ops/aliases in Yoga (they look like flex-start) and are rejected
        // here instead of silently aliasing.
        public function setJustifyContent(node:Object, justify:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setJustifyContent');
            if (justify != LayoutConstants.JUSTIFY_FLEX_START
                && justify != LayoutConstants.JUSTIFY_CENTER
                && justify != LayoutConstants.JUSTIFY_FLEX_END
                && justify != LayoutConstants.JUSTIFY_SPACE_BETWEEN
                && justify != LayoutConstants.JUSTIFY_SPACE_AROUND
                && justify != LayoutConstants.JUSTIFY_SPACE_EVENLY)
            {
                throw new Error('As3LayoutEngine.setJustifyContent: 未实现 justify=' + justify
                    + '（子集仅 flex-start/center/flex-end/space-between/space-around/space-evenly）');
            }
            n.justifyContent = justify;
        }

        // <-> as_ui_yg_set_align_items.
        public function setAlignItems(node:Object, align:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setAlignItems');
            requireChildAlign(align, 'setAlignItems');
            n.alignItems = align;
        }

        // <-> as_ui_yg_set_align_self. AUTO means "inherit the parent's
        // align-items" (resolveChildAlignment), which is the default.
        public function setAlignSelf(node:Object, align:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setAlignSelf');
            if (align != LayoutConstants.ALIGN_AUTO)
            {
                requireChildAlign(align, 'setAlignSelf');
            }
            n.alignSelf = align;
        }

        // <-> as_ui_yg_set_align_content. Yoga's STEP 8 implements flex-start /
        // flex-end / center / stretch / space-around / space-evenly /
        // space-between; Start/End/Auto/Baseline are no-ops there.
        public function setAlignContent(node:Object, align:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setAlignContent');
            if (align != LayoutConstants.ALIGN_FLEX_START
                && align != LayoutConstants.ALIGN_CENTER
                && align != LayoutConstants.ALIGN_FLEX_END
                && align != LayoutConstants.ALIGN_STRETCH
                && align != LayoutConstants.ALIGN_SPACE_BETWEEN
                && align != LayoutConstants.ALIGN_SPACE_AROUND)
            {
                throw new Error('As3LayoutEngine.setAlignContent: 未实现 align-content=' + align
                    + '（子集仅 flex-start/center/flex-end/stretch/space-between/space-around）');
            }
            n.alignContent = align;
        }

        // <-> as_ui_yg_set_flex(grow, shrink, basis, basis_unit). An explicit 0
        // basis (basis_unit == UNIT_UNDEFINED) is the `flex: 1` case: the item
        // contributes 0 to the base and grow/shrink distribute the whole main
        // axis (case c).
        public function setFlex(node:Object, grow:Number, shrink:Number, basis:Number, basisUnit:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setFlex');
            if (basisUnit != LayoutConstants.UNIT_POINT
                && basisUnit != LayoutConstants.UNIT_PERCENT
                && basisUnit != LayoutConstants.UNIT_UNDEFINED)
            {
                throw new Error('As3LayoutEngine.setFlex: 未实现 basisUnit=' + basisUnit
                    + '（子集仅 point/percent/undefined）');
            }
            n.hasFlex = true;
            n.flexGrow = grow;
            n.flexShrink = shrink;
            n.flexBasisValue = basis;
            n.flexBasisUnit = basisUnit;
        }

        // <-> as_ui_yg_set_size. Subset: point / percent / undefined.
        public function setSize(node:Object, axis:int, value:Number, unit:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setSize');
            if (unit != LayoutConstants.UNIT_POINT
                && unit != LayoutConstants.UNIT_PERCENT
                && unit != LayoutConstants.UNIT_UNDEFINED)
            {
                throw new Error('As3LayoutEngine.setSize: 未实现 unit=' + unit
                    + '（子集仅 point/percent/undefined）');
            }
            if (axis == LayoutConstants.AXIS_WIDTH) { n.widthValue = value; n.widthUnit = unit; }
            else if (axis == LayoutConstants.AXIS_HEIGHT) { n.heightValue = value; n.heightUnit = unit; }
            else throw new Error('As3LayoutEngine.setSize: 非法 axis=' + axis);
        }

        // <-> as_ui_yg_set_minmax(axis, is_max, value, unit). Subset: point /
        // percent. UNIT_UNDEFINED clears it. min/max clamp the FINAL size, after
        // the flex solve (cases e1/e2).
        public function setMinMax(node:Object, axis:int, isMax:Boolean, value:Number, unit:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setMinMax');
            if (unit != LayoutConstants.UNIT_POINT
                && unit != LayoutConstants.UNIT_PERCENT
                && unit != LayoutConstants.UNIT_UNDEFINED)
            {
                throw new Error('As3LayoutEngine.setMinMax: 未实现 unit=' + unit
                    + '（子集仅 point/percent/undefined）');
            }
            if (axis == LayoutConstants.AXIS_WIDTH)
            {
                if (isMax) { n.maxWidthValue = value; n.maxWidthUnit = unit; }
                else { n.minWidthValue = value; n.minWidthUnit = unit; }
            }
            else if (axis == LayoutConstants.AXIS_HEIGHT)
            {
                if (isMax) { n.maxHeightValue = value; n.maxHeightUnit = unit; }
                else { n.minHeightValue = value; n.minHeightUnit = unit; }
            }
            else throw new Error('As3LayoutEngine.setMinMax: 非法 axis=' + axis);
        }

        // <-> as_ui_yg_set_margin(edge, value, unit). Point / percent. Percent
        // resolves on the containing block's WIDTH for every edge (CSS 8.4,
        // Style::computeMarginForAxis hardcodes LTR and takes widthSize).
        public function setMargin(node:Object, edge:int, value:Number, unit:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setMargin');
            if (unit != LayoutConstants.UNIT_POINT
                && unit != LayoutConstants.UNIT_PERCENT
                && unit != LayoutConstants.UNIT_UNDEFINED)
            {
                throw new Error('As3LayoutEngine.setMargin: 未实现 unit=' + unit
                    + '（子集仅 point/percent/undefined；auto margin 未实现）');
            }
            setEdgeSlots(n.marginV, n.marginU, edge, value, unit, 'setMargin');
        }

        // <-> as_ui_yg_set_padding(edge, value, unit). Point / percent.
        public function setPadding(node:Object, edge:int, value:Number, unit:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setPadding');
            if (unit != LayoutConstants.UNIT_POINT && unit != LayoutConstants.UNIT_PERCENT)
            {
                throw new Error('As3LayoutEngine.setPadding: 未实现 unit=' + unit
                    + '（子集 padding 仅 point/percent）');
            }
            setEdgeSlots(n.padV, n.padU, edge, value, unit, 'setPadding');
        }

        // <-> as_ui_yg_set_border(edge, value). Points only, per edge. Border is
        // added INSIDE the border-box and subtracted from the content box, so it
        // shifts a child's origin (case d: origin = 10+20 = 30).
        public function setBorder(node:Object, edge:int, value:Number):void
        {
            var n:As3LayoutNode = requireNode(node, 'setBorder');
            setEdgeSlots(n.borderV, n.borderU, edge, value, LayoutConstants.UNIT_POINT, 'setBorder');
        }

        // <-> as_ui_yg_set_gap(gutter, value, unit). Point / percent. The
        // row-gap (vertical) and column-gap (horizontal) are stored SEPARATELY:
        // a row container spaces children by column-gap, a column container by
        // row-gap. Collapsing them into one value is exactly what breaks case b.
        // GUTTER_ALL sets both (Style::setGap).
        public function setGap(node:Object, gutter:int, value:Number, unit:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setGap');
            if (unit != LayoutConstants.UNIT_POINT && unit != LayoutConstants.UNIT_PERCENT)
            {
                throw new Error('As3LayoutEngine.setGap: 未实现 unit=' + unit + '（子集 gap 仅 point/percent）');
            }
            if (gutter == LayoutConstants.GUTTER_ROW || gutter == LayoutConstants.GUTTER_ALL)
            {
                n.gapV[LayoutConstants.GUTTER_ROW] = value;
                n.gapU[LayoutConstants.GUTTER_ROW] = unit;
            }
            if (gutter == LayoutConstants.GUTTER_COLUMN || gutter == LayoutConstants.GUTTER_ALL)
            {
                n.gapV[LayoutConstants.GUTTER_COLUMN] = value;
                n.gapU[LayoutConstants.GUTTER_COLUMN] = unit;
            }
        }

        // <-> as_ui_yg_set_position(edge, value, unit): the INSET. Point /
        // percent. Meaningless until position-type is absolute, but a relative
        // node also shifts by (start ? start : -end) -- Node::relativePosition.
        public function setPosition(node:Object, edge:int, value:Number, unit:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setPosition');
            if (unit != LayoutConstants.UNIT_POINT
                && unit != LayoutConstants.UNIT_PERCENT
                && unit != LayoutConstants.UNIT_UNDEFINED)
            {
                throw new Error('As3LayoutEngine.setPosition: 未实现 unit=' + unit
                    + '（子集仅 point/percent/undefined；auto inset 未实现）');
            }
            setEdgeSlots(n.insetV, n.insetU, edge, value, unit, 'setPosition');
        }

        // <-> as_ui_yg_set_position_type. RELATIVE (default) and ABSOLUTE are
        // implemented; STATIC is rejected (it has its own containing-block
        // subtleties in layoutAbsoluteDescendants that the subset does not do).
        public function setPositionType(node:Object, positionType:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setPositionType');
            if (positionType != LayoutConstants.POSITION_RELATIVE
                && positionType != LayoutConstants.POSITION_ABSOLUTE)
            {
                throw new Error('As3LayoutEngine.setPositionType: 未实现 position=' + positionType
                    + '（STATIC 需 containing-block 推演，见 seam/README.md 缺口）');
            }
            n.positionType = positionType;
        }

        // <-> as_ui_yg_set_box_sizing. Border-box is the engine default (Yoga's
        // default, opposite of CSS); content-box makes an explicit width/height
        // mean the content size, so padding+border are ADDED on top.
        public function setBoxSizing(node:Object, boxSizing:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setBoxSizing');
            if (boxSizing != LayoutConstants.BOX_SIZING_BORDER_BOX
                && boxSizing != LayoutConstants.BOX_SIZING_CONTENT_BOX)
            {
                throw new Error('As3LayoutEngine.setBoxSizing: 非法 boxSizing=' + boxSizing);
            }
            n.boxSizing = boxSizing;
        }

        // <-> as_ui_yg_set_overflow. Stored only: overflow does not change any
        // rectangle in Yoga either -- it is a clipping hint for the painter
        // (see seam/README.md). Keeping the value means a future painter can
        // read it without re-opening this seam.
        public function setOverflow(node:Object, overflow:int):void
        {
            var n:As3LayoutNode = requireNode(node, 'setOverflow');
            if (overflow != LayoutConstants.OVERFLOW_VISIBLE
                && overflow != LayoutConstants.OVERFLOW_HIDDEN
                && overflow != LayoutConstants.OVERFLOW_SCROLL)
            {
                throw new Error('As3LayoutEngine.setOverflow: 非法 overflow=' + overflow);
            }
            n.overflow = overflow;
        }

        // ---- Compute / query ----------------------------------------------

        // <-> as_ui_yg_calculate. Pass NaN on an unconstrained axis.
        public function calculate(node:Object, availableWidth:Number, availableHeight:Number, direction:int):void
        {
            var root:As3LayoutNode = requireNode(node, 'calculate');
            if (direction != LayoutConstants.DIR_LTR
                && direction != LayoutConstants.DIR_RTL
                && direction != LayoutConstants.DIR_INHERIT)
            {
                throw new Error('As3LayoutEngine.calculate: 非法 direction=' + direction);
            }
            // DIR_INHERIT at the root is LTR.
            var dir:int = (direction == LayoutConstants.DIR_RTL) ? LayoutConstants.DIR_RTL : LayoutConstants.DIR_LTR;

            // Pre-compute intrinsic (max-content) sizes for every node bottom-up,
            // so auto-sized axes have a content size to shrink-wrap to.
            intrinsic(root);

            root.left = 0;
            root.top = 0;
            var bw:Number = rootExtent(root, true, availableWidth, availableHeight, dir);
            var bh:Number = rootExtent(root, false, availableWidth, availableHeight, dir);
            // The root is its own containing block: ownerWidth/Height == the
            // available size (YGNodeCalculateLayout).
            layoutFixed(root, bw, bh, dir, availableWidth, availableHeight);
        }

        // <-> as_ui_yg_set_dirty. The subset recomputes on every calculate, so
        // dirty tracking is a no-op; the widget layer owns real dirty propagation.
        public function setDirty(node:Object):void
        {
            // no-op in the subset
        }

        // <-> as_ui_yg_layout_get.
        public function layoutGet(node:Object, out:Array):void
        {
            if (node == null)
            {
                out[0] = 0; out[1] = 0; out[2] = 0; out[3] = 0;
                return;
            }
            var n:As3LayoutNode = As3LayoutNode(node);
            out[0] = n.left;
            out[1] = n.top;
            out[2] = n.width;
            out[3] = n.height;
        }

        // ---- Gaps: everything below is NOT implemented --------------------
        // Each throws loudly rather than silently returning a wrong layout
        // (AGENTS.md: never fall back to wrong semantics). See seam/README.md.

        public function setDisplay(node:Object, display:int):void { throwGap('setDisplay'); }
        public function setAspectRatio(node:Object, ratio:Number):void { throwGap('setAspectRatio'); }
        public function setMeasure(node:Object, measure:Function, ctx:Object):void { throwGap('setMeasure'); }

        // ==================================================================
        // private plumbing
        // ==================================================================

        private function requireNode(node:Object, who:String):As3LayoutNode
        {
            if (node == null) throw new Error('As3LayoutEngine.' + who + ': null node');
            return As3LayoutNode(node);
        }

        private function throwGap(who:String):void
        {
            throw new Error('As3LayoutEngine.' + who + ': 未实现（纯 AS3 子集缺口；native 走 NativeLayoutEngine/Yoga）——见 seam/README.md');
        }

        private function requireChildAlign(align:int, who:String):void
        {
            if (align != LayoutConstants.ALIGN_FLEX_START
                && align != LayoutConstants.ALIGN_CENTER
                && align != LayoutConstants.ALIGN_FLEX_END
                && align != LayoutConstants.ALIGN_STRETCH)
            {
                throw new Error('As3LayoutEngine.' + who + ': 未实现 align=' + align
                    + '（子集仅 flex-start/center/flex-end/stretch；BASELINE 需文本基线，见 seam/README.md 缺口）');
            }
        }

        // Write one EDGE_* slot into a length-9 (value, unit) pair. Yoga's
        // Style::setEdge handles ALL/HORIZONTAL/VERTICAL by writing every
        // covered slot; the remaining priority resolution is deferred to
        // As3LayoutNode.pickSlot (so a later setMargin(LEFT) cannot clobber an
        // earlier setMargin(START)).
        private function setEdgeSlots(v:Array, u:Array, edge:int, value:Number, unit:int, who:String):void
        {
            var e:int = edge;
            if (e < 0 || e > LayoutConstants.EDGE_ALL)
            {
                throw new Error('As3LayoutEngine.' + who + ': 非法 edge=' + edge);
            }
            if (e == LayoutConstants.EDGE_ALL)
            {
                var k:int;
                for (k = 0; k <= LayoutConstants.EDGE_ALL; k++) { v[k] = value; u[k] = unit; }
                return;
            }
            if (e == LayoutConstants.EDGE_HORIZONTAL)
            {
                v[LayoutConstants.EDGE_LEFT] = value; u[LayoutConstants.EDGE_LEFT] = unit;
                v[LayoutConstants.EDGE_RIGHT] = value; u[LayoutConstants.EDGE_RIGHT] = unit;
                return;
            }
            if (e == LayoutConstants.EDGE_VERTICAL)
            {
                v[LayoutConstants.EDGE_TOP] = value; u[LayoutConstants.EDGE_TOP] = unit;
                v[LayoutConstants.EDGE_BOTTOM] = value; u[LayoutConstants.EDGE_BOTTOM] = unit;
                return;
            }
            v[e] = value;
            u[e] = unit;
        }

        // Resolve a (unit, value) length against `basis`. Returns NaN for
        // auto/undefined and for a percent that cannot resolve.
        private function resolveLen(unit:int, value:Number, basis:Number):Number
        {
            if (unit == LayoutConstants.UNIT_POINT) return value;
            if (unit == LayoutConstants.UNIT_PERCENT)
            {
                if (isNaN(basis)) return NaN;
                return basis * value / 100;   // seam keeps percentages as 0..100
            }
            return NaN;   // UNDEFINED / AUTO / ... -> auto
        }

        // ---- per-node style probes ---------------------------------------

        private function padEdge(n:As3LayoutNode, phys:int, dir:int, w:Number):Number
        {
            return n.edgeValue(n.padV, n.padU, phys, dir, w);
        }

        private function borderEdge(n:As3LayoutNode, phys:int, dir:int, w:Number):Number
        {
            return n.edgeValue(n.borderV, n.borderU, phys, dir, w);
        }

        private function pbEdge(n:As3LayoutNode, phys:int, dir:int, w:Number):Number
        {
            return padEdge(n, phys, dir, w) + borderEdge(n, phys, dir, w);
        }

        private function marginEdge(n:As3LayoutNode, phys:int, dir:int, w:Number):Number
        {
            return n.edgeValue(n.marginV, n.marginU, phys, dir, w);
        }

        private function insetEdge(n:As3LayoutNode, phys:int, dir:int, basis:Number):Number
        {
            return n.edgeValue(n.insetV, n.insetU, phys, dir, basis);
        }

        private function padBorderRow(n:As3LayoutNode, dir:int, w:Number):Number
        {
            return pbEdge(n, LayoutConstants.EDGE_LEFT, dir, w)
                 + pbEdge(n, LayoutConstants.EDGE_RIGHT, dir, w);
        }

        private function padBorderColumn(n:As3LayoutNode, dir:int, w:Number):Number
        {
            return pbEdge(n, LayoutConstants.EDGE_TOP, dir, w)
                 + pbEdge(n, LayoutConstants.EDGE_BOTTOM, dir, w);
        }

        private function borderRow(n:As3LayoutNode, dir:int):Number
        {
            return borderEdge(n, LayoutConstants.EDGE_LEFT, dir, 0)
                 + borderEdge(n, LayoutConstants.EDGE_RIGHT, dir, 0);
        }

        private function borderColumn(n:As3LayoutNode, dir:int):Number
        {
            return borderEdge(n, LayoutConstants.EDGE_TOP, dir, 0)
                 + borderEdge(n, LayoutConstants.EDGE_BOTTOM, dir, 0);
        }

        // Padding + border of the axis that `isWidth` picks, percent padding
        // resolved on the containing block's width (ownerW).
        private function pbAxis(n:As3LayoutNode, dir:int, isWidth:Boolean, ownerW:Number):Number
        {
            if (isWidth) return padBorderRow(n, dir, ownerW);
            return padBorderColumn(n, dir, ownerW);
        }

        private function clampAxis(n:As3LayoutNode, isWidth:Boolean, size:Number, basis:Number):Number
        {
            var mn:Number = resolveLen(
                isWidth ? n.minWidthUnit : n.minHeightUnit,
                isWidth ? n.minWidthValue : n.minHeightValue, basis);
            if (!isNaN(mn)) size = Math.max(size, mn);
            var mx:Number = resolveLen(
                isWidth ? n.maxWidthUnit : n.maxHeightUnit,
                isWidth ? n.maxWidthValue : n.maxHeightValue, basis);
            if (!isNaN(mx)) size = Math.min(size, mx);
            return size;
        }

        // ---- flex-direction algebra (FlexDirection.h) ---------------------

        private function isRowDir(fd:int):Boolean
        {
            return fd == LayoutConstants.FLEX_DIR_ROW || fd == LayoutConstants.FLEX_DIR_ROW_REVERSE;
        }

        // resolveDirection: RTL mirrors row <-> row-reverse.
        private function resolveDir(fd:int, dir:int):int
        {
            if (dir == LayoutConstants.DIR_RTL)
            {
                if (fd == LayoutConstants.FLEX_DIR_ROW) return LayoutConstants.FLEX_DIR_ROW_REVERSE;
                if (fd == LayoutConstants.FLEX_DIR_ROW_REVERSE) return LayoutConstants.FLEX_DIR_ROW;
            }
            return fd;
        }

        // resolveCrossDirection: a column container's cross axis is the row
        // direction (which RTL may then mirror); a row container's is column.
        private function crossDir(fd:int, dir:int):int
        {
            if (!isRowDir(fd)) return resolveDir(LayoutConstants.FLEX_DIR_ROW, dir);
            return LayoutConstants.FLEX_DIR_COLUMN;
        }

        private function flexStartEdgeOf(fd:int):int
        {
            if (fd == LayoutConstants.FLEX_DIR_COLUMN) return LayoutConstants.EDGE_TOP;
            if (fd == LayoutConstants.FLEX_DIR_COLUMN_REVERSE) return LayoutConstants.EDGE_BOTTOM;
            if (fd == LayoutConstants.FLEX_DIR_ROW) return LayoutConstants.EDGE_LEFT;
            return LayoutConstants.EDGE_RIGHT;
        }

        private function flexEndEdgeOf(fd:int):int
        {
            if (fd == LayoutConstants.FLEX_DIR_COLUMN) return LayoutConstants.EDGE_BOTTOM;
            if (fd == LayoutConstants.FLEX_DIR_COLUMN_REVERSE) return LayoutConstants.EDGE_TOP;
            if (fd == LayoutConstants.FLEX_DIR_ROW) return LayoutConstants.EDGE_RIGHT;
            return LayoutConstants.EDGE_LEFT;
        }

        // needsTrailingPosition: only the reverse axes need the mirror step.
        private function needsTrailing(fd:int):Boolean
        {
            return fd == LayoutConstants.FLEX_DIR_ROW_REVERSE || fd == LayoutConstants.FLEX_DIR_COLUMN_REVERSE;
        }

        // inlineStart/EndEdge (FlexDirection.h). Used by relativePosition and by
        // absolute placement; note they depend on the DIRECTORY too.
        private function inlineStartEdgeOf(fd:int, dir:int):int
        {
            if (isRowDir(fd))
            {
                if (dir == LayoutConstants.DIR_RTL) return LayoutConstants.EDGE_RIGHT;
                return LayoutConstants.EDGE_LEFT;
            }
            return LayoutConstants.EDGE_TOP;
        }

        private function inlineEndEdgeOf(fd:int, dir:int):int
        {
            if (isRowDir(fd))
            {
                if (dir == LayoutConstants.DIR_RTL) return LayoutConstants.EDGE_LEFT;
                return LayoutConstants.EDGE_RIGHT;
            }
            return LayoutConstants.EDGE_BOTTOM;
        }

        // ---- alignment algebra (Align.h) ---------------------------------

        // resolveChildAlignment: a child's own align-self wins; auto inherits
        // the parent's align-items; and in a COLUMN flex container a Baseline
        // parent-align is downgraded to FlexStart (there is no baseline).
        private function childAlign(parent:As3LayoutNode, child:As3LayoutNode, dir:int):int
        {
            if (child.alignSelf != LayoutConstants.ALIGN_AUTO) return child.alignSelf;
            var fd:int = resolveDir(parent.flexDirection, dir);
            if (parent.alignItems == LayoutConstants.ALIGN_BASELINE && !isRowDir(fd))
            {
                return LayoutConstants.ALIGN_FLEX_START;
            }
            return parent.alignItems;
        }

        // fallbackAlignment for Align::* (Align.h): SpaceBetween / Stretch /
        // SpaceAround / SpaceEvenly all collapse to FlexStart on overflow;
        // FlexEnd and Center are kept as-is.
        private function fallbackAlign(align:int):int
        {
            if (align == LayoutConstants.ALIGN_SPACE_BETWEEN) return LayoutConstants.ALIGN_FLEX_START;
            if (align == LayoutConstants.ALIGN_STRETCH) return LayoutConstants.ALIGN_FLEX_START;
            if (align == LayoutConstants.ALIGN_SPACE_AROUND) return LayoutConstants.ALIGN_FLEX_START;
            if (align == LayoutConstants.ALIGN_SPACE_EVENLY) return LayoutConstants.ALIGN_FLEX_START;
            return align;
        }

        // ---- numeric -----------------------------------------------------

        private function nearlyEqual(a:Number, b:Number):Boolean
        {
            if (a == b) return true;
            var d:Number = Math.abs(a - b);
            var s:Number = Math.max(Math.abs(a), Math.abs(b));
            return d <= 1e-5 * Math.max(1, s);
        }

        // ---- Pass A: intrinsic (max-content) content sizes ----------------

        private function intrinsic(n:As3LayoutNode):void
        {
            var count:int = n.children.length;
            var i:int;
            for (i = 0; i < count; i++) intrinsic(As3LayoutNode(n.children[i]));

            var row:Boolean = n.isRow();
            var sumMain:Number = 0;
            var maxCross:Number = 0;
            var inFlow:int = 0;
            for (i = 0; i < count; i++)
            {
                var c:As3LayoutNode = As3LayoutNode(n.children[i]);
                // Absolute children are out of flow: they never contribute to
                // their parent's content size.
                if (c.positionType == LayoutConstants.POSITION_ABSOLUTE) continue;
                var cw:Number = childExtent(c, true, NaN);
                var ch:Number = childExtent(c, false, NaN);
                var cm:Number = row ? cw : ch;
                var cx:Number = row ? ch : cw;
                // Margins of the main axis add up; cross margins widen the max.
                var mm:Number = marginForAxis(c, row, NaN);
                var mc:Number = marginForAxis(c, !row, NaN);
                sumMain += cm + mm;
                if (cx + mc > maxCross) maxCross = cx + mc;
                inFlow++;
            }
            var mainGap:Number = row ? n.gapValue(LayoutConstants.GUTTER_COLUMN, NaN)
                                     : n.gapValue(LayoutConstants.GUTTER_ROW, NaN);
            if (inFlow > 1) sumMain += mainGap * (inFlow - 1);
            n.iContentW = row ? sumMain : maxCross;
            n.iContentH = row ? maxCross : sumMain;
        }

        // Intrinsic border-box extent of a child on one axis. A percent is not
        // resolvable without a containing block, so it falls back to the
        // child's own content (matching what Yoga's measure pass sees).
        private function childExtent(c:As3LayoutNode, isWidth:Boolean, basis:Number):Number
        {
            var unit:int = isWidth ? c.widthUnit : c.heightUnit;
            var val:Number = isWidth ? c.widthValue : c.heightValue;
            var pb:Number = pbAxis(c, LayoutConstants.DIR_LTR, isWidth, NaN);
            var v:Number = resolveLen(unit, val, basis);
            if (!isNaN(v))
            {
                if (c.boxSizing == LayoutConstants.BOX_SIZING_CONTENT_BOX) return v + pb;
                return v;
            }
            return (isWidth ? c.iContentW : c.iContentH) + pb;
        }

        // computeMarginForAxis: row/column total margin, always resolved on the
        // containing block's WIDTH (Style hardcodes LTR + widthSize).
        private function marginForAxis(c:As3LayoutNode, rowAxis:Boolean, w:Number):Number
        {
            if (rowAxis)
            {
                return marginEdge(c, LayoutConstants.EDGE_LEFT, LayoutConstants.DIR_LTR, w)
                     + marginEdge(c, LayoutConstants.EDGE_RIGHT, LayoutConstants.DIR_LTR, w);
            }
            return marginEdge(c, LayoutConstants.EDGE_TOP, LayoutConstants.DIR_LTR, w)
                 + marginEdge(c, LayoutConstants.EDGE_BOTTOM, LayoutConstants.DIR_LTR, w);
        }

        // ---- root sizing --------------------------------------------------

        // The root's own border-box size: explicit (point/percent) wins, then a
        // max-size, then the available size (StretchFit), then intrinsic
        // content. Mirrors YGNodeCalculateLayout's root sizing-mode selection.
        private function rootExtent(n:As3LayoutNode, isWidth:Boolean, ownerW:Number, ownerH:Number, dir:int):Number
        {
            var avail:Number = isWidth ? ownerW : ownerH;
            var unit:int = isWidth ? n.widthUnit : n.heightUnit;
            var val:Number = isWidth ? n.widthValue : n.heightValue;
            var pb:Number = pbAxis(n, dir, isWidth, ownerW);
            var v:Number = resolveLen(unit, val, avail);
            var size:Number;
            if (!isNaN(v))
            {
                size = v;
                if (n.boxSizing == LayoutConstants.BOX_SIZING_CONTENT_BOX) size = v + pb;
            }
            else
            {
                var mx:Number = resolveLen(isWidth ? n.maxWidthUnit : n.maxHeightUnit,
                    isWidth ? n.maxWidthValue : n.maxHeightValue, avail);
                if (!isNaN(mx)) size = mx;
                else if (!isNaN(avail)) size = avail;
                else size = (isWidth ? n.iContentW : n.iContentH) + pb;
            }
            size = clampAxis(n, isWidth, size, avail);
            return Math.max(size, pb);
        }

        // ---- Pass B: given a fixed border-box size, lay out the subtree -----

        private function layoutFixed(n:As3LayoutNode, bw:Number, bh:Number, dir:int, ownerW:Number, ownerH:Number):void
        {
            var pbH:Number = padBorderRow(n, dir, ownerW);
            var pbV:Number = padBorderColumn(n, dir, ownerW);
            n.width = Math.max(bw, pbH);
            n.height = Math.max(bh, pbV);
            var contentW:Number = n.width - pbH;
            var contentH:Number = n.height - pbV;
            layoutChildren(n, contentW, contentH, dir, ownerW, ownerH);
        }

        private function layoutChildren(n:As3LayoutNode, contentW:Number, contentH:Number, dir:int, ownerW:Number, ownerH:Number):void
        {
            var count:int = n.children.length;
            if (count == 0) return;

            var fd:int = resolveDir(n.flexDirection, dir);
            var mainRow:Boolean = isRowDir(fd);
            var crossAxis:int = crossDir(n.flexDirection, dir);

            var availInnerMain:Number = mainRow ? contentW : contentH;
            var availInnerCross:Number = mainRow ? contentH : contentW;

            var mainStart:int = flexStartEdgeOf(fd);
            var mainEnd:int = flexEndEdgeOf(fd);
            var crossStart:int = flexStartEdgeOf(crossAxis);
            var crossEnd:int = flexEndEdgeOf(crossAxis);

            // computeGapForAxis: row axis -> column-gap, column axis -> row-gap.
            var mainGap:Number = n.gapForAxis(mainRow, availInnerMain);
            var crossGap:Number = n.gapForAxis(!mainRow, availInnerCross);

            // Padding/border at the flex start edge (percentage padding resolves
            // on the container's owner width, not its own width).
            var leadPadMain:Number = pbEdge(n, mainStart, dir, ownerW);
            var leadPadCross:Number = pbEdge(n, crossStart, dir, ownerW);

            // Partition children: absolute ones are out of flow and are placed
            // AFTER the flex pass (STEP 11), like Yoga's layoutAbsoluteChild.
            var flow:Array = [];
            var absChildren:Array = [];
            var i:int;
            for (i = 0; i < count; i++)
            {
                var child:As3LayoutNode = As3LayoutNode(n.children[i]);
                if (child.positionType == LayoutConstants.POSITION_ABSOLUTE) absChildren.push(child);
                else flow.push(child);
            }

            var fn:int = flow.length;
            if (fn > 0)
            {
                layoutFlow(n, flow, dir, mainRow, fd, crossAxis, mainStart, mainEnd, crossStart, crossEnd,
                    mainGap, crossGap, leadPadMain, leadPadCross, contentW, contentH, availInnerMain, availInnerCross);
            }

            for (i = 0; i < absChildren.length; i++)
            {
                layoutAbsoluteChild(n, As3LayoutNode(absChildren[i]), dir, fd, crossAxis, contentW, contentH, ownerW, ownerH);
            }
        }

        // The flex algorithm proper, for one container's in-flow children.
        private function layoutFlow(n:As3LayoutNode, flow:Array, dir:int, mainRow:Boolean, fd:int, crossAxis:int,
            mainStart:int, mainEnd:int, crossStart:int, crossEnd:int,
            mainGap:Number, crossGap:Number, leadPadMain:Number, leadPadCross:Number,
            contentW:Number, contentH:Number, availInnerMain:Number, availInnerCross:Number):void
        {
            var fn:int = flow.length;
            var i:int;
            var k:int;
            var L:int;
            var idx:int;

            // ---- STEP 3: flex base sizes + margins ---------------------------
            var bases:Array = [];
            var bClamp:Array = [];
            var mS:Array = [];      // main start margin
            var mE:Array = [];      // main end margin
            var cS:Array = [];      // cross start margin
            var cE:Array = [];      // cross end margin
            for (i = 0; i < fn; i++)
            {
                var c:As3LayoutNode = As3LayoutNode(flow[i]);
                var pbMain:Number = pbAxis(c, dir, mainRow, contentW);
                var b:Number = flexBaseMain(c, mainRow, contentW, contentH, pbMain);
                bases[i] = b;
                bClamp[i] = clampAxis(c, mainRow, b, mainRow ? contentW : contentH);
                mS[i] = marginEdge(c, mainStart, dir, contentW);
                mE[i] = marginEdge(c, mainEnd, dir, contentW);
                cS[i] = marginEdge(c, crossStart, dir, contentW);
                cE[i] = marginEdge(c, crossEnd, dir, contentW);
            }

            // ---- STEP 4: break the children into flex lines ------------------
            var wrap:Boolean = (n.flexWrap != LayoutConstants.WRAP_NO_WRAP);
            var lines:Array = [];
            var cur:Array = [];
            var consumed:Number = 0;
            for (i = 0; i < fn; i++)
            {
                var gapBefore:Number = (cur.length == 0) ? 0 : mainGap;
                var itemOuter:Number = bClamp[i] + mS[i] + mE[i];
                // Yoga breaks when the item (with its margins and the leading
                // gap) pushes past the line, unless it exactly fits
                // (inexactEquals) or it would be alone on the line.
                var required:Number = consumed + gapBefore + itemOuter;
                if (wrap && !isNaN(availInnerMain) && cur.length > 0
                    && required > availInnerMain && !nearlyEqual(required, availInnerMain))
                {
                    lines.push(cur);
                    cur = [];
                    gapBefore = 0;
                    consumed = 0;
                }
                cur.push(i);
                consumed += gapBefore + itemOuter;
            }
            if (cur.length > 0) lines.push(cur);
            var lineCount:int = lines.length;

            // Line cross sizes (max over the line's children of cross + cross
            // margins) and the accumulated total.
            var lineCross:Array = [];
            var totalLineCrossDim:Number = 0;
            for (L = 0; L < lineCount; L++)
            {
                var ln:Array = lines[L];
                var lc:Number = 0;
                for (k = 0; k < ln.length; k++)
                {
                    idx = int(ln[k]);
                    var cc:Number = crossSizeOf(As3LayoutNode(flow[idx]), mainRow, contentW, contentH, dir);
                    var outer:Number = cc + cS[idx] + cE[idx];
                    if (outer > lc) lc = outer;
                }
                lineCross[L] = lc;
                totalLineCrossDim += lc + (L != 0 ? crossGap : 0);
            }

            // ---- STEP 8 (positions): cross-axis placement --------------------
            // For each in-flow child we compute its cross size and the position
            // on its cross flex-start edge; the row/column split is resolved at
            // the very end (so a reverse axis can mirror in one place).
            var crossSizeArr:Array = [];
            var crossPosArr:Array = [];

            if (!wrap)
            {
                // Single line. Yoga forces the line's cross size to the
                // container's inner cross when that is definite
                // (sizingModeCrossDim == StretchFit); otherwise it is the max
                // of the children.
                var lineCrossVal:Number = isNaN(availInnerCross) ? lineCross[0] : availInnerCross;
                var containerCross:Number = lineCrossVal;
                for (i = 0; i < fn; i++)
                {
                    var ci:As3LayoutNode = As3LayoutNode(flow[i]);
                    var align:int = childAlign(n, ci, dir);
                    var defCross:Number = crossSizeDefinite(ci, mainRow, contentW, contentH);
                    var cs:Number;
                    if (!isNaN(defCross)) cs = clampAxis(ci, !mainRow, defCross, mainRow ? contentH : contentW);
                    else if (align == LayoutConstants.ALIGN_STRETCH) cs = lineCrossVal;
                    else cs = clampAxis(ci, !mainRow, crossSizeOf(ci, mainRow, contentW, contentH, dir), mainRow ? contentH : contentW);
                    crossSizeArr[i] = cs;

                    var remainCross:Number = containerCross - (cs + cS[i] + cE[i]);
                    var leadCross:Number = leadPadCross;
                    if (align != LayoutConstants.ALIGN_STRETCH && align != LayoutConstants.ALIGN_FLEX_START)
                    {
                        if (align == LayoutConstants.ALIGN_CENTER) leadCross += remainCross / 2;
                        else leadCross += remainCross;
                    }
                    crossPosArr[i] = cS[i] + leadCross;
                }
            }
            else
            {
                // Multi-line: place the lines (align-content), then the children
                // inside each line (align-items / align-self).
                var innerCross:Number = isNaN(availInnerCross) ? totalLineCrossDim : availInnerCross;
                // NB: AS3 `var` is function-scoped and rejects a redeclaration,
                // so the cross-axis remainder is named apart from the main-axis
                // one below (mxmlc enforces this; our AOT did not).
                var remainingCross:Number = innerCross - totalLineCrossDim;
                var ac:int = (remainingCross >= 0) ? n.alignContent : fallbackAlign(n.alignContent);
                var leadPerLine:Number = 0;
                var currentLead:Number = leadPadCross;
                var extraSpacePerLine:Number = 0;
                if (ac == LayoutConstants.ALIGN_FLEX_END) currentLead += remainingCross;
                else if (ac == LayoutConstants.ALIGN_CENTER) currentLead += remainingCross / 2;
                else if (ac == LayoutConstants.ALIGN_STRETCH) extraSpacePerLine = remainingCross / lineCount;
                else if (ac == LayoutConstants.ALIGN_SPACE_AROUND)
                {
                    currentLead += remainingCross / (2 * lineCount);
                    leadPerLine = remainingCross / lineCount;
                }
                else if (ac == LayoutConstants.ALIGN_SPACE_EVENLY)
                {
                    currentLead += remainingCross / (lineCount + 1);
                    leadPerLine = remainingCross / (lineCount + 1);
                }
                else if (ac == LayoutConstants.ALIGN_SPACE_BETWEEN)
                {
                    if (lineCount > 1) leadPerLine = remainingCross / (lineCount - 1);
                }

                for (L = 0; L < lineCount; L++)
                {
                    if (L != 0) currentLead += crossGap;
                    var lineH:Number = lineCross[L] + extraSpacePerLine;
                    var ln2:Array = lines[L];
                    for (k = 0; k < ln2.length; k++)
                    {
                        var cj:As3LayoutNode = As3LayoutNode(flow[int(ln2[k])]);
                        idx = int(ln2[k]);
                        var al:int = childAlign(n, cj, dir);
                        var dc:Number = crossSizeDefinite(cj, mainRow, contentW, contentH);
                        var csz:Number;
                        if (!isNaN(dc)) csz = clampAxis(cj, !mainRow, dc, mainRow ? contentH : contentW);
                        else if (al == LayoutConstants.ALIGN_STRETCH) csz = leadPerLine + lineH;
                        else csz = clampAxis(cj, !mainRow, crossSizeOf(cj, mainRow, contentW, contentH, dir), mainRow ? contentH : contentW);
                        crossSizeArr[idx] = csz;

                        if (al == LayoutConstants.ALIGN_FLEX_END) crossPosArr[idx] = currentLead + lineH - cE[idx] - csz;
                        else if (al == LayoutConstants.ALIGN_CENTER) crossPosArr[idx] = currentLead + (lineH - csz) / 2;
                        else crossPosArr[idx] = currentLead + cS[idx];
                    }
                    currentLead += leadPerLine + lineH;
                }
            }

            // ---- STEP 5/6: main-axis flex + justification, per line ----------
            var mainSizeArr:Array = [];
            var mainPosArr:Array = [];
            for (L = 0; L < lineCount; L++)
            {
                var line:Array = lines[L];
                var ln3:int = line.length;
                var sizeConsumed:Number = 0;
                for (k = 0; k < ln3; k++)
                {
                    idx = int(line[k]);
                    sizeConsumed += bClamp[idx] + mS[idx] + mE[idx];
                }
                if (ln3 > 1) sizeConsumed += mainGap * (ln3 - 1);

                var original:Number = isNaN(availInnerMain) ? 0 : (availInnerMain - sizeConsumed);
                var used:Array = [];
                var sumBase:Number = 0;
                for (k = 0; k < ln3; k++) { used[k] = bases[int(line[k])]; sumBase += bases[int(line[k])]; }

                if (!isNaN(availInnerMain) && original > 0)
                {
                    // grow: distribute free space by grow factor (floored to 1
                    // when 0 < sum < 1, per FlexLine).
                    var growSum:Number = 0;
                    for (k = 0; k < ln3; k++) growSum += As3LayoutNode(flow[int(line[k])]).flexGrow;
                    if (growSum > 0 && growSum < 1) growSum = 1;
                    if (growSum > 0)
                    {
                        for (k = 0; k < ln3; k++)
                        {
                            var g:Number = As3LayoutNode(flow[int(line[k])]).flexGrow;
                            used[k] = bases[int(line[k])] + original * g / growSum;
                        }
                    }
                }
                else if (!isNaN(availInnerMain) && original < 0)
                {
                    // shrink: distribute by flex-shrink * basis, floored to 1.
                    var wsum:Number = 0;
                    for (k = 0; k < ln3; k++)
                    {
                        var si:As3LayoutNode = As3LayoutNode(flow[int(line[k])]);
                        wsum += si.flexShrink * bases[int(line[k])];
                    }
                    if (wsum > 0 && wsum < 1) wsum = 1;
                    if (wsum > 0)
                    {
                        for (k = 0; k < ln3; k++)
                        {
                            var sj:As3LayoutNode = As3LayoutNode(flow[int(line[k])]);
                            used[k] = bases[int(line[k])] - (-original) * (sj.flexShrink * bases[int(line[k])]) / wsum;
                        }
                    }
                }

                // min/max clamp the final main size, AFTER the flex solve.
                var sumUsed:Number = 0;
                for (k = 0; k < ln3; k++)
                {
                    idx = int(line[k]);
                    used[k] = clampAxis(As3LayoutNode(flow[idx]), mainRow, used[k], mainRow ? contentW : contentH);
                    sumUsed += used[k];
                    mainSizeArr[idx] = used[k];
                }
                var distributed:Number = sumUsed - sumBase;
                var remainingMain:Number = original - distributed;

                var justify:int = (remainingMain >= 0) ? n.justifyContent : fallbackJustify(n.justifyContent);
                var leadingMain:Number = 0;
                var betweenMain:Number = mainGap;
                if (justify == LayoutConstants.JUSTIFY_CENTER) leadingMain = remainingMain / 2;
                else if (justify == LayoutConstants.JUSTIFY_FLEX_END) leadingMain = remainingMain;
                else if (justify == LayoutConstants.JUSTIFY_SPACE_BETWEEN)
                {
                    if (ln3 > 1) betweenMain += remainingMain / (ln3 - 1);
                }
                else if (justify == LayoutConstants.JUSTIFY_SPACE_AROUND)
                {
                    leadingMain = 0.5 * remainingMain / ln3;
                    betweenMain += leadingMain * 2;
                }
                else if (justify == LayoutConstants.JUSTIFY_SPACE_EVENLY)
                {
                    leadingMain = remainingMain / (ln3 + 1);
                    betweenMain += leadingMain;
                }

                var cursor:Number = leadPadMain + leadingMain;
                for (k = 0; k < ln3; k++)
                {
                    idx = int(line[k]);
                    mainPosArr[idx] = mS[idx] + cursor;
                    if (k != ln3 - 1) cursor += betweenMain;
                    cursor += used[k] + mS[idx] + mE[idx];
                }
            }

            // ---- STEP 7/9/10: resolve the physical box, recurse, mirror -------
            // wrap-reverse is a POST-pass: compute the layout normally, then
            // mirror every in-flow child along the cross axis
            // (crossPos = parentCross - childCross - crossPos). It is applied
            // BEFORE the physical conversion, exactly as Yoga applies it before
            // its trailing-position step.
            var wrapReverse:Boolean = (n.flexWrap == LayoutConstants.WRAP_WRAP_REVERSE);
            var parentCrossDim:Number = mainRow ? n.height : n.width;

            for (i = 0; i < fn; i++)
            {
                var cf:As3LayoutNode = As3LayoutNode(flow[i]);
                var mainSize:Number = mainSizeArr[i];
                var crossSize:Number = crossSizeArr[i];
                var mainPos:Number = mainPosArr[i];
                var crossPos:Number = crossPosArr[i];
                if (wrapReverse) crossPos = parentCrossDim - crossSize - crossPos;
                var relMain:Number = relativePosition(cf, fd, dir, contentW, contentH);
                var relCross:Number = relativePosition(cf, crossAxis, dir, contentW, contentH);
                mainPos += relMain;
                crossPos += relCross;

                if (mainRow)
                {
                    // main = horizontal
                    cf.left = (mainStart == LayoutConstants.EDGE_LEFT)
                        ? mainPos : (n.width - mainSize - mainPos);
                    // cross = vertical
                    cf.top = (crossStart == LayoutConstants.EDGE_TOP)
                        ? crossPos : (n.height - crossSize - crossPos);
                    layoutFixed(cf, mainSize, crossSize, dir, contentW, contentH);
                }
                else
                {
                    // main = vertical
                    cf.top = (mainStart == LayoutConstants.EDGE_TOP)
                        ? mainPos : (n.height - mainSize - mainPos);
                    // cross = horizontal
                    cf.left = (crossStart == LayoutConstants.EDGE_LEFT)
                        ? crossPos : (n.width - crossSize - crossPos);
                    layoutFixed(cf, crossSize, mainSize, dir, contentW, contentH);
                }
            }
        }

        // flex-basis / the item's own main size / its content, clamped to at
        // least padding+border (Node::computeFlexBasisForChild).
        private function flexBaseMain(c:As3LayoutNode, mainRow:Boolean, contentW:Number, contentH:Number, pbMain:Number):Number
        {
            var basis:Number = mainRow ? contentW : contentH;
            if (c.hasFlex)
            {
                if (c.flexBasisUnit == LayoutConstants.UNIT_POINT) return Math.max(c.flexBasisValue, pbMain);
                if (c.flexBasisUnit == LayoutConstants.UNIT_PERCENT)
                {
                    var p:Number = resolveLen(LayoutConstants.UNIT_PERCENT, c.flexBasisValue, basis);
                    if (!isNaN(p)) return Math.max(p, pbMain);
                    // unresolvable percent -> fall through to the explicit size
                }
                else return Math.max(0, pbMain);   // UNIT_UNDEFINED == explicit 0 basis
            }

            var unit:int = mainRow ? c.widthUnit : c.heightUnit;
            var val:Number = mainRow ? c.widthValue : c.heightValue;
            var v:Number = resolveLen(unit, val, basis);
            if (!isNaN(v))
            {
                if (c.boxSizing == LayoutConstants.BOX_SIZING_CONTENT_BOX) v = v + pbMain;
                return Math.max(v, pbMain);
            }
            var ic:Number = mainRow ? c.iContentW : c.iContentH;
            return Math.max(ic + pbMain, pbMain);
        }

        // The cross size if the child declares one (point or resolvable
        // percent); NaN otherwise. Border-box unless content-box.
        private function crossSizeDefinite(c:As3LayoutNode, mainRow:Boolean, contentW:Number, contentH:Number):Number
        {
            var unit:int = mainRow ? c.heightUnit : c.widthUnit;
            var val:Number = mainRow ? c.heightValue : c.widthValue;
            var basis:Number = mainRow ? contentH : contentW;
            var v:Number = resolveLen(unit, val, basis);
            if (isNaN(v)) return NaN;
            if (c.boxSizing == LayoutConstants.BOX_SIZING_CONTENT_BOX)
            {
                v = v + pbAxis(c, LayoutConstants.DIR_LTR, !mainRow, contentW);
            }
            return v;
        }

        // Cross size used for the LINE's cross dimension: the declared one, or
        // the child's own content (a leaf contributes just its padding+border).
        private function crossSizeOf(c:As3LayoutNode, mainRow:Boolean, contentW:Number, contentH:Number, dir:int):Number
        {
            var d:Number = crossSizeDefinite(c, mainRow, contentW, contentH);
            if (!isNaN(d)) return d;
            var pb:Number = pbAxis(c, dir, !mainRow, contentW);
            return (mainRow ? c.iContentH : c.iContentW) + pb;
        }

        // fallbackAlignment for Justify::* (Align.h): the three space-* values
        // collapse to FlexStart on overflow; FlexEnd and Center are kept.
        private function fallbackJustify(justify:int):int
        {
            if (justify == LayoutConstants.JUSTIFY_SPACE_BETWEEN) return LayoutConstants.JUSTIFY_FLEX_START;
            if (justify == LayoutConstants.JUSTIFY_SPACE_AROUND) return LayoutConstants.JUSTIFY_FLEX_START;
            if (justify == LayoutConstants.JUSTIFY_SPACE_EVENLY) return LayoutConstants.JUSTIFY_FLEX_START;
            return justify;
        }

        // Node::relativePosition: a relative node shifts by the start inset if
        // it is defined, otherwise by the NEGATIVE end inset. STATIC is rejected
        // at the setter, so it never reaches here.
        private function relativePosition(c:As3LayoutNode, axis:int, dir:int, contentW:Number, contentH:Number):Number
        {
            if (c.positionType == LayoutConstants.POSITION_ABSOLUTE) return 0;
            var axisSize:Number = isRowDir(axis) ? contentW : contentH;
            var se:int = inlineStartEdgeOf(axis, dir);
            if (c.edgeDefined(c.insetV, c.insetU, se, dir))
            {
                return insetEdge(c, se, dir, axisSize);
            }
            var ee:int = inlineEndEdgeOf(axis, dir);
            return -1 * insetEdge(c, ee, dir, axisSize);
        }

        // ---- absolute children (AbsoluteLayout.cpp) -----------------------

        private function layoutAbsoluteChild(containing:As3LayoutNode, c:As3LayoutNode, dir:int,
            fd:int, crossAxis:int, contentW:Number, contentH:Number, ownerW:Number, ownerH:Number):void
        {
            // The containing block is the parent's PADDING box: measured size
            // minus its BORDER (ExcludesPadding errata is off, so the padding is
            // included in the containing block).
            var cbW:Number = containing.width - borderRow(containing, dir);
            var cbH:Number = containing.height - borderColumn(containing, dir);

            var marginRow:Number = marginForAxis(c, true, cbW);
            var marginColumn:Number = marginForAxis(c, false, cbW);

            var childW:Number = NaN;
            if (c.widthUnit == LayoutConstants.UNIT_POINT
                || (c.widthUnit == LayoutConstants.UNIT_PERCENT && !isNaN(cbW)))
            {
                childW = resolveLen(c.widthUnit, c.widthValue, cbW);
            }
            else if (horizontalInsetsDefined(c, dir))
            {
                // left + right insets pin the width (boundAxis omitted here).
                childW = containing.width - borderRow(containing, dir)
                    - (insetEdge(c, inlineStartEdgeOf(LayoutConstants.FLEX_DIR_ROW, dir), dir, cbW)
                     + insetEdge(c, inlineEndEdgeOf(LayoutConstants.FLEX_DIR_ROW, dir), dir, cbW));
            }

            var childH:Number = NaN;
            if (c.heightUnit == LayoutConstants.UNIT_POINT
                || (c.heightUnit == LayoutConstants.UNIT_PERCENT && !isNaN(cbH)))
            {
                childH = resolveLen(c.heightUnit, c.heightValue, cbH);
            }
            else if (verticalInsetsDefined(c, dir))
            {
                childH = containing.height - borderColumn(containing, dir)
                    - (insetEdge(c, inlineStartEdgeOf(LayoutConstants.FLEX_DIR_COLUMN, dir), dir, cbH)
                     + insetEdge(c, inlineEndEdgeOf(LayoutConstants.FLEX_DIR_COLUMN, dir), dir, cbH));
            }

            if (isNaN(childW)) childW = c.iContentW + padBorderRow(c, dir, cbW);
            if (isNaN(childH)) childH = c.iContentH + padBorderColumn(c, dir, cbW);
            childW = Math.max(childW, padBorderRow(c, dir, cbW));
            childH = Math.max(childH, padBorderColumn(c, dir, cbW));

            // Place on each axis. `mainAxis` first, then the cross axis; the
            // position is written on the flex-start edge and mirrored by the
            // caller when the axis is reversed.
            absAxis(containing, c, dir, fd, true, cbW, cbH, childW, childH);
            absAxis(containing, c, dir, crossAxis, false, cbW, cbH, childW, childH);

            // Convert "position on the flex-start edge" to physical left/top.
            if (needsTrailing(fd))
            {
                if (isRowDir(fd)) c.left = containing.width - childW - c.left;
                else c.top = containing.height - childH - c.top;
            }
            if (needsTrailing(crossAxis))
            {
                if (isRowDir(crossAxis)) c.left = containing.width - childW - c.left;
                else c.top = containing.height - childH - c.top;
            }

            layoutFixed(c, childW, childH, dir, cbW, cbH);
        }

        // One axis of positionAbsoluteChild. NB: Yoga resolves EVERY margin
        // percent against the containing block's WIDTH (containingBlockWidth) in
        // AbsoluteLayout, but the insets against the axis' own containing size.
        private function absAxis(containing:As3LayoutNode, c:As3LayoutNode, dir:int, axis:int,
            isMainAxis:Boolean, cbW:Number, cbH:Number, childW:Number, childH:Number):void
        {
            var isAxisRow:Boolean = isRowDir(axis);
            var cbSize:Number = isAxisRow ? cbW : cbH;
            var parentDim:Number = isAxisRow ? containing.width : containing.height;
            var childDim:Number = isAxisRow ? childW : childH;

            var startEdge:int = inlineStartEdgeOf(axis, dir);
            var endEdge:int = inlineEndEdgeOf(axis, dir);
            var fStartEdge:int = flexStartEdgeOf(axis);
            var invert:Boolean = (startEdge != fStartEdge);

            if (c.edgeDefined(c.insetV, c.insetU, startEdge, dir))
            {
                var pStart:Number = insetEdge(c, startEdge, dir, cbSize)
                    + borderEdge(containing, startEdge, dir, cbW)
                    + marginEdge(c, startEdge, dir, cbW);
                var pFlex:Number = invert ? (parentDim - childDim - pStart) : pStart;
                setAxisPos(c, fStartEdge, pFlex);
            }
            else if (c.edgeDefined(c.insetV, c.insetU, endEdge, dir))
            {
                var pEnd:Number = parentDim - childDim
                    - borderEdge(containing, endEdge, dir, cbW)
                    - marginEdge(c, endEdge, dir, cbW)
                    - insetEdge(c, endEdge, dir, cbSize);
                var pFlex2:Number = invert ? (parentDim - childDim - pEnd) : pEnd;
                setAxisPos(c, fStartEdge, pFlex2);
            }
            else if (isMainAxis)
            {
                // justifyAbsoluteChild: reuses the parent's justifyContent.
                var j:int = containing.justifyContent;
                if (j == LayoutConstants.JUSTIFY_FLEX_END) absFlexEnd(containing, c, dir, axis, cbW, childW, childH);
                else if (j == LayoutConstants.JUSTIFY_CENTER) absCenter(containing, c, dir, axis, cbW, childW, childH);
                else absFlexStart(containing, c, dir, axis, cbW, childW, childH);
            }
            else
            {
                // alignAbsoluteChild: align-self / align-items.
                var a:int = childAlign(containing, c, dir);
                if (a == LayoutConstants.ALIGN_FLEX_END) absFlexEnd(containing, c, dir, axis, cbW, childW, childH);
                else if (a == LayoutConstants.ALIGN_CENTER) absCenter(containing, c, dir, axis, cbW, childW, childH);
                else absFlexStart(containing, c, dir, axis, cbW, childW, childH);
            }
        }

        private function setAxisPos(c:As3LayoutNode, physEdge:int, value:Number):void
        {
            if (physEdge == LayoutConstants.EDGE_LEFT) c.left = value;
            else if (physEdge == LayoutConstants.EDGE_TOP) c.top = value;
            else if (physEdge == LayoutConstants.EDGE_RIGHT) c.left = value;   // provisional; mirrored later
            else c.top = value;
        }

        private function absFlexStart(containing:As3LayoutNode, c:As3LayoutNode, dir:int, axis:int,
            cbW:Number, childW:Number, childH:Number):void
        {
            var isAxisRow:Boolean = isRowDir(axis);
            var parentDim:Number = isAxisRow ? containing.width : containing.height;
            var childDim:Number = isAxisRow ? childW : childH;
            var fStart:int = flexStartEdgeOf(axis);
            var pos:Number = marginEdge(c, fStart, dir, cbW) + borderEdge(containing, fStart, dir, cbW)
                + padEdge(containing, fStart, dir, cbW);
            var invert:Boolean = (inlineStartEdgeOf(axis, dir) != fStart);
            setAxisPos(c, fStart, invert ? (parentDim - childDim - pos) : pos);
        }

        private function absFlexEnd(containing:As3LayoutNode, c:As3LayoutNode, dir:int, axis:int,
            cbW:Number, childW:Number, childH:Number):void
        {
            var isAxisRow:Boolean = isRowDir(axis);
            var parentDim:Number = isAxisRow ? containing.width : containing.height;
            var childDim:Number = isAxisRow ? childW : childH;
            var fEnd:int = flexEndEdgeOf(axis);
            var fStart:int = flexStartEdgeOf(axis);
            var pos:Number = parentDim - childDim
                - marginEdge(c, fEnd, dir, cbW) - borderEdge(containing, fEnd, dir, cbW)
                - padEdge(containing, fEnd, dir, cbW);
            var invert:Boolean = (inlineStartEdgeOf(axis, dir) != fStart);
            setAxisPos(c, fStart, invert ? (parentDim - childDim - pos) : pos);
        }

        private function absCenter(containing:As3LayoutNode, c:As3LayoutNode, dir:int, axis:int,
            cbW:Number, childW:Number, childH:Number):void
        {
            var isAxisRow:Boolean = isRowDir(axis);
            var parentDim:Number = isAxisRow ? containing.width : containing.height;
            var childDim:Number = isAxisRow ? childW : childH;
            var fStart:int = flexStartEdgeOf(axis);
            var fEnd:int = flexEndEdgeOf(axis);
            var outer:Number = childDim + marginForAxis(c, isAxisRow, cbW);
            var contentBox:Number = parentDim
                - borderEdge(containing, fStart, dir, cbW) - borderEdge(containing, fEnd, dir, cbW)
                - padEdge(containing, fStart, dir, cbW) - padEdge(containing, fEnd, dir, cbW);
            var pos:Number = (contentBox - outer) / 2
                + borderEdge(containing, fStart, dir, cbW)
                + padEdge(containing, fStart, dir, cbW)
                + marginEdge(c, fStart, dir, cbW);
            var invert:Boolean = (inlineStartEdgeOf(axis, dir) != fStart);
            setAxisPos(c, fStart, invert ? (parentDim - childDim - pos) : pos);
        }

        private function horizontalInsetsDefined(c:As3LayoutNode, dir:int):Boolean
        {
            var se:int = inlineStartEdgeOf(LayoutConstants.FLEX_DIR_ROW, dir);
            var ee:int = inlineEndEdgeOf(LayoutConstants.FLEX_DIR_ROW, dir);
            return c.edgeDefined(c.insetV, c.insetU, se, dir) && c.edgeDefined(c.insetV, c.insetU, ee, dir);
        }

        private function verticalInsetsDefined(c:As3LayoutNode, dir:int):Boolean
        {
            var se:int = inlineStartEdgeOf(LayoutConstants.FLEX_DIR_COLUMN, dir);
            var ee:int = inlineEndEdgeOf(LayoutConstants.FLEX_DIR_COLUMN, dir);
            return c.edgeDefined(c.insetV, c.insetU, se, dir) && c.edgeDefined(c.insetV, c.insetU, ee, dir);
        }
    }
}
