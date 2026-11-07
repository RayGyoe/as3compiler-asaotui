// asaot.ui.FpsPanel -- the frame-rate HUD behind `UiApp.showFps()`.
//
// WHAT IT MEASURES, AND WHY IT IS NOT A STOPWATCH
// -----------------------------------------------
// A frame rate needs FRAMES, and the only honest count of frames is the number of
// times the runtime broadcast ENTER_FRAME. So this class is driven from UiApp's own
// one ENTER_FRAME listener (`tick`), not from a Timer: a Timer measures the clock,
// not the drawing, and an app whose frames take 40ms would still read "25 fps from a
// 25ms timer" while the screen updated at 25. `getTimer()` is the same monotonic ms
// clock the animator and `View.tick` use, read once per frame by the caller.
//
// It reports THREE numbers, because one is not enough to tell "smooth" from "jerky":
//
//   fps     frames per second over the last window (WINDOW_MS)
//   avg     the window's mean frame interval in milliseconds
//   peak    the WORST single interval in the window
//
// 60 fps with a 60ms peak is a visible stutter; the average would hide it and the
// peak is the number that explains it. The sparkline is that same average over the
// last HISTORY windows, so a stall leaves a mark for six seconds.
//
// IT IS CHROME, AND CHROME IS NOT CLICKABLE. The nodes it builds live in the app's
// THIRD retained tree (see UiApp.showFps), which UiApp marks `mouseEnabled = false`
// AND `mouseChildren = false`: a HUD drawn over the top-right corner must never eat
// a click from the control underneath it. That is a property of the TREE, not of
// this description -- see the comment at the attachment site.
//
// NO THEME TOKENS FOR THE FOREGROUND. The background is `surfaceInverse` (a dark
// slate in BOTH palettes, the same choice the tooltip makes), so a foreground that
// followed the palette would go dark-on-dark the moment someone switched themes.
// Health colours are fixed for the same reason: a rate is a measurement, and a
// measurement that changes colour because the app did is not a measurement.
package asaot.ui
{
    import asaot.ui.style.Corners;
    import asaot.ui.style.Fill;
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;

    public class FpsPanel
    {
        // The four corners `showFps` accepts. A fifth spelling is an error, never a
        // silent default: a panel in the wrong corner is a bug you would not see
        // until a screenshot.
        public static const TOP_LEFT:String = "top-left";
        public static const TOP_RIGHT:String = "top-right";
        public static const BOTTOM_LEFT:String = "bottom-left";
        public static const BOTTOM_RIGHT:String = "bottom-right";

        // 4 samples a second: fast enough to catch a stall, slow enough that the HUD
        // costs one three-node describe per window instead of one per frame.
        private static const WINDOW_MS:int = 250;
        // 24 windows x 250ms = six seconds of history in the sparkline.
        private static const HISTORY:int = 24;

        private static const INSET:Number = 12;
        private static const W:Number = 104;
        private static const PAD:Number = 9;
        private static const CW:Number = W - PAD * 2;

        // HUD foreground. See the header for why these are not tokens.
        private static const INK:uint = 0xFFFFFF;
        private static const LABEL:uint = 0x94A3B8;
        private static const GOOD:uint = 0x4ADE80;
        private static const WARN:uint = 0xFBBF24;
        private static const BAD:uint = 0xF87171;
        private static const LINE:uint = 0x60A5FA;

        // ---- published numbers (plain fields: a probe reads them like a model) --
        public var fps:int = 0;
        public var avgMs:Number = 0;
        public var peakMs:Number = 0;
        // Has one window closed yet? A rate needs an INTERVAL, and the first frames
        // have none, so the panel shows dashes plus "warming up" rather than a zero it
        // never measured.
        public var sampled:Boolean = false;

        public var corner:String;
        // Frame counter for the CURRENT window and the window's start/peak.
        private var _frames:int;
        private var _winStart:int;
        private var _peak:Number;
        // The previous frame's timestamp; 0 until the second frame (the first frame
        // has no interval to measure).
        private var _last:int;

        // Per-window averages, oldest first -- the sparkline's series. Mutated IN
        // PLACE with `_ver` bumped, which is the contract SparklineNode documents for
        // an array the author keeps.
        private var _series:Array;
        private var _ver:int;

        public function FpsPanel(corner:String = "top-right"):void
        {
            this.corner = corner;
            this.checkCorner(corner);
            this._frames = 0;
            this._winStart = 0;
            this._peak = 0;
            this._last = 0;
            this._series = [];
            this._ver = 0;
        }

        private function checkCorner(c:String):void
        {
            if (c == TOP_LEFT || c == TOP_RIGHT || c == BOTTOM_LEFT || c == BOTTOM_RIGHT) return;
            throw new Error('asaot.ui.FpsPanel: unknown corner "' + c
                + '" (known: top-left, top-right, bottom-left, bottom-right)');
        }

        // Moving the panel keeps the MEASUREMENT: only the inset changes, and a
        // window that starts over because someone dragged the HUD would report a
        // gap in the data that the app never had.
        public function setCorner(c:String):void
        {
            this.checkCorner(c);
            this.corner = c;
        }

        // ---- the clock -------------------------------------------------------
        // Called once per ENTER_FRAME, BEFORE the reflow, so the window this frame
        // belongs to is the one it is counted in. Returns TRUE when a window closed,
        // i.e. when the numbers below moved and the panel needs a new description --
        // UiApp turns that into one reflow of the HUD tree and nothing else.
        public function tick(now:int):Boolean
        {
            if (this._winStart == 0)
            {
                // First frame: start the clock. There is no interval yet, and
                // inventing one (0) would report a 1000 fps spike on frame one.
                this._winStart = now;
                this._last = now;
                return false;
            }
            var dt:int = now - this._last;
            if (dt > 0 && dt > this._peak) this._peak = dt;
            this._last = now;
            this._frames = this._frames + 1;

            var span:int = now - this._winStart;
            if (span < WINDOW_MS) return false;
            if (span < 1) span = 1;
            var f:Number = this._frames;
            this.fps = int(Math.round(f * 1000 / span));
            this.avgMs = span / f;
            this.peakMs = this._peak;

            this._series.push(this.avgMs);
            while (this._series.length > HISTORY) this._series.shift();
            this._ver = this._ver + 1;

            this._frames = 0;
            this._winStart = now;
            this._peak = 0;
            this.sampled = true;
            return true;
        }

        // ---- the description --------------------------------------------------
        // Rebuilt on every closed window. The STRUCTURE never changes (same kinds,
        // same keys), so the reconciler reuses all four nodes and only the text and
        // the series pointer/version move.
        public function describe():Node
        {
            var t:ThemeTokens = Theme.tokens();
            var inv:uint = t.surfaceInverse;
            var bg:Fill = Fill.solid(inv);

            var head:StyleRefinement = StyleRefinement.from({
                flexDirection: "row", alignItems: "flex-end", justifyContent: "flex-start", gap: 4,
                size: [Length.px(CW), Length.px(20)]
            });
            var value:StyleRefinement = StyleRefinement.from({
                // 36px holds three bold Courier digits, so the unit does not jump when
                // the rate crosses 99; the number is RIGHT-aligned against the unit so
                // the pair reads as one token rather than as two columns.
                size: [Length.px(36), Length.px(20)],
                text: { fontFamily: "Courier New", fontSize: 19, fontWeight: "bold",
                        textAlign: "right", color: this.tone() }
            });
            var unit:StyleRefinement = StyleRefinement.from({
                size: [Length.px(20), Length.px(13)],
                text: { fontSize: 10, fontWeight: "bold", color: LABEL }
            });
            // The two qualifiers sit on ONE row, pinned to its edges. A single string
            // would have to guess where the column break is, and the widest case -- a
            // three-digit peak -- would then overflow the panel.
            var subRow:StyleRefinement = StyleRefinement.from({
                flexDirection: "row", justifyContent: "space-between",
                size: [Length.px(CW), Length.px(13)]
            });
            var sub:StyleRefinement = StyleRefinement.from({
                text: { fontFamily: "Courier New", fontSize: 10, color: LABEL }
            });

            return overlay([
                column({
                    key: "fpsPanel",
                    ariaName: "Frame rate",
                    style: StyleRefinement.from({
                        position: "absolute",
                        inset: this.inset(),
                        size: [Length.px(W), null],
                        padding: [7, PAD],
                        gap: 3,
                        background: bg,
                        cornerRadii: Corners.all(9),
                        borderWidths: 1,
                        borderColor: 0x0B1220
                    })
                }, [
                    row({ key: "fpsHead", style: head, ariaName: "" }, [
                        text(this.sampled ? String(this.fps) : "—",
                             { key: "fpsValue", style: value, ariaName: "" }),
                        text("fps", { key: "fpsUnit", style: unit, ariaName: "" })
                    ]),
                    row({ key: "fpsSubRow", style: subRow, ariaName: "" }, [
                        text(this.avgText(), { key: "fpsAvg", style: sub, ariaName: "" }),
                        text(this.peakText(), { key: "fpsPeak", style: sub, ariaName: "" })
                    ]),
                    sparkline({ key: "fpsSpark", values: this._series, version: this._ver,
                                color: LINE, fill: true, dot: true, strokeWidth: 1.2,
                                style: StyleRefinement.from({
                                    size: [Length.px(CW), Length.px(20)] }) })
                ])
            ]);
        }

        private function avgText():String
        {
            // NOT "0 ms": a rate needs an INTERVAL, and the first 250ms of any app has
            // none. A HUD that printed a zero would be reporting a measurement it never
            // took; the words say what is actually happening.
            if (!this.sampled) return "warming up";
            return this.avgMs.toFixed(1) + " ms";
        }

        private function peakText():String
        {
            if (!this.sampled) return "";
            return "max " + this.peakMs.toFixed(0);
        }

        // Green at a healthy rate, amber below 55, red below 30. The thresholds are
        // the HUD's own judgement, named here so they are not magic numbers spread
        // through an expression.
        private function tone():uint
        {
            if (!this.sampled) return LABEL;
            if (this.fps >= 55) return GOOD;
            if (this.fps >= 30) return WARN;
            return BAD;
        }

        private function inset():Array
        {
            if (this.corner == TOP_LEFT) return [INSET, null, null, INSET];
            if (this.corner == BOTTOM_LEFT) return [null, null, INSET, INSET];
            if (this.corner == BOTTOM_RIGHT) return [null, INSET, INSET, null];
            return [INSET, INSET, null, null];
        }
    }
}