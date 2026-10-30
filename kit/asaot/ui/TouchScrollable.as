// asaot.ui.TouchScrollable -- a viewport a finger can DRAG (MOBILE.md S1/S2).
//
// WHY THIS IS AN INTERFACE AND NOT A KIND CHECK. Press routing already asks "is this
// node inside a scroller?" by kind, and says why: the library has exactly one scroll
// container. A drag needs more than a yes/no, though -- it needs three calls at three
// moments, and a hard cast to ScrollViewWidget would put the router's compile unit in
// the business of one widget. This interface is the same shape as WidgetKeys /
// WidgetFocus / WidgetTeardown: an OPTIONAL capability a kind may implement, resolved
// through the kind registry (`Widgets.require(n.kind)`).
//
// COORDINATES ARE ROOT (STAGE) SPACE, the same ones `Pointer` carries. The widget
// converts to its own box internally, so a router never has to know about transforms,
// and a nested viewport (a scroller inside a scroller) works without special cases.
//
// WHAT THE ROUTER OWES THE IMPLEMENTATION: `touchDragBegin` once, `touchDragTo` for
// every move while it owns the series, then exactly ONE of `touchDragEnd` /
// `touchDragCancel`. A cancelled series means the platform took the touch away (an
// incoming call, a gesture takeover): the widget must NOT start momentum from it.
package asaot.ui
{
    public interface TouchScrollable
    {
        // A finger went DOWN inside this viewport. Not yet a drag (it may be a tap, or the
        // start of one), but a coasting list has to stop HERE: on every mobile platform
        // touching a list that is still gliding stops it, and waiting for the press delay
        // or the slop would let it keep sliding under a finger that is already down.
        function touchPress(n:UiNode):void;

        // The press became a drag: anchor here. `x`/`y` are the point where the finger
        // left the press slop (the offset arithmetic starts there); `originX`/`originY`
        // are where the finger went DOWN, which is the only sample that can say which
        // AXIS the gesture is on. Called AFTER the router has withdrawn the press (a
        // dragged row must not stay painted pressed, and must not click).
        function touchDragBegin(n:UiNode, x:Number, y:Number, originX:Number, originY:Number):void;

        // 1:1 follow of the pointer. `x`/`y` are root coordinates of the touch that
        // the router has already decided is a drag (it has left the press slop).
        function touchDragTo(n:UiNode, x:Number, y:Number):void;

        // The finger lifted. The widget may start momentum from the velocity it
        // measured itself while following (the router deliberately keeps no clock:
        // the sample interval that matters is the one between finger positions).
        function touchDragEnd(n:UiNode, x:Number, y:Number):void;

        // The platform revoked the series. No click and NO momentum: whoever took the
        // touch over owns what happens next.
        function touchDragCancel(n:UiNode):void;
    }
}
