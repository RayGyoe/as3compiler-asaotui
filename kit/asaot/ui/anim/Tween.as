// asaot.ui.anim.Tween -- one in-flight tween record: (node, field) -> numbers.
//
// ALLOCATED ONLY WHEN A TWEEN STARTS (Anim.retarget), never per frame. The node
// owns at most one record per field, held in its AnimState; when a field is
// retargeted mid-flight the SAME record is rewritten in place, so a steady
// animation allocates nothing (AGENTS.md memory rule).
//
// `done` is the "landed, but painted once more" latch: the frame the tween
// reaches its target writes the EXACT target into `cur` and applies it, and the
// caller repaints that frame; the next `advance` removes the record. Without
// this extra frame the last paint would show the previous (not exact) step.
package asaot.ui.anim
{
    import asaot.ui.UiNode;

    public class Tween
    {
        public var node:UiNode;
        public var field:String;
        public var from:Number;
        public var to:Number;
        public var cur:Number;
        public var startMs:Number;
        public var durMs:Number;
        public var ease:String;
        public var active:Boolean;
        public var done:Boolean;

        public function Tween():void
        {
            this.node = null;
            this.field = null;
            this.from = 0;
            this.to = 0;
            this.cur = 0;
            this.startMs = 0;
            this.durMs = 1;
            this.ease = "linear";
            this.active = false;
            this.done = false;
        }
    }
}