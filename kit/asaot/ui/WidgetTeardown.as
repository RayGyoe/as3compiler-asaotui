// asaot.ui.WidgetTeardown -- the OPTIONAL per-kind teardown hook.
//
// WHY A SECOND INTERFACE AND NOT A SIXTH METHOD ON `Widget`: `Widget` is the
// published per-kind contract (CONTRIBUTING-widget.md section 4). Adding a method
// there would touch all ~30 kind classes to implement a no-op, and every third
// party kind with it. A separate interface says what is true -- almost no widget
// owns anything outside its node -- and `UiNode.destroySubtree` asks for it with
// one `is` test.
//
// WHEN IT IS CALLED: from `UiNode.destroySubtree`, BEFORE the node's scratch bag
// (`n.extra`), `n.app`, `n.backing` and `n.shapeA` are nulled. So a teardown may
// still read everything it stored, and it MUST NOT keep the node afterwards.
//
// WHO NEEDS IT (both found by the six-page gallery demo, which is the first
// program that creates an overlay tree and then TEARS IT DOWN while the app keeps
// running):
//   * PopoverWidget -- the outside-close CLICK listener lives on the STAGE, so it
//     outlives the node. A destroyed menu therefore kept a listener that
//     dereferenced `n.extra`, and the next click anywhere in the window threw
//     #1009 (the gallery's tab click, one frame after page 5 went away).
//   * ToastWidget -- a pending `setTimeout` holds the node too, and would fire
//     `onClose` on a torn-down toast.
package asaot.ui
{
    public interface WidgetTeardown
    {
        // Release everything this node's widget attached OUTSIDE the node.
        // Idempotent: the same node is never torn down twice, but a kind that
        // already cleared its timer must not fail if it is.
        function teardown(n:UiNode):void;
    }
}