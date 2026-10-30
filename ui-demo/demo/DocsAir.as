// DocsAir.as -- the documentation app as the AIR runtime runs it (`mxmlc` -> `adl`).
//
// WHY A SECOND ENTRY POINT EXISTS
// -------------------------------
// `DocsMain` is the AOT document class AND its headless acceptance tour. The tour
// needs three hooks that only our AOT provides -- `Stage.dispatchMouse`,
// `Stage.dispatchWheel`, `Stage.render` -- so `mxmlc` rejects that file outright
// ("通过静态类型为 Stage 的引用来调用的方法 dispatchMouse 可能未定义"). Those hooks are
// not AS3 API; they are the test seams a headless tour is built on, and AIR has no
// such thing (an AIR window is driven by the OS, not by the app).
//
// So the AIR arm gets the APP and none of the tour: this class mounts the same
// `DocsModel` + `DocsView` + `UiApp`, lands on the same first page, and then gets out
// of the way. That is exactly the split the project measures everywhere else
// ("AIR is the reference"): what AIR shows here is the reference picture a human can
// click through, and the AOT arm is the one that also proves itself with rects.
//
// THE WIRING IS NOT OPTIONAL and is deliberately identical to DocsMain.onAdded:
// a widget reports to the MODEL, the model notifies, and `app.invalidate` is what
// turns a notify into a repaint. Dropping that subscription leaves a window that
// looks right on the first frame and then never reacts to a click.
//
// The window itself (size, title, renderMode, requestedDisplayResolution) comes from
// `../air-gallery/app.xml`; nothing here calls `Stage.showWindow`.
//
// THE DRIVER FILE (why this class reads and writes files at all)
// -------------------------------------------------------------
// AIR cannot script a click, so the two things a human does in this window -- pick a
// page, open a popup -- are the two things a check cannot do. A command line would be
// the natural way to say "start on this page", and mxmlc REJECTS it here: reading
// `NativeApplication.argv` fails to compile ("accessing the possibly-undefined
// property argv through a reference with static type NativeApplication" -- measured,
// AIR SDK 51.4.1). A sidecar file is the channel that works, and it is the same one
// the probe harness already uses (a `.done` file).
//
//     ui-demo/air-gallery/air-mode.txt, first line, whitespace-separated:
//         <mode> [<log path>]
//
//         <mode> absent     -> the first page (what `build.sh` opens)
//         <mode> = page id  -> that page, straight away   (`build.sh air select`)
//         <mode> = sweep    -> every page in turn, 120 ms each, then quit
//         <log path>        -> where the run log goes; default is `air-trace.txt`
//                              next to this app's descriptor
//         open=<k,k,...>    -> demo state keys whose popup is opened for one tick
//                              on every page, then shut again (`sweep` only)
//
// WHY THE SWEEP OPENS THE POPUPS ITSELF
// -------------------------------------
// The pages do not start with a dropdown open -- `select({ open: model.planOpen })`
// reads a demo key that is false until someone clicks. AIR cannot click (see above),
// so without this step the sweep would visit 41 correct pages and never reach the one
// state that is broken: a popup that LIFTS its owner out of the parent's display list
// while a later sibling still expects a slot in it. Flipping the model key is exactly
// what the docs page itself tells the reader to do ("open: true -- the boolean is the
// model's"), so it exercises the real path, not a back door. The key list is supplied
// by the gate, which derives it from the demo sources (`m.bool("<x>.open")`), so a new
// openable demo is covered without editing this file.
//
// `sweep` is `tools/air-sweep.cjs`: the ONLY gate that runs the REFERENCE runtime. It
// exists because AIR is the authority we align to -- error numbers, error TEXT, event
// ordering, text metrics -- and because "we measured that contract once" is not the same
// as "we still implement it". Two gaps in this very file's history were found only here:
// `setChildIndex` clamping an out-of-range index instead of throwing #2006 (G24) and the
// runtime never dispatching roll events (G25); both were fixed in v0.4.239, and the gate
// is what keeps them fixed. One run of the real runtime over every page is the cheap way
// to notice the next one.
//
// WHY THE RUN LOG IS A FILE AND NOT trace()
// -----------------------------------------
// `adl.exe` on Windows is a GUI-subsystem binary: a parent that spawns it with pipes
// gets an EMPTY stream while the window is up and traces are being produced (measured
// -- the reason the first version of the sweep could not see a single line). So the app
// writes its own log:
//
//     START
//     OPENED <n>                       (once; counted from the model after the flip)
//     PAGE <id>                        (before each switch)
//     ROLL <from> hovered=<h> destroyed=<d> errors=<e>     (one per page; see captureHover)
//     ROLLFAIL <from> <kind> <error>   (a roll-out at a torn-down node threw)
//     ERROR <page> <Class>: <message>  [+ `  at ...` stack lines]
//     SWEEP DONE <n>
//     END errors=<n>
//
// Errors come from `loaderInfo.uncaughtErrorEvents`, i.e. exactly the errors AIR would
// otherwise print and forget -- the shape a library bug has. An uncaught error does NOT
// stop the sweep, so one run names every broken page instead of only the first.
//
// The log path is passed in (or built as a plain absolute path) because a File obtained
// from `File.applicationDirectory` is READ-ONLY even under adl: opening it for writing
// throws `fileWriteResource` (#3003). The same path built as `new File("C:/.../x.txt")`
// writes fine -- measured, both halves.
package demo
{
    import asaot.ui.Dirty;
    import asaot.ui.UiApp;
    import asaot.ui.UiNode;
    import flash.desktop.NativeApplication;
    import flash.display.DisplayObject;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import flash.events.TimerEvent;
    import flash.events.UncaughtErrorEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.Timer;

    public class DocsAir extends Sprite
    {
        private var model:DocsModel;
        private var app:UiApp;
        private var sweepTimer:Timer;
        private var pages:Array;
        private var sweepIndex:int;
        private var sweepStep:int;      // 0 = land, 1 = open the popups, 2 = shut them
        private var openKeys:Array;
        // [[node, backing], ...] captured while the pointer is "over" a node -- see
        // captureHover/dispatchRoll.
        private var rolled:Array;
        private var rollFrom:String;
        private var logFile:File;
        private var errorCount:int;

        public function DocsAir():void
        {
            addEventListener(Event.ADDED_TO_STAGE, onAdded);
        }

        private function onAdded(e:Event):void
        {
            removeEventListener(Event.ADDED_TO_STAGE, onAdded);

            this.model = new DocsModel();
            var view:DocsView = new DocsView(this.model);
            // The shell lays itself out from the stage it is given (UiApp reflows on
            // RESIZE), so pinning the scale mode is all that is needed for the
            // logical coordinates to match the descriptor's window size.
            this.stage.scaleMode = StageScaleMode.NO_SCALE;
            this.stage.align = StageAlign.TOP_LEFT;
            this.app = new UiApp(view);
            var self:DocsAir = this;
            this.model.subscribe(function (d:int):void { self.app.invalidate(d); });
            this.app.mount(this.stage);
            this.app.attachRoot();

            var req:Array = requestedMode();          // [mode, logPath, openKeys]
            var mode:String = req[0];
            this.logFile = File.applicationDirectory.resolvePath(req[1] != null ? String(req[1]) : defaultLogPath());
            this.openKeys = req[2] != null ? String(req[2]).split(",") : [];
            this.errorCount = 0;

            // Registered even for an ordinary launch: an uncaught error is a bug in
            // either case, and this file is the only place it survives.
            this.loaderInfo.uncaughtErrorEvents.addEventListener(
                UncaughtErrorEvent.UNCAUGHT_ERROR,
                function (pe:UncaughtErrorEvent):void { selfRecordError(pe); });

            // Land on the requested page (or the first one); the window's first frame
            // is painted after this returns to AIR's event loop.
            this.model.doc = isPage(mode) ? mode : "start";
            this.app.invalidate(Dirty.ALL);
            this.app.reflow();
            if (mode == "sweep")
            {
                selfLog("START");
                this.startSweep();
            }
        }

        // [mode, logPath, openKeys]. No file (or one that says nothing) means "no
        // request", which is the ordinary launch -- and a typo must not leave a blank
        // window.
        private function requestedMode():Array
        {
            var out:Array = ["", null, null];
            var f:File = File.applicationDirectory.resolvePath("air-mode.txt");
            if (!f.exists) return out;
            var s:FileStream = new FileStream();
            try
            {
                s.open(f, FileMode.READ);
                var words:Array = s.readUTFBytes(s.bytesAvailable).split(/\s+/);
                var kept:Array = [];
                for (var i:int = 0; i < words.length; i++)
                {
                    if (String(words[i]).length > 0) kept.push(String(words[i]));
                }
                if (kept.length > 0) out[0] = kept[0];
                if (kept.length > 1 && String(kept[1]).indexOf("open=") != 0) out[1] = kept[1];
                for (var j:int = 0; j < kept.length; j++)
                {
                    var w:String = String(kept[j]);
                    if (w.indexOf("open=") == 0) out[2] = w.substring(5);
                }
            }
            catch (e:Error)
            {
                return ["", null, null];
            }
            finally
            {
                s.close();
            }
            return out;
        }

        // `air-trace.txt` next to the descriptor, spelled as a plain path -- see the
        // header note about `File.applicationDirectory` being read-only.
        private function defaultLogPath():String
        {
            var dir:String = File.applicationDirectory.nativePath;
            var sep:String = dir.indexOf("\\") >= 0 ? "\\" : "/";
            return dir + sep + "air-trace.txt";
        }

        private function isPage(id:String):Boolean
        {
            if (id == null) return false;
            var list:Array = DocsCatalog.pages();
            for (var i:int = 0; i < list.length; i++)
            {
                if (DocPage(list[i]).id == id) return true;
            }
            return false;
        }

        // Walk the catalog, one page per tick. A TIMER (not ENTER_FRAME arithmetic)
        // because a page needs more than one frame to settle -- the first frames after
        // a switch are the ones where the reconciler inserts nodes and repairs display
        // order, which is exactly where AIR throws and we do not.
        private function startSweep():void
        {
            this.pages = DocsCatalog.pages();
            this.sweepIndex = 0;
            this.sweepStep = 0;
            this.sweepTimer = new Timer(120);
            this.sweepTimer.addEventListener(TimerEvent.TIMER, function (te:TimerEvent):void { selfAdvance(); });
            this.sweepTimer.start();
        }

        // Three ticks per page: land, open the popups, shut them again. Without the
        // open/shut ticks the sweep would only ever see the closed state, which is the
        // state that WORKS (see the header note).
        //
        // Step 0 puts the POINTER down on the page it is about to leave and step 1
        // delivers the roll-out one tick later, after the reconciler has replaced the
        // tree -- see captureHover. That is the fourth thing this sweep measures, and
        // the only one that needs a pointer.
        private function selfAdvance():void
        {
            if (this.sweepStep == 0)
            {
                if (this.sweepIndex >= this.pages.length)
                {
                    selfLog("SWEEP DONE " + this.pages.length);
                    selfLog("END errors=" + this.errorCount);
                    this.sweepTimer.stop();
                    // The point of the sweep is the log file; a window left open would
                    // make a gate wait for its own timeout instead of the verdict.
                    NativeApplication.nativeApplication.exit(0);
                    return;
                }
                // Hover BEFORE the switch: a page change replaces the whole node tree,
                // so every node captured here dies in the next frame.
                this.captureHover();
                this.rollFrom = String(this.model.doc);
                var id:String = DocPage(this.pages[this.sweepIndex]).id;
                selfLog("PAGE " + id);
                this.model.doc = id;
                this.model.notify(Dirty.ALL);
                this.sweepStep = 1;
                return;
            }
            if (this.sweepStep == 1)
            {
                // One tick after the switch the reconciler has run, so the captured
                // nodes are gone and this is the delivery that used to throw #1009.
                this.dispatchRoll();
                this.sweepStep = this.openKeys.length > 0 ? 2 : 4;
                return;
            }
            if (this.sweepStep == 2)
            {
                this.flipOpen(true);
                this.sweepStep = 3;
                return;
            }
            if (this.sweepStep == 3)
            {
                this.flipOpen(false);
                this.sweepStep = 4;
                return;
            }
            this.sweepIndex = this.sweepIndex + 1;
            this.sweepStep = 0;
        }

        // `put` is the model's own write path (notify(VALUE) -> invalidate -> the next
        // frame re-describes), so the popup opens the way a click would open it.
        private function flipOpen(v:Boolean):void
        {
            for (var i:int = 0; i < this.openKeys.length; i++)
            {
                this.model.put(String(this.openKeys[i]), v);
            }
            // MEASURE the flip instead of trusting the call. The gate requires this
            // number to equal the key count: a sweep whose open step stopped working
            // would still visit 41 correct pages and look green while never exercising
            // the lifted state -- which is the only state this sweep exists for.
            if (v && this.sweepIndex == 0)
            {
                var on:int = 0;
                for (var j:int = 0; j < this.openKeys.length; j++)
                {
                    if (this.model.bool(String(this.openKeys[j]), false)) on = on + 1;
                }
                selfLog("OPENED " + on);
            }
        }

        // ---- the pointer, for the library's sake --------------------------
        // AIR cannot be scripted to click, so this was the blind spot that let a whole
        // class of crash through: EVERY pointer-driven bug (hover, press, drag) needs a
        // pointer, and the sweep had none. It does not need the OS pointer though -- it
        // needs the EVENTS, and those are dispatched from here.
        //
        // The sequence is the one that threw TypeError #1009 in the wild (reported on
        // the accordion page, reproduced by clicking around): an event arrives at the
        // object that WAS under the pointer ONE BEAT AFTER the frame that removed it --
        // AIR finishes the frame first and only then recomputes the pointer's target.
        // If the node was torn down in between, the listener used to run into a nulled
        // field.
        //
        // 2026-10-26: the library no longer installs per-object ROLL listeners. Hover is
        // DERIVED from ONE stage MOUSE_MOVE using the click's own hit test, so both arms
        // run the same code -- which is a design choice, not a workaround: G25 was fixed
        // in v0.4.239 and roll events do arrive now. The hazard did not go away, it
        // moved: a backing still carries its DOWN/UP/CLICK listeners until
        // destroySubtree takes them off, and AIR can deliver to a removed object. So the
        // drill CAPTURES every leaf of both trees (main + overlay) before the page
        // switch, then delivers CLICK + MOUSE_DOWN one tick later to the ones that
        // REALLY died -- and never to a live one, because a live click would mutate the
        // page under test. `destroyed=` still counts the torn-down nodes: if it fell to
        // nothing the drill stopped biting, and the gate fails instead of grading a
        // blind test.
        private function captureHover():void
        {
            this.rolled = [];
            this.hoverLeaves(this.app.getRoot());
            var ov:UiNode = this.app.getOverlayRoot();
            if (ov != null) this.hoverLeaves(ov);
        }

        // A HANDFUL of nodes would make the delivery happen; every leaf is what makes
        // the drill measurable. First run, 2026-10-24: 3107 nodes captured over the
        // catalog and 348 of them really were destroyed by the page switches, so the
        // number the gate grades is a measurement of this app, not of this comment.
        private function hoverLeaves(n:UiNode):void
        {
            if (n == null || n.backing == null) return;
            if (n.children.length == 0)
            {
                // The BACKING is kept, not just the node: destroySubtree nulls the
                // node field, and it is the display object that AIR delivers to.
                this.rolled.push([n, n.backing]);
                return;
            }
            for (var i:int = 0; i < n.children.length; i++) this.hoverLeaves(n.children[i]);
        }

        private function dispatchRoll():void
        {
            if (this.rolled == null) return;
            var dead:int = 0;
            var failed:int = 0;
            for (var i:int = 0; i < this.rolled.length; i++)
            {
                var pair:Array = this.rolled[i] as Array;
                var n:UiNode = UiNode(pair[0]);
                var bak:DisplayObject = pair[1] as DisplayObject;
                // `app == null` is the library's own "torn down" marker.
                if (n.app != null) continue;
                dead = dead + 1;
                try
                {
                    bak.dispatchEvent(new MouseEvent(MouseEvent.CLICK));
                    bak.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_DOWN));
                }
                catch (err:Error)
                {
                    // A caught error does NOT reach uncaughtErrorEvents, so this gate
                    // would otherwise report a clean sweep over a throwing delivery.
                    failed = failed + 1;
                    selfLog("TEARDOWNFAIL " + this.rollFrom + " " + n.kind + " " + err.name + ": " + err.message);
                }
            }
            selfLog("TEARDOWN " + this.rollFrom + " captured=" + this.rolled.length
                + " destroyed=" + dead + " errors=" + failed);
            this.rolled = null;
        }

        private function selfRecordError(e:UncaughtErrorEvent):void
        {
            var err:Object = e.error;
            this.errorCount = this.errorCount + 1;
            var line:String = "ERROR " + this.model.doc + " ";
            if (err is Error)
            {
                line = line + String(Error(err).name) + ": " + String(Error(err).message);
            }
            else
            {
                line = line + "" + err;
            }
            selfLog(line);
            var st:String = err is Error ? String(Error(err).getStackTrace()) : null;
            if (st != null)
            {
                var rows:Array = st.split("\n");
                for (var i:int = 0; i < rows.length && i < 6; i++) selfLog("  at " + String(rows[i]));
            }
        }

        // Append one line. Open/close per line: 42 pages plus a handful of errors is
        // nothing next to a process launch, and a crash cannot lose output that was
        // never flushed.
        private function selfLog(line:String):void
        {
            if (this.logFile == null) return;
            var s:FileStream = new FileStream();
            try
            {
                s.open(this.logFile, FileMode.APPEND);
                s.writeUTFBytes(line + "\n");
            }
            catch (e:Error)
            {
                // A log that cannot be written must not take the app down with it.
            }
            finally
            {
                s.close();
            }
        }
    }
}