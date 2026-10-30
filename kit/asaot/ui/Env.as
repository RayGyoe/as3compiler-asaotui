// asaot.ui.Env -- the platform facts a layout must not GUESS (MOBILE.md 6.3).
//
// WHY THIS EXISTS
// ---------------
// The kit can draw a status-bar-clear page only if someone tells it how tall the
// status bar is, and it can decide whether the 103 `hover` branches in the kinds
// are worth running only if someone says whether the pointer can hover at all.
// Both answers are PLATFORM facts, and the library's rule is that platform facts
// arrive through ONE interface and are consumed in ONE place -- not as a
// `hasHover` test inside every widget, and not as a safe-area insets sprinkled
// through the engine.
//
// READ, THEN SUBSCRIBE. Every value is a plain getter, so a consumer that only
// needs the current number (a measure, a one-off padding) never has to hold a
// subscription. A consumer that has to REACT (UiApp) subscribes, and the
// notification channel is the SAME `Observable`/`Subscription` pair the data flow
// already uses -- no second event vocabulary, no EventDispatcher allocation per
// change.
//
// WHAT A BACKEND MAY NOT DO: change this interface. The desktop implementation
// (DesktopEnv) answers with zeros/false because a desktop window has no notch and
// a mouse always hovers; an iOS/Android shell overrides the VALUES and leaves the
// shape alone. That is the whole point of the split -- see MOBILE.md `B9`, which
// is where the real numbers have to come from.
package asaot.ui
{
    import asaot.ui.style.Edges;

    import flash.geom.Rectangle;

    public interface Env
    {
        // The insets the platform wants left clear, in LOGICAL POINTS, on the four
        // sides. All zero on a desktop window; (47, 0, 34, 0) on a modern iPhone.
        // Consumed as PADDING on a container that asks for it (MOBILE.md E2), never
        // scattered through the engine.
        function get safeArea():Edges;

        // The soft keyboard's rectangle in SCREEN coordinates; a zero-size rect
        // while the keyboard is down. Not consumed by the kit yet (MOBILE.md S7,
        // "scroll the focused field into view") -- the value is delivered so the
        // consumer can be written against a real interface rather than a stub.
        function get keyboardRect():Rectangle;

        // Physical pixels per logical point, for anything that must stay crisp.
        // NOT a layout input: layout is always in logical points.
        function get pixelRatio():Number;

        // Is there a TOUCH input source, and is there a HOVERING one? They are two
        // different questions (a touch-screen laptop answers true to both). The
        // hover answer is the one with teeth: `UiApp.setHasHover` is the single
        // verdict behind every `hover` branch in the kit.
        function get hasTouch():Boolean;
        function get hasHover():Boolean;

        // "Cut the animation" for accessibility. The kit's animator is not yet
        // wired to it (MOBILE.md E8); the value is delivered here.
        function get reduceMotion():Boolean;

        // "active" | "inactive" | "background". Currently DELIVERED, not consumed:
        // stopping the frame pump while backgrounded is MOBILE.md E7.
        function get appState():String;

        // The system appearance, so a dark-mode app can follow the OS instead of
        // its own switch (MOBILE.md E5).
        function get isDark():Boolean;

        // BCP-47-ish locale of the user ("zh-CN"). Delivered; RTL/locale-aware
        // layout is MOBILE.md E6.
        function get locale():String;

        // Called synchronously, once per change, in registration order. The int is
        // a `Dirty` bit; today every producer sends Dirty.VALUE ("an environment
        // value changed") and no consumer branches on it.
        function subscribe(listener:Function):Subscription;

        // The mirror of subscribe; `Subscription.cancel()` calls it, so an author
        // normally cancels the handle instead.
        function unsubscribe(s:Subscription):void;
    }
}
