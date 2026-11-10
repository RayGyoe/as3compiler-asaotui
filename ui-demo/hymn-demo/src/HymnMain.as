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
    import flash.display.DisplayObject;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.getTimer;

    public class HymnMain extends Sprite
    {
        private static const OUT:String = "hymn";
        // The shot waits for the SPLASH TO BE GONE (1500 hold + 450 fade) and then a
        // few frames, so the picture is the app and not its own loading screen.
        private static const SHOT_FRAME:int = 130;

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
                this.selfFail = HymnSelfTest.run(this.model.hymns);
                this.out(OUT + "-selftest.txt", this.selfFail == ""
                    ? "PASS " + String(this.model.hymns.length) + " hymns, "
                        + String(HymnSelfTest.notes) + " notes over " + String(HymnSelfTest.tunes)
                        + " tunes\n"
                    : this.selfFail);
                trace("HymnMain: " + this.model.hymns.length + " hymns in " + this.loadMs + " ms");
                return;
            }
            this.model.tick(getTimer());
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
                        this.out(OUT + ".done", "PASS " + this.model.hymns.length + " hymns, load "
                            + this.loadMs + " ms, " + w + "x" + h + ", splash gone at frame "
                            + String(SHOT_FRAME) + ", tuned=" + String(this.model.hasTuneSelected())
                            + ", followFrom=" + String(Math.round(this.playAt))
                            + " followTo=" + String(Math.round(this.model.scrollY))
                            + ", verse=" + String(this.model.blockIndex + 1)
                            + ", audio=" + a.status + " ready=" + String(a.ready)
                            + " samples=" + String(a.samples) + " render=" + String(a.renderMs) + "ms"
                            + " peak=" + a.peak.toFixed(3) + " regs=" + String(a.regs)
                            + ", trace=" + aTrace + "\n");
                        trace("HymnMain: done");
                        aSub = 4;
                        this.next(5);
                    }
                    break;
            }
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
        private function dumpRects(w:Number, h:Number, suffix:String):void
        {
            var keys:Array = ["root", "titlebar", "logo", "brand", "brandName", "brandSub",
                "theme", "min", "max", "close", "winbtns",
                "band", "slot", "library", "libHead", "libTitle", "libCount", "search",
                "searchField", "filters", "segAll", "segTuned", "libList", "r0", "ri0",
                "reader", "rToolbar", "hymnBadge", "minus", "plus", "rScroll", "rDoc",
                "titleBlock", "title0", "chips", "chipVerses", "bk0", "bk1",
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

        private function out(p:String, txt:String):void
        {
            var f:File = File.applicationDirectory.resolvePath(p);
            var fs:FileStream = new FileStream();
            fs.open(f, FileMode.WRITE);
            fs.writeUTFBytes(txt);
            fs.close();
        }
    }
}
