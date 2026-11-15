// asaot.ui.anim.Motion -- the single motion-discipline table.
//
// TWO JOBS, ONE PLACE (theme-tokens-vs-cui.md §2.4):
//   1. ONE TASK, ONE DURATION. Every named animation duration lives here. A widget
//      that invents its own `250` is a visible diff against this table, not a silent
//      drift. The two overlay numbers are the shipped values (140 enter / 120 exit);
//      they are NOT re-tuned here -- moving them would break the pixel pins.
//   2. A GLOBAL reduced-motion PATH. `reducedMotion` is the opt-in switch a host sets
//      (e.g. from the OS "reduce motion" preference). When true, every mechanism that
//      consults it lands on the FINAL state immediately -- it does not delete the
//      feedback, it removes the travel. Default false keeps today's pixels byte-for-byte.
//
// WHY A SEPARATE CLASS, NOT A FLAG ON Anim: Anim is the per-field tween core and
// OverlayMotion is the display-object entrance; both must honour the SAME switch and
// the SAME durations. Putting the discipline in one neutral place keeps the two
// mechanisms from drifting apart (one honouring reduced-motion, the other not).
package asaot.ui.anim
{
    public final class Motion
    {
        // Opt-in global switch. false = ship behaviour. A host may set this once at
        // startup from the platform preference; nothing in the kit sets it implicitly.
        public static var reducedMotion:Boolean = false;

        // ---- the duration table (one task, one duration) ---------------------
        // Floating-surface entrance / exit. Exit is faster than entrance: something
        // leaving should not make the author wait for it.
        public static const OVERLAY_ENTER_MS:int = 140;
        public static const OVERLAY_EXIT_MS:int = 120;

        // Small state feedback (checkbox / switch reporting a new state). Kept short
        // and non-bouncy: reporting a state lands, it does not spring.
        public static const STATE_MS:int = 180;
        // Hover colour blend.
        public static const HOVER_MS:int = 140;
        // Expand / collapse of a tree or accordion row (no overshoot).
        public static const EXPAND_MS:int = 320;
        // A row following the pointer / keyboard.
        public static const ROW_MS:int = 100;

        public function Motion() { }
    }
}