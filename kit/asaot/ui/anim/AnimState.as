// asaot.ui.anim.AnimState -- the per-(node) tween bag, stored in `UiNode.extra`.
//
// One bag per node, created lazily by Anim the first time that node starts a
// tween, so a node that never animates carries no animation state at all. It
// holds:
//   * `tweens` -- field name -> Tween (at most one live record per field);
//   * `list`   -- every record ever created for this node, so `clear` can drop
//                 them from the global active list without a `for-in` walk;
//   * `bgFill` -- a node-OWNED Fill for the background tween. The resolved
//                 Style's `background` is a SHARED reference (it aliases the
//                 author's style constant and the theme baseline), so mutating it
//                 would corrupt every node sharing that style. We therefore copy
//                 the packed colour into an owned Fill and hand THAT back to
//                 `resolved.background` while the background is animating.
package asaot.ui.anim
{
    import asaot.ui.style.Fill;

    public class AnimState
    {
        public var tweens:Object;
        public var list:Array;
        public var bgFill:Fill;

        public function AnimState():void
        {
            this.tweens = {};
            this.list = [];
            this.bgFill = null;
        }
    }
}