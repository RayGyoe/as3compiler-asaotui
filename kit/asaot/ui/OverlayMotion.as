// asaot.ui.OverlayMotion -- the entrance animation of a floating surface.
//
// WHY NOT `anim/Anim`: Anim re-aims a resolved STYLE field (opacity / background /
// borderColor) and is driven from `UiNode.resolveStyle`. An overlay's entrance is
// not a style change -- the style is identical before and after, the node only has
// to LOOK like it is arriving -- and forcing it through a resolve would mean writing
// a fake `previous` opacity, which the next real resolve would then fight. So this
// is a second, much smaller mechanism: wall time, display-object level, owned by the
// surface that is opening.
//
// THE POSITION IS RECOMPUTED FROM THE ENGINE, NEVER ACCUMULATED. The moving object's
// local offset comes from `engine.layoutGet(...)` on every frame of the entrance, and
// the animation writes `solved + delta*(1-ease)`. This matters: the first version
// stored the base offset once, on the first animated frame, and it went wrong the
// moment the base was stale -- the probe caught a toast parked 100px too high
// because its base had been captured on the 560x460 fallback solve and the window
// then re-solved to 760x560. Reading the engine each frame is exact, survives a
// resize mid-entrance, and leaves nothing to clear afterwards.
//
// WALL TIME, ALWAYS. `getTimer()` is monotonic ms since start (see View.tick for why
// frame counting is wrong). The tween is (now - t0) / MS with an ease-out, clamped:
// a late frame lands at exactly 1 and never overshoots.
//
// STEADY STATE IS A NO-OP. Once the entrance lands, `T0` is cleared and both entry
// points return without touching anything -- so a settled overlay still repaints
// nothing (the invariant UiApp's steady-frame counters pin).
//
// NOTE ON HIT TESTING DURING THE ENTRANCE: `absX/absY` keep the SOLVED rect while the
// backing is offset by a few px. For 140ms a click on the outermost few pixels of an
// opening panel could miss. Making the solve follow the animation would mean
// re-solving layout every frame of it -- the one thing the three-pass design refuses
// to do for decoration.
package asaot.ui
{
    import flash.utils.getTimer;

    public final class OverlayMotion
    {
        public static const MS:int = 140;

        private static const T0:String = "mt0";

        // Arm the entrance. Called from `payload` on the frame `open` flips true.
        //
        // NO FRAME CLOCK, NO ENTRANCE -- and the reason is not a nicety. The tween is
        // WALL time, and it lands only because frames keep coming. A surface that is
        // already open on the app's very first frame (an initial state, or a page that
        // mounts a dialog) has nothing to arrive FROM, and an app that pumps its frames
        // by hand (the gallery tour calls reflow() in a loop, so ~0 ms of wall time
        // separates them) would capture it at t=0: the six-page tour's page-5
        // screenshot came out as a 3%-opaque dialog over its own scrim, and every rect
        // in the tour was still perfect. So: no elapsed frames yet means no entrance.
        public static function start(n:UiNode):void
        {
            if (n == null || n.extra == null) return;
            if (n.app == null || n.app.enterFrameTicks <= 0) return;
            n.extra[T0] = getTimer();
        }

        public static function isRunning(n:UiNode):Boolean
        {
            return n != null && n.extra != null && n.extra[T0] != null;
        }

        // Called from `arrange` of the opening kind, AFTER the node's own children
        // have been arranged (i.e. from the LAST arrange of the surface), and from
        // `paint` -- both are idempotent and both read the engine for the base, so a
        // layout frame and a paint-only frame produce the same picture.
        //
        // `fade` may be null (skip the alpha ramp) and so may `move`.
        public static function apply(n:UiNode, fade:UiNode, move:UiNode,
                                     dx:Number, dy:Number):void
        {
            if (n == null || n.extra == null) return;
            var t0:Object = n.extra[T0];
            if (t0 == null) return;
            if (n.app == null) { n.extra[T0] = null; return; }

            var t:Number = (getTimer() - Number(t0)) / MS;
            if (t < 0) t = 0;
            if (t > 1) t = 1;
            // Ease-out quad: 1 - (1-t)^2. Fast arrival, soft landing.
            var e:Number = 1 - (1 - t) * (1 - t);
            var keep:Number = 1 - e;

            if (move != null && move.backing != null && move.engineNode != null)
            {
                var out:Array = n.app.rectScratch;
                n.app.engine.layoutGet(move.engineNode, out);
                move.backing.x = out[0] + dx * keep;
                move.backing.y = out[1] + dy * keep;
            }
            if (fade != null && fade.backing != null)
            {
                var base:Number = isNaN(fade.resolved.opacity) ? 1.0 : fade.resolved.opacity;
                fade.backing.alpha = base * e;
            }

            if (t >= 1)
            {
                n.extra[T0] = null;
                return;
            }
            // Ask for the next frame. `markPaint` is the documented "repaint me"
            // signal and it never re-solves (design doc 3.3).
            n.app.markPaint(n);
        }

        public function OverlayMotion() { }
    }
}
