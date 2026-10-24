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
//   * `corners` / `sizeOwned` / `padOwned` -- the same argument for the composite
//                 fields the layout/paint tweens write: `resolved.cornerRadii`, and
//                 a refined `resolved.size` / `resolved.padding`, are shared with
//                 the theme baseline or the parent's resolved Style (see
//                 Style.mergeSize/mergeEdges: an unset component returns the PARENT's
//                 object). Writing an interpolated number into a shared object would
//                 animate every node that shares it, so each animated node owns its
//                 copies and re-points `resolved` at them while a tween is live.
//                 Nothing here exists until a tween actually starts.
package asaot.ui.anim
{
    import asaot.ui.style.Corners;
    import asaot.ui.style.Edges;
    import asaot.ui.style.Fill;
    import asaot.ui.style.Size;

    public class AnimState
    {
        public var tweens:Object;
        public var list:Array;
        public var bgFill:Fill;
        public var corners:Corners;
        public var sizeOwned:Size;
        public var padOwned:Edges;

        public function AnimState():void
        {
            this.tweens = {};
            this.list = [];
            this.bgFill = null;
            this.corners = null;
            this.sizeOwned = null;
            this.padOwned = null;
        }
    }
}