// asaot.ui.PointerRouter -- one touch series in, one normalized pointer out
// (MOBILE.md P1/P2/P5/P7).
//
// WHY THIS LIVES BESIDE UiApp AND NOT IN EACH WIDGET
// --------------------------------------------------
// There is no touch backend to feed this class yet (G5 in compiler-gaps.md: the window
// backend never dispatches a TouchEvent, SDL_FINGER is wired nowhere), so the ONLY touch
// sequences that exist today are ones a program synthesizes. That makes the router's job
// narrow and checkable: turn a touch series into the SAME press / move / release / click
// vocabulary the 41 existing kinds already speak, and do it with the press semantics a
// finger needs but a mouse does not (delay inside a scroller, slop, long press).
//
// THE COMPATIBILITY LAYER IS SYNTHETIC MOUSE EVENTS, AND IT IS HONEST ABOUT IT. The
// library's click path is `MouseEvent.CLICK` on the node's backing (UiNode.wirePointer),
// so a touch that produces the same events produces the same behaviour with zero
// control-side changes -- that is the whole point of doing it here instead of adding a
// `Pointer` parameter to every widget. The cost is recorded, not hidden: these events did
// not come from the engine, so the engine's own mouse state (`ASC_mouse_down`, its
// roll-over bookkeeping, its TextField focus-on-mouse-down) does not see them. UiApp
// compensates for hover and focus; anything else the engine does on a real mouse-down
// stays unmodelled, and `probes/widgets/pointer-touch` measures which of those the
// library actually depends on.
//
// WHAT A PRESS IS (MOBILE.md 6.2 defaults, all overridable per descriptor field)
//   * outside a scroller: press DOWN immediately -- a button must react on touch-down,
//     that is what "responsive" means;
//   * inside a scroller: wait PRESS_DELAY_MS first, because the same drag may be the
//     list scrolling, and a row that flashes pressed on every scroll is a bug;
//   * moving beyond PRESS_SLOP_PT cancels a waiting press (and a pending tap) -- a
//     finger is never still, and the scroller must win cleanly;
//   * held past LONG_PRESS_MS, the press is a long press; the release no longer taps.
//
// AND WHAT A DRAG IS (MOBILE.md S1). Once the finger leaves the slop inside a
// viewport, the touch stops being "a press that might become a tap" and becomes the
// viewport's: the press is withdrawn WITHOUT a click (a row must not click when the
// list was scrolled), and every later move is handed to the widget through
// TouchScrollable. Only a viewport can claim a series -- there is one scroll container
// today, and a widget that only has a press (a slider's thumb, say) keeps its own
// arithmetic, which is what every one of the 41 kinds already relies on.
package asaot.ui
{
    import flash.events.MouseEvent;
    import flash.events.TouchEvent;
    import flash.utils.Dictionary;
    import flash.utils.clearTimeout;
    import flash.utils.getTimer;
    import flash.utils.setTimeout;

    public class PointerRouter
    {
        private var app:UiApp;
        private var pointers:Dictionary;      // touch id -> Pointer (one instance per id)

        // The press THIS router is currently driving. Only one at a time: a tap needs one
        // target and one verdict, and multi-pointer arbitration (pinch, two-finger pan)
        // is deliberately not built yet (MOBILE.md P3 is a later milestone).
        private var press:Pointer;

        private var pending:Pointer;          // press waiting out the scroller delay
        private var pendingTimer:int;
        private var longTimer:int;

        // The pointer whose series a VIEWPORT now owns, and that viewport. Set the
        // moment the finger leaves the slop inside a scroller; the press slot is empty
        // for the rest of the series (the press was withdrawn without a click).
        private var drag:Pointer;
        private var dragNode:UiNode;
        // ONE verdict for "this series does not tap": set by a long press and by leaving
        // the slop. Two flags for the same decision is how the release path grew a second
        // opinion -- measured: with slop-checking in both move() and end(), removing
        // either one left the drag-click bug invisible (mutation M4 was green).
        private var noTap:Boolean;
        private var pressStartMs:int;

        // ---- counters the probe reads (one number per decision) -----------
        public var downCounts:int;
        public var moveCounts:int;
        public var upCounts:int;
        public var cancelCounts:int;
        public var pressCounts:int;           // presses actually delivered
        public var delayedCounts:int;         // presses that went through the scroller delay
        public var slopCancels:int;           // waiting presses/moves killed by slop
        public var longPresses:int;
        public var taps:int;                  // press+release pairs that produced a click
        public var suppressedMoves:int;       // moves sent while no press owned the pointer
        public var dragStarts:int;            // series a viewport took over
        public var dragMoves:int;             // moves forwarded to that viewport
        public var dragEnds:int;              // drags released (not cancelled)

        // The last tap's target, for the probe to compare against its own model.
        public var lastTapNode:UiNode;

        public function PointerRouter(app:UiApp):void
        {
            this.app = app;
            this.pointers = new Dictionary();
            this.press = null;
            this.pending = null;
            this.pendingTimer = -1;
            this.longTimer = -1;
            this.drag = null;
            this.dragNode = null;
            this.noTap = false;
            this.pressStartMs = 0;
            this.downCounts = 0;
            this.moveCounts = 0;
            this.upCounts = 0;
            this.cancelCounts = 0;
            this.pressCounts = 0;
            this.delayedCounts = 0;
            this.slopCancels = 0;
            this.longPresses = 0;
            this.taps = 0;
            this.suppressedMoves = 0;
            this.dragStarts = 0;
            this.dragMoves = 0;
            this.dragEnds = 0;
            this.lastTapNode = null;
        }

        // ---- the four phases ---------------------------------------------

        public function begin(e:TouchEvent):void
        {
            this.downCounts = this.downCounts + 1;
            var p:Pointer = this.acquire(e);
            p.phase = "down";
            p.startX = p.x;
            p.startY = p.y;

            // A SECOND FINGER does not start a press. It is recorded (a later gesture
            // engine needs the series) but the press slot belongs to the first pointer;
            // overwriting it would make two touches into one half-finished tap. The same
            // holds while a viewport owns the series: a second finger dropped onto a
            // scrolling list must not also start pressing a row.
            if (this.press != null || this.pending != null || this.drag != null) return;
            if (!p.isPrimary) return;

            var node:UiNode = this.app.pickAt(p.x, p.y);
            p.node = node;
            // A FINGER ON A COASTING LIST STOPS IT, before the press delay and before the
            // slop: the wait exists to decide "tap or scroll", not to keep gliding under a
            // finger that has already landed.
            if (node != null)
            {
                var sv:UiNode = this.scrollerOf(node);
                if (sv != null)
                {
                    var ts:TouchScrollable = this.scrollableOf(sv);
                    if (ts != null) ts.touchPress(sv);
                }
            }
            this.press = p;
            this.pressStartMs = getTimer();
            this.noTap = false;

            // No node under the finger: the series is still tracked (a drag out of the
            // window must not leave a press behind) but nothing is dispatched.
            if (node == null) return;

            if (this.scrollerOf(node) != null)
            {
                this.pending = p;
                this.delayedCounts = this.delayedCounts + 1;
                this.pendingTimer = setTimeout(flushPending, InputConstants.PRESS_DELAY_MS, p);
                return;
            }
            this.deliverPress(p);
        }

        public function move(e:TouchEvent):void
        {
            var p:Pointer = this.acquire(e);
            p.phase = "move";
            this.moveCounts = this.moveCounts + 1;

            // The viewport owns the series now: every sample goes to it, and no widget
            // sees a synthetic MOVE (there is no press to move ON -- a dragged row must
            // not stay lit, let alone follow the finger).
            if (this.drag == p)
            {
                var ts:TouchScrollable = this.scrollableOf(this.dragNode);
                this.dragMoves = this.dragMoves + 1;
                if (ts != null) ts.touchDragTo(this.dragNode, p.x, p.y);
                return;
            }

            // A press still waiting out the scroller delay dies here if the finger
            // travelled: this touch is a scroll, not a tap. Inside a viewport the drag
            // starts right here (the wait is exactly what this decision was for).
            if (this.pending == p)
            {
                if (this.slopExceeded(p))
                {
                    this.clearPending();
                    this.slopCancels = this.slopCancels + 1;
                    this.startDrag(p);   // false = the series just dies, as before
                }
                return;
            }
            if (this.press != p)
            {
                this.suppressedMoves = this.suppressedMoves + 1;
                return;
            }
            // The press is already delivered (it is what shows `pressed`), so it can not
            // be "cancelled" any more -- all that is left is to stop treating the release
            // as a tap. Inside a viewport the press is WITHDRAWN here instead: a list that
            // scrolled must not leave the row under the finger painted pressed.
            if (this.slopExceeded(p))
            {
                this.noTap = true;
                if (this.startDrag(p)) return;
            }
            this.app.dispatchPointerMouse(MouseEvent.MOUSE_MOVE, p.node, p.x, p.y);
        }

        public function end(e:TouchEvent):void
        {
            var p:Pointer = this.acquire(e);
            p.phase = "up";
            this.upCounts = this.upCounts + 1;

            // A drag ends at the finger's LAST position, which is this event's: a fling's
            // final sample is the one that carries the speed, so dropping it would make
            // every fast flick feel one frame stale.
            if (this.drag == p)
            {
                var node:UiNode = this.dragNode;
                var ts:TouchScrollable = this.scrollableOf(node);
                this.drag = null;
                this.dragNode = null;
                this.dragEnds = this.dragEnds + 1;
                if (ts != null) ts.touchDragEnd(node, p.x, p.y);
                return;
            }

            // Lifted before the scroller delay expired: this is a TAP in a list, and it
            // still has to work. Deliver the press it never showed, then release it --
            // one press, one click, no pressed state that outlives the finger.
            if (this.pending == p)
            {
                this.clearPending();
                this.deliverPress(p);
                this.release(p, true);
                return;
            }
            if (this.press != p) return;
            this.release(p, !this.noTap);
        }

        public function cancel(e:TouchEvent):void
        {
            var p:Pointer = this.acquire(e);
            p.phase = "cancel";
            this.cancelCounts = this.cancelCounts + 1;
            // A revoked drag stops DEAD: no momentum and no click. Whoever took the
            // touch over (an incoming call, a gesture recogniser) owns what happens next.
            if (this.drag == p)
            {
                var dragNode:UiNode = this.dragNode;
                var ts:TouchScrollable = this.scrollableOf(dragNode);
                this.drag = null;
                this.dragNode = null;
                this.dragEnds = this.dragEnds + 1;
                if (ts != null) ts.touchDragCancel(dragNode);
                return;
            }
            if (this.pending == p)
            {
                this.clearPending();
                this.press = null;
                return;
            }
            if (this.press != p) return;
            // Cancel means NO click, but the widget still has to learn the press is over
            // or it stays painted down for the rest of the session.
            if (p.node != null) this.app.dispatchPointerMouse(MouseEvent.MOUSE_UP, p.node, p.x, p.y);
            this.press = null;
        }

        // ---- press machinery ----------------------------------------------

        private function deliverPress(p:Pointer):void
        {
            this.pressCounts = this.pressCounts + 1;
            if (p.node == null) return;
            this.app.dispatchPointerMouse(MouseEvent.MOUSE_DOWN, p.node, p.x, p.y);
            this.longTimer = setTimeout(fireLongPress, InputConstants.LONG_PRESS_MS, p);
        }

        // Fired when the scroller delay ran out with the finger still inside the slop:
        // NOW it is a press. The check is by identity because the series may have ended
        // (and been cleared) while the timer was in flight.
        private function flushPending(p:Pointer):void
        {
            this.pendingTimer = -1;
            if (this.pending != p) return;
            this.pending = null;
            if (this.slopExceeded(p)) return;
            this.deliverPress(p);
            this.longTimer = setTimeout(fireLongPress, InputConstants.LONG_PRESS_MS, p);
        }

        private function fireLongPress(p:Pointer):void
        {
            this.longTimer = -1;
            if (this.press != p) return;
            this.noTap = true;
            this.longPresses = this.longPresses + 1;
        }

        private function release(p:Pointer, tap:Boolean):void
        {
            if (this.longTimer != -1)
            {
                clearTimeout(this.longTimer);
                this.longTimer = -1;
            }
            var node:UiNode = p.node;
            this.press = null;
            if (node == null) return;
            this.app.dispatchPointerMouse(MouseEvent.MOUSE_UP, node, p.x, p.y);
            if (!tap) return;
            this.taps = this.taps + 1;
            this.lastTapNode = node;
            this.app.dispatchPointerMouse(MouseEvent.CLICK, node, p.x, p.y);
        }

        // ---- helpers -------------------------------------------------------

        private function acquire(e:TouchEvent):Pointer
        {
            var p:Pointer = this.pointers[e.touchPointID] as Pointer;
            if (p == null)
            {
                p = new Pointer(e.touchPointID, e.localX, e.localY, e.isPrimaryTouchPoint, e.pressure);
                this.pointers[e.touchPointID] = p;
                return p;
            }
            p.x = e.localX;
            p.y = e.localY;
            return p;
        }

        private function slopExceeded(p:Pointer):Boolean
        {
            var dx:Number = p.x - p.startX;
            var dy:Number = p.y - p.startY;
            return (dx * dx + dy * dy) > (InputConstants.PRESS_SLOP_PT * InputConstants.PRESS_SLOP_PT);
        }

        private function clearPending():void
        {
            this.pending = null;
            if (this.pendingTimer != -1)
            {
                clearTimeout(this.pendingTimer);
                this.pendingTimer = -1;
            }
            if (this.longTimer != -1)
            {
                clearTimeout(this.longTimer);
                this.longTimer = -1;
            }
            this.press = null;
        }

        // Is this node inside a scrolling container? Not by kind: a kind check would
        // make the drag path skip a viewport that a future widget implements under
        // another name, and it would have to be repeated here for every question after
        // it. The capability IS the answer (TouchScrollable), and it is resolved through
        // the same registry every other optional trait uses.
        private function scrollerOf(n:UiNode):UiNode
        {
            var p:UiNode = n;
            while (p != null)
            {
                if (this.scrollableOf(p) != null) return p;
                p = p.parent;
            }
            return null;
        }

        private function scrollableOf(n:UiNode):TouchScrollable
        {
            if (n == null || n.kind == null || !Widgets.has(n.kind)) return null;
            var w:Widget = Widgets.require(n.kind);
            if (!(w is TouchScrollable)) return null;
            return w as TouchScrollable;
        }

        // Hand the series to the viewport under the press. False = nobody can take it
        // (no scroller ancestor, or a scroller that does not implement the trait), and
        // then every caller behaves exactly as it did before this feature existed.
        private function startDrag(p:Pointer):Boolean
        {
            var sv:UiNode = this.scrollerOf(p.node);
            if (sv == null) return false;
            var ts:TouchScrollable = this.scrollableOf(sv);
            if (ts == null) return false;
            // THE PRESS IS WITHDRAWN, NOT "CANCELLED LATER": a row painted pressed while
            // its list scrolls is the single most reported mobile glitch. Withdrawing it
            // is one MOUSE_UP with no CLICK after it -- the same two events a real mouse
            // gives when the pointer leaves the control.
            if (this.press == p)
            {
                if (this.longTimer != -1)
                {
                    clearTimeout(this.longTimer);
                    this.longTimer = -1;
                }
                if (p.node != null) this.app.dispatchPointerMouse(MouseEvent.MOUSE_UP, p.node, p.x, p.y);
                this.press = null;
            }
            this.noTap = true;
            this.drag = p;
            this.dragNode = sv;
            this.dragStarts = this.dragStarts + 1;
            ts.touchDragBegin(sv, p.x, p.y, p.startX, p.startY);
            // THE POSITION THAT CROSSED THE SLOP IS PART OF THE SERIES. Without this the
            // widget's first sample would be the NEXT move, and the axis would then be
            // decided from an anchor many points away -- discarding the whole motion from
            // touch-down instead of the 8pt of slop (measured: a 20pt drag landed at 0).
            ts.touchDragTo(sv, p.x, p.y);
            return true;
        }

        public function pointerCount():int
        {
            var n:int = 0;
            for each (var p:Pointer in this.pointers) n = n + 1;
            return n;
        }
    }
}
