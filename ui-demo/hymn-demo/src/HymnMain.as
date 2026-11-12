// hymn/HymnMain.as -- the document class the window boots.
//
// WHAT --air-app DOES FOR US (do not call showWindow here): the generated bootstrap
// constructs this class, adds it to the stage and only then shows the window, so the
// size, title, renderMode and requestedDisplayResolution all come from
// hymn-demo/app.xml.
//
// THE LOAD HAPPENS ON THE FIRST FRAME, AND THAT IS LOAD-BEARING. Parsing 1000 hymns
// allocates several megabytes of strings and objects; before the frame loop exists the
// collector's offscreen path runs a full cycle FROM INSIDE the allocation stream, and
// a cycle there frees objects the loop is still holding (compiler-gaps.md G45 --
// measured: n=400 SIGSEGVs, n=200 does not, and `ASC_GC_THRESHOLD` or `-O1` hides it).
// Inside an ENTER_FRAME handler the collector only ever steps at a frame boundary, so
// the whole build completes with no cycle running. Moving this line back into
// onAdded() reintroduces that crash.
//
// The build also leaves a screenshot and a `.done` beacon behind, like the gallery
// tour does, so a run is verifiable without a human looking at the window.
package hymn
{
    import asaot.ui.Dirty;
    import asaot.ui.Theme;
    import asaot.ui.UiApp;
    import asaot.ui.UiNode;
    import asaot.ui.WidgetFocus;
    import flash.display.DisplayObject;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.events.Event;
    import flash.events.KeyboardEvent;
    import flash.events.MouseEvent;
    import flash.events.TouchEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.getTimer;

    public class HymnMain extends Sprite
    {
        private static const OUT:String = "hymn";
        // THE CAPTURE PLAN IS OPT-IN, BY FILE, AND THE FILE IS THE ONLY SWITCH.
        // Double-clicking the exe must give a NORMAL APP -- a demo that starts playing
        // by itself the moment you open it is a test rig, not a demo. So the plan only
        // runs when `auto-tour` sits next to the executable, which is a thing
        // `run-hymn.cjs` creates and deletes and a human never needs. A file rather
        // than an environment variable because AS3 has no `getenv` (and adding one is
        // not this project's call); a file rather than a second exe because the
        // harness and the demo would then be two binaries that can drift apart.
        private static const TOUR_MARKER:String = "auto-tour";
        // The shot waits for the SPLASH TO BE GONE (1500 hold + 450 fade) and then a
        // few frames, so the picture is the app and not its own loading screen.
        private static const SHOT_FRAME:int = 130;

        private var tour:Boolean = false;

        private var model:HymnModel;
        private var view:HymnView;
        private var app:UiApp;
        private var frames:int = 0;
        private var loaded:Boolean = false;
        // The capture plan's clock (see onFrame).
        private var phase:int = 0;
        private var phaseAt:int = 0;
        private var playAt:Number = 0;
        private var loadMs:int = 0;
        // Phase 4's beats (see onFrame) and the one-line record they append.
        private var aSub:int = 0;
        private var aSubAt:int = 0;
        private var aTrace:String = "";
        private var selfFail:String = "";
        // Which palette the KIT was last given, so a theme toggle installs the other one
        // exactly once instead of on every notifying call.
        private var kitName:String = "";

        public function HymnMain():void
        {
            addEventListener(Event.ADDED_TO_STAGE, onAdded);
        }

        private function onAdded(e:Event):void
        {
            removeEventListener(Event.ADDED_TO_STAGE, onAdded);
            this.model = new HymnModel();
            this.view = new HymnView();
            this.view.model = this.model;
            this.stage.scaleMode = StageScaleMode.NO_SCALE;
            this.stage.align = StageAlign.TOP_LEFT;
            this.stage.frameRate = 60;
            this.tour = File.applicationDirectory.resolvePath(TOUR_MARKER).exists;
            trace("HymnMain: tour=" + String(this.tour));
            this.app = new UiApp(this.view);
            var self:HymnMain = this;
            // A kit-side palette that agrees with ours (see HymnTheme.kitPalette): the
            // scroll bars, the placeholder ghost and a control's base skin are painted
            // by the WIDGET from Theme.tokens(), not from our style objects.
            Theme.setTheme(this.model.theme.kitPalette());
            this.kitName = this.model.theme.name;
            this.model.subscribe(function (d:int):void {
                if (self.kitName != self.model.theme.name)
                {
                    self.kitName = self.model.theme.name;
                    Theme.setTheme(self.model.theme.kitPalette());
                }
                self.app.invalidate(d);
            });
            this.view.app = this.app;
            // ADDED BEFORE mount(): both listeners sit on the stage and run in
            // registration order, so this one sees a key BEFORE the kit does. That is
            // the point -- the kit's keymap consumes a binding ahead of the focused
            // widget, which would steal an arrow from the search field's caret (see
            // keyStep). Unhandled keys fall through and the kit still gets them.
            this.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
            this.app.mount(this.stage);
            this.app.attachRoot();
            // systemChrome=none: the caption's drag area is now the drawn title bar.
            this.stage.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
            addEventListener(Event.ENTER_FRAME, onFrame);
        }

        // A press on the title bar (but NOT on one of the caption icons) starts a real
        // system move. startMove() latches the pointer at the OS level, so there is no
        // drag state to track here and no position to write -- which is exactly why a
        // hand-rolled loop over `nativeWindow.x` is the wrong answer: it fights snapping
        // and stalls as soon as the pointer leaves the window.
        private function onMouseDown(e:MouseEvent):void
        {
            var n:UiNode = this.app.nodeAt(DisplayObject(e.target));
            var onBar:Boolean = false;
            var onButton:Boolean = false;
            var p:UiNode = n;
            while (p != null)
            {
                if (p.key == "titlebar") onBar = true;
                else if (p.key == "winbtns") onButton = true;
                p = p.parent;
            }
            if (!onBar || onButton) return;
            var w:Object = this.stage.nativeWindow;
            if (w != null) w.startMove();
        }

        // Upstream's root `on_key_down` (src/ui/mod.rs): Down/Up walk the hymn list,
        // Ctrl+B folds the library. The field keeps its arrows: gpui's InputState
        // consumes them before the root handler, so the same rule applies here -- an
        // editable focus means "the caret is typing", not "the list is walking".
        private function onKeyDown(e:KeyboardEvent):void
        {
            if (this.model == null || !this.model.ready) return;
            var kc:int = e.keyCode;
            if (kc == 38 || kc == 40)
            {
                var f:UiNode = this.app.focusedNode();
                if (f != null && f.widget is WidgetFocus) return;
                this.model.stepHymn(kc == 40 ? 1 : -1);
                e.preventDefault();
                return;
            }
            if (kc == 66 && e.ctrlKey)
            {
                this.model.toggleSidebar();
                e.preventDefault();
            }
        }

        private function onFrame(e:Event):void
        {
            frames++;
            if (!loaded)
            {
                loaded = true;
                var t0:int = getTimer();
                this.model.load();
                this.loadMs = getTimer() - t0;
                // hymnbook's own fourteen tests, run here rather than left as a comment:
                // a port whose only check is "the screen looks right" drifts exactly
                // where those tests bite. Plus the one join those tests cannot see --
                // the generated note corpus against the generated tune metadata.
                // A TOUR-ONLY GATE: the report lands in the executable's directory, and
                // a person who just opened the app did not ask for a file next to it.
                if (this.tour)
                {
                    this.selfFail = HymnSelfTest.run(this.model.hymns);
                    this.out(OUT + "-selftest.txt", this.selfFail == ""
                        ? "PASS " + String(this.model.hymns.length) + " hymns, "
                            + String(HymnSelfTest.notes) + " notes over " + String(HymnSelfTest.tunes)
                            + " tunes\n"
                        : this.selfFail);
                }
                trace("HymnMain: " + this.model.hymns.length + " hymns in " + this.loadMs + " ms");
                return;
            }
            this.model.tick(getTimer());
            if (!this.tour) return;
            var w:Number = this.stage.stageWidth;
            var h:Number = this.stage.stageHeight;
            // A small capture PLAN, each step driven by the app's own verbs so the
            // pictures prove the BEHAVIOUR and not just the first frame's paint:
            //   0  the splash (frame 2, before it starts fading)
            //   1  the page as it opens (hymn 1, no tune)
            //   2  a tuned hymn: section map, voice pills, transport
            //   3  sidebar slid away + light palette
            //   4  play for 80 frames, then report where the reader followed to
            switch (phase)
            {
                case 0:
                    // 40 frames = 0.66s into the 700ms entrance fade: early enough to be
                    // the splash, late enough that the content is actually opaque.
                    if (frames == 40)
                    {
                        this.stage.render(w, h, OUT + "-splash.png");
                        this.next(1);
                    }
                    break;
                case 1:
                    if (frames >= SHOT_FRAME && this.model.splash == 2)
                    {
                        this.dumpRects(w, h, "-page");
                        this.stage.render(w, h, OUT + "-page.png");
                        trace("HymnMain: page shot at " + w + "x" + h);
                        this.toTuned();
                        this.next(2);
                    }
                    break;
                case 2:
                    if (frames >= phaseAt)
                    {
                        this.dumpRects(w, h, "-tuned");
                        this.stage.render(w, h, OUT + "-tuned.png");
                        trace("HymnMain: tuned shot");
                        // Two more behaviours in one run: the drawer slides out (300ms)
                        // and the palette swaps (which also re-installs the KIT's).
                        this.model.toggleSidebar();
                        this.model.toggleTheme();
                        this.next(3);
                    }
                    break;
                case 3:
                    if (frames >= phaseAt)
                    {
                        this.dumpRects(w, h, "-light");
                        this.stage.render(w, h, OUT + "-light.png");
                        trace("HymnMain: light shot");
                        this.model.togglePlay();
                        this.playAt = this.model.scrollY;
                        this.next(4);
                    }
                    break;
                case 4:
                    // THE TRANSPORT IS EXERCISED, NOT JUST STARTED. Four beats, each
                    // through the verb the UI itself calls, each recording both clocks:
                    //   0  play (any part/instrument)        -> device is pulling
                    //   1  mute Soprano                      -> re-render, position kept
                    //   2  switch to Flute                   -> re-render, position kept
                    //   3  seek to the second VERSE block    -> device jumps to that second
                    // A silent transport would still advance the model clock, so the
                    // device's own `positionSec` is the number that has to move with it.
                    var el:int = frames - phaseAt;
                    if (aSub == 0 && el >= 30)
                    {
                        this.note("play");
                        this.model.toggleVoice("Soprano");
                        aSub = 1; aSubAt = frames;
                    }
                    else if (aSub == 1 && frames - aSubAt >= 12)
                    {
                        this.note("muteS");
                        this.model.setInstrument("Flute");
                        aSub = 2; aSubAt = frames;
                    }
                    else if (aSub == 2 && frames - aSubAt >= 12)
                    {
                        this.note("flute");
                        this.model.seekBlock(2);
                        aSub = 3; aSubAt = frames;
                    }
                    else if (aSub == 3 && frames - aSubAt >= 12)
                    {
                        this.note("seek3");
                        var a:HymnAudio = this.model.audio;
                        // AUDIO AND FOLLOW ARE READ BEFORE THE KEYS. The keyboard walk
                        // changes the hymn below, and a hymn change stops the transport
                        // (that is select() -> load_tune, seen from the model side), so a
                        // reading taken afterwards would describe a different program.
                        this.kAudio = a.status + " ready=" + String(a.ready)
                            + " samples=" + String(a.samples) + " render=" + String(a.renderMs) + "ms"
                            + " peak=" + a.peak.toFixed(3) + " regs=" + String(a.regs);
                        this.kFollow = this.model.scrollY;
                        this.kVerse = this.model.blockIndex + 1;
                        // THE FADE IS ASSERTED, NOT EYEBALLED. While a tune plays, exactly
                        // one block sits at full opacity and every other one at DIM; a
                        // theme/style regression that hands the whole reader one style
                        // would read either all 1 or all 0.42 here. Read from the nodes,
                        // not from the model: the question is whether the fade reached the
                        // widget that paints it.
                        this.kDim = this.opacityOf("bk" + String(this.model.blockIndex) + "v")
                            + "/" + this.opacityOf(this.model.blockIndex == 0 ? "bk1v" : "bk0v");
                        // THE ONE STATE THE OTHER FOUR SHOTS CANNOT SHOW: mid-song. The
                        // transport has seeked to the third verse, so this frame has to
                        // carry the fade (one block lit, the rest at 0.42), the follower's
                        // scroll offset and the transport's own clock all at once.
                        this.stage.render(w, h, OUT + "-playing.png");
                        trace("HymnMain: playing shot");
                        // THE DRAWER IS CLOSED AT THIS POINT (phase 2 folded it for the
                        // light shot), and a folded drawer has no search field in the
                        // rid tree at all. So the keyboard test starts by opening it,
                        // waits for the frame that puts the field back, and closes it
                        // again at the end.
                        this.kSide0 = this.model.sidebarOpen;
                        this.sendKey(66, true);
                        this.kSideA = this.model.sidebarOpen;
                        aSub = 4; aSubAt = frames;
                    }
                    else if (aSub == 4 && frames - aSubAt >= 12)
                    {
                        // THE FIELD GUARD: with the caret in the search box the SAME key
                        // must not walk the list. Upstream gets this from gpui for free
                        // (InputState consumes the arrow before the root handler); here
                        // the root handler asks the focus first.
                        this.app.focusNode(this.app.findByKey("searchField"));
                        this.kGuard0 = this.model.sel;
                        this.sendKey(40, false);
                        this.kGuard1 = this.model.sel;
                        // BLUR TO A NODE, NOT TO NULL: focusNode(null) while a text field
                        // holds the focus throws Error #1009 in this runtime (compiler-gaps
                        // G47); moving the focus to any other node is the path the typing
                        // probe already walks and it is clean.
                        this.app.focusNode(this.app.findByKey("reader"));
                        // DOWN walks the FILTERED list (the `With tune` segment is on),
                        // which is why the numbers jump instead of counting up by one.
                        this.kSel0 = this.model.sel;
                        this.sendKey(40, false);
                        this.sendKey(40, false);
                        this.kSel1 = this.model.sel;
                        this.kReveal = this.model.libReveal;
                        aSub = 5; aSubAt = frames;
                    }
                    else if (aSub == 5 && frames - aSubAt >= 8)
                    {
                        // A TAP, FIVE OF THEM, ONE PER BEAT. Every other beat in this
                        // plan calls a model verb, so the pointer path -- pick, press
                        // delay, click, the author's `onClick` -- was never executed and
                        // a `#1063` in a handler was invisible. Each tap is graded by its
                        // EFFECT (palette name, lyric size, selection), because a handler
                        // that throws leaves the model untouched and the frame guard
                        // swallows the error.
                        this.cTheme0 = this.model.theme.name;
                        this.cSize0 = this.model.lyricSize;
                        this.cTapSel0 = this.model.sel;
                        if (this.sendTap("theme")) this.cTapHits += "theme+ ";
                        else this.cTapHits += "theme! ";
                        aSub = 6; aSubAt = frames;
                    }
                    else if (aSub == 6 && frames - aSubAt >= 8)
                    {
                        this.cTheme1 = this.model.theme.name;
                        // THE ONE DIRECTION NO OTHER CAPTURE TAKES. The plan's own switch
                        // is dark->light (phase 2); this beat is light->dark, driven by a
                        // real tap on the titlebar sun. Photograph it before tapping back:
                        // a palette that half-lands is a direction-specific bug, and it
                        // took a human looking at the window to find it.
                        this.dumpRects(w, h, "-dark2");
                        this.stage.render(w, h, OUT + "-dark2.png");
                        this.sendTap("theme");          // back to where it was
                        aSub = 7; aSubAt = frames;
                    }
                    else if (aSub == 7 && frames - aSubAt >= 8)
                    {
                        this.cTheme2 = this.model.theme.name;
                        if (this.sendTap("plus")) this.cTapHits += "plus+ "; else this.cTapHits += "plus! ";
                        aSub = 8; aSubAt = frames;
                    }
                    else if (aSub == 8 && frames - aSubAt >= 8)
                    {
                        this.cSize1 = this.model.lyricSize;
                        this.sendTap("minus");          // back to where it was
                        aSub = 9; aSubAt = frames;
                    }
                    else if (aSub == 9 && frames - aSubAt >= 8)
                    {
                        this.cSize2 = this.model.lyricSize;
                        // A ROW lives inside the scroller, so this one also proves the
                        // press-delay path (begin -> pending -> end delivers the press).
                        if (this.sendTap("ri3")) this.cTapHits += "row+ "; else this.cTapHits += "row! ";
                        aSub = 10; aSubAt = frames;
                    }
                    else if (aSub == 10 && frames - aSubAt >= 8)
                    {
                        this.cTapSel1 = this.model.sel;
                        // Put the drawer and the hymn back: the capture above must not be
                        // evidence of a program that stopped existing one line later.
                        if (this.model.sidebarOpen != this.kSide0) this.sendKey(66, true);
                        var side1:Boolean = this.model.sidebarOpen;
                        this.model.pick(this.kSel0);
                        this.model.seekBlock(2);
                        this.model.togglePlay();
                        var a2:HymnAudio = this.model.audio;
                        var resume:String = a2.status + " samples=" + String(a2.samples)
                            + " peak=" + a2.peak.toFixed(3) + " regs=" + String(a2.regs);
                        this.out(OUT + ".done", "PASS " + this.model.hymns.length + " hymns, load "
                            + this.loadMs + " ms, " + w + "x" + h + ", splash gone at frame "
                            + String(SHOT_FRAME) + ", tuned=" + String(this.model.hasTuneSelected())
                            + ", followFrom=" + String(Math.round(this.playAt))
                            + " followTo=" + String(Math.round(this.kFollow))
                            + ", verse=" + String(this.kVerse)
                            + ", dim=" + this.kDim
                            + ", audio=" + this.kAudio
                            + ", keys=ctrlB " + String(this.kSide0) + "->" + String(this.kSideA)
                            + " (restored " + String(side1) + ")"
                            + " fieldGuard " + String(this.kGuard0) + "->" + String(this.kGuard1)
                            + " down,down " + String(this.kSel0) + "->" + String(this.kSel1)
                            + " of " + String(this.model.visible.length)
                            + " reveal=" + String(this.kReveal)
                            + ", taps " + this.cTapHits
                            + " palette " + this.cTheme0 + "->" + this.cTheme1 + "->" + this.cTheme2
                            + " size " + String(this.cSize0) + "->" + String(this.cSize1)
                            + "->" + String(this.cSize2)
                            + " rowSel " + String(this.cTapSel0) + "->" + String(this.cTapSel1)
                            + ", resume=" + resume
                            + ", trace=" + aTrace + "\n");
                        trace("HymnMain: done");
                        aSub = 11;
                        this.next(5);
                    }
                    break;
            }
        }

        // One synthetic KEY_DOWN on the stage, with the ctor order this runtime
        // declares: (type, bubbles, cancelable, charCode, keyCode, keyLocation,
        // ctrlKey, altKey, shiftKey, controlKey, commandKey, functionKey).
        private function sendKey(code:int, ctrl:Boolean):void
        {
            var e:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, true,
                0, code, 0, ctrl, false, false, false, false, false);
            this.stage.dispatchEvent(e);
        }

        // One synthetic TAP on the stage at (x, y).
        //
        // THE POINTER CHANNEL IS TOUCH, NOT MOUSE: `UiApp` listens for
        // `TouchEvent.TOUCH_*` and `PointerRouter` turns a begin/end pair on the same
        // point into a press plus a click (a raw MouseEvent dispatched at the stage
        // reaches no widget at all). Coordinates are `localX/localY` -- `stageX/
        // stageY` are derived and this runtime always reports 0.0 for them.
        //
        // WHY A TAP IS IN THIS PLAN AT ALL: every other beat calls the model's verb
        // directly, so a click handler could be broken and every capture would still
        // pass -- which is exactly what happened: the kit calls `onClick()` with NO
        // arguments (UiNode.as:490, and its contract note says so), the demo declared
        // `function (e:Object)`, and AVM2 threw `#1063 Argument count mismatch` on
        // every single click while the whole beacon stayed green. The frame guard
        // swallows that error, so the only observable is "the handler never ran".
        private function sendClick(x:Number, y:Number):void
        {
            var d:TouchEvent = new TouchEvent(TouchEvent.TOUCH_BEGIN, true, true,
                0, true, x, y, 1, 1, 1.0, null, false, false, false, false, false,
                0, null, null, false);
            this.stage.dispatchEvent(d);
            var u:TouchEvent = new TouchEvent(TouchEvent.TOUCH_END, true, true,
                0, true, x, y, 1, 1, 1.0, null, false, false, false, false, false,
                0, null, null, false);
            this.stage.dispatchEvent(u);
        }

        // Tap the centre of a landmark found by key. False when the node is not in
        // the tree right now (a folded drawer has no rows), so a beat can say so
        // instead of quietly asserting nothing.
        private function sendTap(key:String):Boolean
        {
            var n:UiNode = this.app.findByKey(key);
            if (n == null || n.absW <= 0 || n.absH <= 0) return false;
            this.sendClick(n.absX + n.absW / 2, n.absY + n.absH / 2);
            return true;
        }

        private function next(p:int):void
        {
            this.phase = p;
            this.phaseAt = frames + 20;
            if (p == 3) this.phaseAt = frames + 30;   // let the drawer finish sliding
            if (p == 4) this.phaseAt = frames;       // phase 4 counts its own beats
        }

        // One beat of the audio trace: the device clock and the model clock side by
        // side. They are two different numbers on purpose -- the model's is derived
        // from a frame count, the device's comes back from the mixer -- so "they track"
        // is a measurement, and a mute or a seek that only moved one of them shows up.
        private function note(tag:String):void
        {
            var a:HymnAudio = this.model.audio;
            aTrace += (aTrace == "" ? "" : "; ") + tag
                + " dev=" + String(Math.round(a.positionSec() * 100) / 100)
                + " model=" + String(Math.round(this.model.nowSec() * 100) / 100)
                + " regs=" + String(a.regs)
                + " stat=" + a.status;
        }

        // Pick the first hymn that has a tune, through the same two calls the UI makes:
        // switch the filter to "With tune", then select the first row.
        private function toTuned():void
        {
            this.model.setFilter(HymnModel.TUNED_ROWS);
            var vis:Array = this.model.visible;
            if (vis.length == 0) return;
            this.model.pick(int(vis[0]));
        }

        // A NUMBER, NOT AN OPINION, per region: the solved rect of every landmark the
        // layout is judged on, plus a scan for nodes that escaped the stage.
        //
        // A vision pass reads a screenshot as prose and gets a 6 px inset wrong; this
        // file is what turns "the player looks crowded" into "player y=683 h=100 while
        // the stage is 783 tall, so it is NOT clipped" -- or catches the opposite.
        // Overlays and the fps panel legitimately sit outside the flow, so they are
        // skipped by key.
        private function walkInk(n:UiNode, acc:Array):void
        {
            if (n == null) return;
            if (n.resolved != null && n.resolved.text != null)
            {
                var c:Number = n.resolved.text.color;
                if (!isNaN(c))
                {
                    // BOTH NUMBERS: what the style resolved to and what the FIELD is
                    // actually showing. They disagree only when the paint side lost the
                    // colour, which is the whole question a screenshot cannot answer.
                    var fc:String = n.tf == null ? "-" : uint(n.tf.textColor).toString(16);
                    // WHICH OF THE TWO COLOURS THE RENDERER BELIEVES. `textColor` is the
                    // field-level one; `getTextFormat()` reads back the RUN format that
                    // `setTextFormat` installed. When they disagree, the run is what is on
                    // screen -- and the run is only refreshed by a re-measure.
                    var rc:String = "-";
                    if (n.tf != null)
                    {
                        var gf:Object = n.tf.getTextFormat();
                        if (gf != null && gf.color != null) rc = uint(gf.color).toString(16);
                    }
                    acc.push((n.key == null ? "-" : String(n.key)) + "=" + uint(c).toString(16)
                        + "/" + fc + "/" + rc);
                }
            }
            for (var i:int = 0; i < n.children.length; i++) this.walkInk(n.children[i], acc);
        }

        private function dumpRects(w:Number, h:Number, suffix:String):void
        {
            var keys:Array = ["root", "titlebar", "logo", "brand", "brandName", "brandSub",
                "theme", "min", "max", "close", "winbtns",
                "band", "slot", "library", "libHead", "libTitle", "libCount", "search",
                "searchField", "filters", "segAll", "segTuned", "libList", "r0", "ri0",
                "reader", "rToolbar", "hymnBadge", "minus", "plus", "rScroll", "rDoc",
                "titleBlock", "title0", "chips", "chipVerses",
                "bk0v", "bk1v", "bk2v", "bk3v", "bk1c",
                "rule0v", "g0v", "ls0v", "ls1v", "ln0_0v", "ln0_1v", "ln1_0v", "ln1_1v",
                "ln1_2v", "rule1v", "g1v", "d0v", "d1v", "d2v",
                "cls1c", "ln1_0c", "ln1_0cv", "ln1_0ct",
                "ln0_0vt", "ln1_0vt", "ln1_2vt",
                "player", "plLeft", "plTile", "plCenter", "plRight", "voices", "play",
                "instr", "map", "tEl", "tRem", "pauseAfter", "exp"];
            var txt:String = "stage " + w + "x" + h + "\n";
            // The SAME advance the view used to wrap with: when a label's solved width
            // disagrees with this number, the measurement is what is wrong, not the
            // layout -- which is what distinguishes a text-measure defect from a
            // sizing one without another build.
            txt = txt + "advAll=" + HymnWrap.width("All 1000", "Segoe UI", 12)
                + " advTuned=" + HymnWrap.width("With tune 239", "Segoe UI", 12) + "\n";
            var i:int = 0;
            for (i = 0; i < keys.length; i++)
            {
                var n:UiNode = this.app.findByKey(String(keys[i]));
                txt = txt + (n == null ? String(keys[i]) + ": MISSING\n"
                    : String(keys[i]) + ": " + n.absX + "," + n.absY + " " + n.absW + "x" + n.absH + "\n");
            }
            // THE PALETTE THE NODES RESOLVED, next to the one the PNG shows.
            // A screenshot alone cannot separate the two ways a theme switch fails:
            // a resolve that kept the old refinement (this line is right, the pixels
            // are right too -- the node was never rebuilt) versus a paint that never
            // ran on a fresh resolve (this line is right, the pixels are stale). The
            // 2026-11-12 light shot came out with dark panels and light-theme ink, and
            // this line is what proved the resolver had already handed out 0xFFFFFF --
            // so the fault was downstream. The `/same` flag is the diff baseline
            // identity: a shared Fill means the previous/resolved comparison can see no
            // change at all, because both buffers point at one object.
            var styled:Array = ["root", "reader", "title0", "chipVerses", "d0v", "ln0_0v", "tEl", "player"];
            txt = txt + "palette";
            for (i = 0; i < styled.length; i++)
            {
                var sn:UiNode = this.app.findByKey(String(styled[i]));
                txt = txt + " " + String(styled[i]) + "=";
                if (sn == null || sn.resolved == null) { txt = txt + "?"; continue; }
                var bg:Object = sn.resolved.background;
                txt = txt + (bg == null ? "-" : (Number(bg.rgb()) + ""));
                var pb:Object = sn.previous == null ? null : sn.previous.background;
                txt = txt + "/" + ((pb != null && pb == bg) ? "same" : "new");
            }
            txt = txt + "\n";
            // EVERY LIVE TEXT NODE'S RESOLVED INK. The palette line above only reads
            // BACKGROUNDS, and the dark-mode defect the user hit was ink-only: after
            // light->dark the panels swapped and a subset of the runs stayed at the light
            // theme's 0x14161C, i.e. dark on dark. Diffing this line between a run that
            // started dark and one that switched into dark separates "resolve kept the old
            // colour" from "the field never got the new one".
            var inks:Array = [];
            this.walkInk(this.app.getRoot(), inks);
            txt = txt + "ink " + inks.join(" ") + "\n";
            var acc:Object = { out: "", n: 0 };
            this.scan(this.app.getRoot(), 0, w, h, acc);
            txt = txt + "escaped " + acc.n + ": " + String(acc.out) + "\n";
            this.out(OUT + "-rects" + suffix + ".txt", txt);
        }

        private function scan(n:UiNode, depth:int, w:Number, h:Number, acc:Object):void
        {
            if (n == null || depth > 14) return;
            if (n.absW > 0 && n.absH > 0
                && (n.absX < -0.5 || n.absY < -0.5 || n.absX + n.absW > w + 0.5 || n.absY + n.absH > h + 0.5))
            {
                acc.n = int(acc.n) + 1;
                if (int(acc.n) <= 8)
                {
                    acc.out = String(acc.out) + "[" + String(n.key) + ":" + n.kind + " "
                        + n.absX + "," + n.absY + " " + n.absW + "x" + n.absH + "] ";
                }
            }
            for (var i:int = 0; i < n.children.length; i++)
            {
                this.scan(n.children[i], depth + 1, w, h, acc);
            }
        }

        // The opacity a block actually carries (1 when the style leaves it unset). Named
        // `opacityOf` rather than inlined so the probe reads the SAME `resolved` the
        // painter does, instead of re-deriving it from the model.
        private function opacityOf(key:String):String
        {
            var n:UiNode = this.app.findByKey(key);
            if (n == null || n.resolved == null) return "?";
            var v:Number = n.resolved.opacity;
            return isNaN(v) ? "1.00" : v.toFixed(2);
        }

        private function out(p:String, txt:String):void
        {
            var f:File = File.applicationDirectory.resolvePath(p);
            var fs:FileStream = new FileStream();
            fs.open(f, FileMode.WRITE);
            fs.writeUTFBytes(txt);
            fs.close();
        }

        // The keyboard test spans frames (the drawer has to re-render before its
        // field is in the tree again), so its readings live here between beats.
        private var kSide0:Boolean = true;
        private var kSideA:Boolean = true;
        private var kGuard0:int = 0;
        private var kGuard1:int = 0;
        private var kSel0:int = 0;
        private var kSel1:int = 0;
        private var kReveal:int = -1;
        private var kFollow:Number = 0;
        private var kVerse:int = 0;
        private var kDim:String = "-";
        private var kAudio:String = "";

        // The tap beat's readings, same reason: a tap and its effect are not in the
        // same frame (the click goes through the router and a possible press delay).
        private var cTheme0:String = "";
        private var cTheme1:String = "";
        private var cTheme2:String = "";
        private var cSize0:Number = 0;
        private var cSize1:Number = 0;
        private var cSize2:Number = 0;
        private var cTapSel0:int = -1;
        private var cTapSel1:int = -1;
        private var cTapHits:String = "";
    }
}
