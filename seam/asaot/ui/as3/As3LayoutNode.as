// asaot.ui.as3.As3LayoutNode -- the per-node record owned by As3LayoutEngine.
//
// Callers never see this type: the seam hands it back as an opaque `Object`,
// exactly as the native engine hands back a wrapped `void*` handle. Casting it
// back inside As3LayoutEngine is the AS3-side equivalent of the C seam's
// "the C side never dereferences the opaque void*".
//
// EDGES ARE STORED AS (value, unit) SLOTS, NOT AS SCALARS. That mirrors Yoga's
// `Style::Edges` (9 slots: left/top/right/bottom/start/end/horizontal/vertical/
// all) because the RESOLUTION ORDER between those slots is observable: a later
// `setMargin(LEFT)` must not clobber an earlier `setMargin(START)`, and in RTL
// EDGE_START means the right edge. Collapsing them into four scalars at set
// time (what this class used to do) loses both facts. The slots are resolved
// lazily, per physical edge, by edgeValue()/edgeDefined(), with the direction
// threaded through -- see Style::computeLeftEdge in the Yoga source.
package asaot.ui.as3
{
    import asaot.ui.LayoutConstants;

    public class As3LayoutNode
    {
        // Tri-state length, one (value, unit) pair per axis. `unit` is a
        // LayoutConstants.UNIT_* value; UNIT_UNDEFINED means auto / not set.
        public var widthValue:Number = 0;
        public var widthUnit:int = LayoutConstants.UNIT_UNDEFINED;
        public var heightValue:Number = 0;
        public var heightUnit:int = LayoutConstants.UNIT_UNDEFINED;

        // The style default applied by createNode, NOT a hardcoded constant:
        // web defaults (YGConfigSetUseWebDefaults) make a fresh node default
        // to row, Yoga's own default is column (yoga_glue.h:246-249). The
        // initializer below is only what a node gets before createNode has had
        // its say, so it must never be relied on directly.
        public var flexDirection:int = LayoutConstants.FLEX_DIR_COLUMN;

        // ---- flex item properties (setFlex) ------------------------------
        // `hasFlex` distinguishes "setFlex was called" from the defaults: when
        // it is true, a UNIT_UNDEFINED basis means an EXPLICIT 0 basis (flex:1
        // style), NOT the item's own width/height. When false, the item keeps
        // its explicit main size (this is how a plain child with width=100
        // stays 100 without any flex-basis).
        public var hasFlex:Boolean = false;
        public var flexGrow:Number = 0;
        public var flexShrink:Number = 1;
        public var flexBasisValue:Number = 0;
        public var flexBasisUnit:int = LayoutConstants.UNIT_UNDEFINED;

        // ---- min / max box (setMinMax); UNIT_UNDEFINED == unset ----------
        public var minWidthValue:Number = 0;
        public var minWidthUnit:int = LayoutConstants.UNIT_UNDEFINED;
        public var maxWidthValue:Number = 0;
        public var maxWidthUnit:int = LayoutConstants.UNIT_UNDEFINED;
        public var minHeightValue:Number = 0;
        public var minHeightUnit:int = LayoutConstants.UNIT_UNDEFINED;
        public var maxHeightValue:Number = 0;
        public var maxHeightUnit:int = LayoutConstants.UNIT_UNDEFINED;

        // ---- box model (setMargin / setPadding / setBorder / setPosition) -
        // Each is two parallel length-9 arrays indexed by LayoutConstants.EDGE_*
        // (V = values, U = units). See the file header for why they are kept as
        // slots rather than resolved scalars.
        public var marginV:Array = [0, 0, 0, 0, 0, 0, 0, 0, 0];
        public var marginU:Array = [
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED];
        public var padV:Array = [0, 0, 0, 0, 0, 0, 0, 0, 0];
        public var padU:Array = [
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED];
        public var borderV:Array = [0, 0, 0, 0, 0, 0, 0, 0, 0];
        public var borderU:Array = [
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED];
        public var insetV:Array = [0, 0, 0, 0, 0, 0, 0, 0, 0];
        public var insetU:Array = [
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED];

        // Gap, split by gutter (GUTTER_COLUMN / GUTTER_ROW / GUTTER_ALL). A row
        // container uses the column gap on its main axis, a column container
        // the row gap; that is why case b (column, row-gap=10) is correct.
        public var gapV:Array = [0, 0, 0];
        public var gapU:Array = [
            LayoutConstants.UNIT_UNDEFINED, LayoutConstants.UNIT_UNDEFINED,
            LayoutConstants.UNIT_UNDEFINED];

        public var flexWrap:int = LayoutConstants.WRAP_NO_WRAP;
        public var justifyContent:int = LayoutConstants.JUSTIFY_FLEX_START;
        public var alignItems:int = LayoutConstants.ALIGN_STRETCH;
        public var alignSelf:int = LayoutConstants.ALIGN_AUTO;
        public var alignContent:int = LayoutConstants.ALIGN_FLEX_START;
        public var positionType:int = LayoutConstants.POSITION_RELATIVE;
        public var overflow:int = LayoutConstants.OVERFLOW_VISIBLE;

        // The engine default is BORDER_BOX (matching Yoga), the opposite of
        // CSS. An explicit width/height is a border-box size unless the author
        // asks for content-box.
        public var boxSizing:int = LayoutConstants.BOX_SIZING_BORDER_BOX;

        public var parent:As3LayoutNode = null;
        public var children:Array = [];

        // Computed border-box rectangle, relative to the parent's border box.
        public var left:Number = 0;
        public var top:Number = 0;
        public var width:Number = 0;
        public var height:Number = 0;

        // Intrinsic (max-content) CONTENT-box sizes from a measure pass, used
        // only when this node's own size is auto. Filled by As3LayoutEngine.
        public var iContentW:Number = 0;
        public var iContentH:Number = 0;

        public function As3LayoutNode() { }

        public function isRow():Boolean
        {
            return flexDirection == LayoutConstants.FLEX_DIR_ROW
                || flexDirection == LayoutConstants.FLEX_DIR_ROW_REVERSE;
        }

        public function isRowReverse():Boolean
        {
            return flexDirection == LayoutConstants.FLEX_DIR_ROW_REVERSE;
        }

        public function isColumnReverse():Boolean
        {
            return flexDirection == LayoutConstants.FLEX_DIR_COLUMN_REVERSE;
        }

        // ---- physical-edge resolution ------------------------------------
        //
        // Which slot wins for a physical edge, given the layout direction. This
        // is Style::computeLeftEdge / computeRightEdge / computeTopEdge /
        // computeBottomEdge verbatim: a START/END slot shadows the physical one,
        // and START means "left" in LTR but "right" in RTL. If NO slot is
        // defined the function returns -1 (Yoga's "undefined handle").
        public function pickSlot(v:Array, u:Array, phys:int, dir:int):int
        {
            if (phys == LayoutConstants.EDGE_LEFT)
            {
                if (dir == LayoutConstants.DIR_LTR && u[LayoutConstants.EDGE_START] != LayoutConstants.UNIT_UNDEFINED) return LayoutConstants.EDGE_START;
                if (dir == LayoutConstants.DIR_RTL && u[LayoutConstants.EDGE_END] != LayoutConstants.UNIT_UNDEFINED) return LayoutConstants.EDGE_END;
                if (u[LayoutConstants.EDGE_LEFT] != LayoutConstants.UNIT_UNDEFINED) return LayoutConstants.EDGE_LEFT;
                if (u[LayoutConstants.EDGE_HORIZONTAL] != LayoutConstants.UNIT_UNDEFINED) return LayoutConstants.EDGE_HORIZONTAL;
            }
            else if (phys == LayoutConstants.EDGE_RIGHT)
            {
                if (dir == LayoutConstants.DIR_LTR && u[LayoutConstants.EDGE_END] != LayoutConstants.UNIT_UNDEFINED) return LayoutConstants.EDGE_END;
                if (dir == LayoutConstants.DIR_RTL && u[LayoutConstants.EDGE_START] != LayoutConstants.UNIT_UNDEFINED) return LayoutConstants.EDGE_START;
                if (u[LayoutConstants.EDGE_RIGHT] != LayoutConstants.UNIT_UNDEFINED) return LayoutConstants.EDGE_RIGHT;
                if (u[LayoutConstants.EDGE_HORIZONTAL] != LayoutConstants.UNIT_UNDEFINED) return LayoutConstants.EDGE_HORIZONTAL;
            }
            else if (phys == LayoutConstants.EDGE_TOP)
            {
                if (u[LayoutConstants.EDGE_TOP] != LayoutConstants.UNIT_UNDEFINED) return LayoutConstants.EDGE_TOP;
                if (u[LayoutConstants.EDGE_VERTICAL] != LayoutConstants.UNIT_UNDEFINED) return LayoutConstants.EDGE_VERTICAL;
            }
            else
            {
                if (u[LayoutConstants.EDGE_BOTTOM] != LayoutConstants.UNIT_UNDEFINED) return LayoutConstants.EDGE_BOTTOM;
                if (u[LayoutConstants.EDGE_VERTICAL] != LayoutConstants.UNIT_UNDEFINED) return LayoutConstants.EDGE_VERTICAL;
            }
            if (u[LayoutConstants.EDGE_ALL] != LayoutConstants.UNIT_UNDEFINED) return LayoutConstants.EDGE_ALL;
            return -1;
        }

        // Resolve a physical edge against `basis` (the containing block's inner
        // width for padding/margin/gap -- CSS percentages always resolve on the
        // inline size -- or the owner height for a vertical inset). Undefined
        // slots and auto resolve to 0, matching Style::resolve(...).unwrap(0).
        public function edgeValue(v:Array, u:Array, phys:int, dir:int, basis:Number):Number
        {
            return slotValue(v, u, pickSlot(v, u, phys, dir), basis);
        }

        public function edgeDefined(v:Array, u:Array, phys:int, dir:int):Boolean
        {
            return pickSlot(v, u, phys, dir) >= 0;
        }

        public function slotValue(v:Array, u:Array, slot:int, basis:Number):Number
        {
            if (slot < 0) return 0;
            var unit:int = u[slot];
            var val:Number = v[slot];
            if (unit == LayoutConstants.UNIT_POINT) return val;
            if (unit == LayoutConstants.UNIT_PERCENT)
            {
                if (isNaN(basis)) return 0;
                return basis * val / 100;   // seam keeps percentages as 0..100
            }
            return 0;   // AUTO / UNDEFINED / ... resolve to 0
        }

        // The gap on an axis: a row container consumes the column gap, a column
        // container the row gap (Style::computeGapForAxis).
        public function gapForAxis(isMainRow:Boolean, basis:Number):Number
        {
            var slot:int = isMainRow ? LayoutConstants.GUTTER_COLUMN : LayoutConstants.GUTTER_ROW;
            return gapValue(slot, basis);
        }

        public function gapValue(slot:int, basis:Number):Number
        {
            return slotValue(gapV, gapU, slot, basis);
        }
    }
}
