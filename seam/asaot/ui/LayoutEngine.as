// asaot.ui.LayoutEngine -- the layout seam, expressed as a PURE AS3 INTERFACE.
//
// WHY AN INTERFACE (and not a C function seam at the AS3 edge)
// ------------------------------------------------------------
// AS3 has no FFI (docs/zh-cn/enhancements.md E11, un-scheduled), so a plain
// `asaot.ui.*` .as source cannot call a host C function. The only way to reach
// native code from AS3 is a BUILT-IN class emitted by `src/emit.ts`. But if the
// seam itself is a pure AS3 interface, then the widget layer depends only on
// the interface, and:
//
//   * the whole library (NodeTree, Style, controls, AND the AS3 layout engine)
//     is plain AS3 that mxmlc can compile and `adl` can run -> we get the
//     "same .as source, mxmlc->adl vs our AOT->native" two-sided lever; and
//   * the native path is one implementation of this interface, emitted as a
//     built-in that `implements` it (NativeLayoutEngine; see
//     native/NativeLayoutEngine.as.doc).
//
// TWO IMPLEMENTATIONS, ONE INTERFACE
// ----------------------------------
//   * As3LayoutEngine   -- pure AS3 flexbox (a minimal skeleton, adl-runnable)
//   * NativeLayoutEngine -- a built-in class forwarding to as_ui_yg_* -> Yoga
// `UiApp` picks the native one when it is linked, else falls back to the AS3 one
// (see seam/README.md). Because both are selected through THIS interface, the
// two must agree: the differential test in README.md is a hard requirement.
//
// LAYOUT IS AN ENHANCEMENT, NOT AN AIR FEATURE
// --------------------------------------------
// AIR has no flexbox concept at all, so layout's reference is NOT `adl`: it is
// the W3C flexbox spec / a browser (Yoga is implemented to the web standard).
// `adl` is used to check the AS3 orchestration and the pure-AS3 engine, not the
// layout numbers. This does not violate AGENTS.md section 1.5: layout is an
// enhancement with no AIR counterpart, hence no AIR reference exists.
//
// METHOD SET
// ----------
// The methods mirror, 1:1, the capabilities of the 30 `as_ui_yg_*` functions in
// `u1-prototype/yoga_glue.h` (the authoritative opaque C seam). Each method
// carries a `// <-> as_ui_yg_*` note. Node and config handles are opaque
// `Object`s, exactly as the C seam keeps the node an opaque `void*`.
package asaot.ui
{
    public interface LayoutEngine
    {
        // ---- Config -------------------------------------------------------
        // <-> as_ui_yg_config_new(point_scale, use_web_defaults)
        function createConfig(pointScale:Number, useWebDefaults:Boolean):Object;
        // <-> as_ui_yg_config_free
        function destroyConfig(cfg:Object):void;

        // ---- Node lifecycle ----------------------------------------------
        // <-> as_ui_yg_node_new(cfg)
        function createNode(cfg:Object):Object;
        // <-> as_ui_yg_node_free
        function destroyNode(node:Object):void;
        // <-> as_ui_yg_node_free_recursive
        function destroyNodeRecursive(node:Object):void;
        // <-> as_ui_yg_node_insert(parent, child, index)
        function insertChild(parent:Object, child:Object, index:int):void;
        // <-> as_ui_yg_node_remove(parent, child)
        function removeChild(parent:Object, child:Object):void;

        // ---- Style setters -----------------------------------------------
        // <-> as_ui_yg_set_flex_direction   (value: LayoutConstants.FLEX_DIR_*)
        function setFlexDirection(node:Object, direction:int):void;
        // <-> as_ui_yg_set_flex_wrap        (value: LayoutConstants.WRAP_*)
        function setFlexWrap(node:Object, wrap:int):void;
        // <-> as_ui_yg_set_justify          (value: LayoutConstants.JUSTIFY_*)
        function setJustifyContent(node:Object, justify:int):void;
        // <-> as_ui_yg_set_align_items      (value: LayoutConstants.ALIGN_*)
        function setAlignItems(node:Object, align:int):void;
        // <-> as_ui_yg_set_align_self       (value: LayoutConstants.ALIGN_*)
        function setAlignSelf(node:Object, align:int):void;
        // <-> as_ui_yg_set_align_content    (value: LayoutConstants.ALIGN_*)
        function setAlignContent(node:Object, align:int):void;
        // <-> as_ui_yg_set_flex(grow, shrink, basis, basis_unit)
        //    basis uses the (value, unit) trichotomy (LayoutConstants.UNIT_*).
        function setFlex(node:Object, grow:Number, shrink:Number, basis:Number, basisUnit:int):void;
        // <-> as_ui_yg_set_size(axis, value, unit)   (axis: LayoutConstants.AXIS_*)
        function setSize(node:Object, axis:int, value:Number, unit:int):void;
        // <-> as_ui_yg_set_minmax(axis, is_max, value, unit)
        function setMinMax(node:Object, axis:int, isMax:Boolean, value:Number, unit:int):void;
        // <-> as_ui_yg_set_margin(edge, value, unit)  (edge: LayoutConstants.EDGE_*)
        function setMargin(node:Object, edge:int, value:Number, unit:int):void;
        // <-> as_ui_yg_set_padding(edge, value, unit)
        function setPadding(node:Object, edge:int, value:Number, unit:int):void;
        // <-> as_ui_yg_set_border(edge, value)   (points only)
        function setBorder(node:Object, edge:int, value:Number):void;
        // <-> as_ui_yg_set_gap(gutter, value, unit)   (gutter: LayoutConstants.GUTTER_*)
        function setGap(node:Object, gutter:int, value:Number, unit:int):void;
        // <-> as_ui_yg_set_position(edge, value, unit)  (inset; needs absolute/relative)
        function setPosition(node:Object, edge:int, value:Number, unit:int):void;
        // <-> as_ui_yg_set_position_type   (value: LayoutConstants.POSITION_*)
        function setPositionType(node:Object, positionType:int):void;
        // <-> as_ui_yg_set_display         (value: LayoutConstants.DISPLAY_*)
        function setDisplay(node:Object, display:int):void;
        // <-> as_ui_yg_set_overflow        (value: LayoutConstants.OVERFLOW_*)
        function setOverflow(node:Object, overflow:int):void;
        // <-> as_ui_yg_set_aspect_ratio(ratio)   (ratio <= 0 clears it)
        function setAspectRatio(node:Object, ratio:Number):void;
        // <-> as_ui_yg_set_box_sizing      (value: LayoutConstants.BOX_SIZING_*)
        function setBoxSizing(node:Object, boxSizing:int):void;

        // ---- Measure callback (intrinsic sizing: text, images) -----------
        // <-> as_ui_yg_set_measure(fn, ctx). `measure` may be null to clear it.
        // The AS3 callback shape mirrors the C one:
        //   function m(ctx:Object, aw:Number, wMode:int, ah:Number, hMode:int, out:Array):void
        // writing out[0]=width, out[1]=height. `ctx` is the object passed here.
        function setMeasure(node:Object, measure:Function, ctx:Object):void;

        // ---- Compute / query ---------------------------------------------
        // <-> as_ui_yg_calculate(availableWidth, availableHeight, direction)
        //    If an axis is unconstrained, pass NaN on that axis (never a large
        //    number: that would STRETCH an auto-sized root instead of letting it
        //    shrink-wrap -- see u1-prototype/check-layout.md case f).
        function calculate(node:Object, availableWidth:Number, availableHeight:Number, direction:int):void;
        // <-> as_ui_yg_set_dirty
        function setDirty(node:Object):void;
        // <-> as_ui_yg_layout_get(out[4])
        //    Writes out[0]=left, out[1]=top, out[2]=width, out[3]=height, all
        //    relative to the parent. A null node writes all four as 0.
        function layoutGet(node:Object, out:Array):void;
    }
}
