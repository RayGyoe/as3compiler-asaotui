// asaot.ui.InputConstants -- the ONE place the touch thresholds live (MOBILE.md 6.2).
//
// A literal repeated in five widgets is a number nobody can change and nothing can
// check; every value here is also the DEFAULT of a descriptor field, so an author can
// override it per control without editing the library.
//
// NOT MEASURED ON A DEVICE. The three timing/slop numbers come from the NSH docs and
// the platform conventions they cite (see MOBILE.md section 10); this workspace has no
// touch backend to feel them (G5: the window backend produces no TouchEvent at all).
// They are defaults, not findings -- do not quote them as measurements.
package asaot.ui
{
    public class InputConstants
    {
        // Press-down inside a SCROLLER waits this long. The same touch is either a press
        // (tap the row) or the start of a drag (scroll the list), and the drag must win
        // without ever showing a pressed state.
        public static const PRESS_DELAY_MS:int = 130;

        // Held without leaving the slop for this long, the touch is a long press; the
        // release then does NOT count as a tap.
        public static const LONG_PRESS_MS:int = 500;

        // Moving further than this from the press anchor cancels the press: a finger is
        // never perfectly still, and a 1pt wobble must not eat a tap.
        public static const PRESS_SLOP_PT:Number = 8;

        // iOS HIG says 44pt, Material says 48dp; take the smaller of the two, because a
        // bigger floor silently rewrites layouts that were measured against 44.
        public static const MIN_HIT_PT:Number = 44;

        // A release only becomes a FLING above this speed (px per millisecond).
        // 0.05 px/ms is 300 px/s: slower than that and the finger was placing the
        // content, not throwing it -- a 1px nudge must not start a glide.
        public static const FLING_MIN_PT_PER_MS:Number = 0.05;

        // The glide STOPS below this speed (px per millisecond). 0.02 px/ms is
        // ~20 px/s: at that point the remaining travel is under a pixel per frame and
        // every further step would be a repaint that no eye can see.
        public static const FLING_STOP_PT_PER_MS:Number = 0.02;

        // The frame the deceleration table is quoted against (60 Hz). Used as the
        // DENOMINATOR of the dt correction, never as an assumed frame length: the
        // glide integrates wall-clock milliseconds (S2), so a 120 Hz window and a
        // stalled frame both land in the same place.
        public static const FLING_FRAME_MS:Number = 16.667;

        // Overscroll resistance (MOBILE.md S3). The rubber-band curve is the iOS one,
        // f(x) = (x * dim * c) / (dim + c * x): the stretch rises fast and then flattens
        // with an asymptote at the viewport dimension, so a finger gets the message
        // "there is nothing more here" without dragging the pane off-screen. 0.55 is
        // the constant every UIKit clone copies; it is a CONVENTION, not a measurement
        // (this workspace has no touch backend to feel it -- G5).
        public static const OVERSCROLL_RESIST:Number = 0.55;

        // How much of the bounce is left after ONE 60Hz frame. Corrected for the real
        // frame time exactly like the glide (S2), so a 120Hz window returns in the same
        // WALL-CLOCK time. 0.72 puts a 47px bounce back on the wall in ~230ms.
        public static const SPRING_RATE:Number = 0.72;

        // The bounce is over below this distance (px). M1's acceptance is "回位误差 <
        // 1pt"; stopping at half a pixel and writing EXACTLY zero makes the error zero
        // rather than "less than one". An exponential decay never reaches zero on its
        // own, so without a floor the spring would repaint forever.
        public static const SPRING_STOP_PX:Number = 0.5;

        // A velocity sample older than this is not a flick. A finger that stops for a
        // few frames and then lifts was PLACING the content; treating its stale speed
        // as a throw makes a list coast away under a user who thought they had stopped.
        public static const FLING_FRESH_MS:Number = 60;

        // OUR OWN EVENT TYPE, not TouchEvent.TOUCH_CANCEL: the AIR 3.0 class in this
        // runtime declares TOUCH_BEGIN/MOVE/END/OVER/OUT/ROLL_OVER/ROLL_OUT/TAP and no
        // cancel constant, while a platform can always revoke a touch series (incoming
        // call, gesture takeover). Keeping the string here lets the arm that cannot
        // produce it still compile.
        public static const TOUCH_CANCEL:String = "touchCancel";
    }
}
