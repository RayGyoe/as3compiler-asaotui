// asaot.ui.Widget -- the per-kind behaviour contract of a retained UiNode.
//
// WHY THIS EXISTS
// ---------------
// `UiNode` is kind-agnostic plumbing: identity, the three passes, dirty bits,
// hover/press bookkeeping, display-order repair. Everything that DIFFERS
// between a button and a checkbox (what display objects it owns, how it is
// measured, how its inner parts are placed, what it draws, what a click does)
// lives behind this interface, one implementation per file under `kind/`.
//
// Before this seam, all of it was an `if (kind == "...")` chain inside
// UiNode.as at five separate sites, so adding a widget meant editing a 750-line
// file five times. That is exactly the "single file carrying several unrelated
// responsibilities" AGENTS.md section 2.8 tells us to split.
//
// REGISTRATION
// ------------
// A widget Node class registers its implementation once, from its constructor
// (see `Widgets.register`). `UiNode` then looks it up by `kind` and THROWS if it
// is missing -- an unregistered widget must be a loud failure, never a silently
// invisible control (AGENTS.md section 2.5).
//
// THE FIVE HOOKS MAP 1:1 TO THE PIPELINE
// --------------------------------------
//   build   -- structure time only: create the backing's display objects
//   measure -- pass 1 (intrinsic size; writes n.state.measuredW/H)
//   arrange -- pass 2 (place the inner display objects inside the solved rect)
//   paint   -- pass 3 (draw; must be cheap and allocation-free)
//   click   -- input: return true if this widget consumed the click
package asaot.ui
{
    public interface Widget
    {
        // Structure time. The backing Sprite already exists; add display objects
        // to it in the order they should be layered (lowest first).
        function build(n:UiNode):void;

        // Payload mirroring, called by the reconciler EVERY frame with the fresh
        // description node. Copy whatever this kind mirrors onto the node, and
        // return true when the change forces a RE-MEASURE (a layout change).
        // The generic role/ariaName/visible are already copied by UiNode.
        // Read kind-specific fields by casting `desc` to this kind's Node class;
        // remember last-seen values on `n.extra` so a per-frame reconcile does not
        // reflow (or allocate) when nothing actually changed.
        function payload(n:UiNode, desc:Node):Boolean;

        // Does this kind want MOUSE_DOWN/MOUSE_UP press tracking on its backing?
        // (Purely visual: press never reflows.)
        function wantsPress():Boolean;

        // Pass 1. May assume n.engineNode != null; n.resolved is current.
        function measure(n:UiNode):void;

        // Pass 2. n.absX/absY/absW/absH and n.backing.x/y are already set.
        function arrange(n:UiNode):void;

        // Pass 3. Must not allocate GC objects in steady state.
        function paint(n:UiNode):void;

        // Input. Return true when the widget handled the click itself (and thus
        // n.onClick should NOT also fire).
        function click(n:UiNode):Boolean;
    }
}