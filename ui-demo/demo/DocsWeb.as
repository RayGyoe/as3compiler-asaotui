// DocsWeb.as -- the documentation app as a BROWSER page (`--target wasm --package web`).
//
// WHY A THIRD ENTRY POINT
// -----------------------
// The tree already has two, for two different reasons, and this is the third:
//
//   DocsMain   our AOT document class AND its headless acceptance tour. The tour
//              drives the app through `Stage.dispatchMouse` / `Stage.dispatchWheel`
//              / `Stage.render` -- seams only our native AOT provides -- and writes
//              `gallery.txt` + `gallery.done` to the filesystem.
//   DocsAir    the AIR arm: same model + view + UiApp, no tour (mxmlc rejects
//              DocsMain outright). It also reads a sidecar driver file through
//              `flash.filesystem` and reports through `UncaughtErrorEvent`.
//   DocsWeb    this file. Nothing to drive, nothing to log, no file channel: a
//              browser page is looked at by a human and clicked with a real mouse,
//              which is exactly the interaction the AOT tour has to fake. Both of
//              the hooks the other two entries rely on are absent here -- the
//              browser has no writable app directory to drop a `.done` file in and
//              no process to exit -- and `UncaughtErrorEvent` is not a class this
//              compiler knows, so DocsAir does not even compile for wasm.
//
// WHAT IS DELIBERATELY IDENTICAL
// ------------------------------
// The wiring below is byte-for-byte the wiring DocsMain.onAdded does before its
// tour starts: a widget reports to the MODEL, the model notifies, and
// `app.invalidate` is what turns that notify into a repaint. Dropping the
// subscription leaves a page that looks right on the first frame and then never
// reacts to a click -- the exact defect the tour was written to catch, which a
// browser page would show to a human instead. Keep these three lines in step.
//
// The window (canvas size, title) comes from `air-gallery/app.xml`, which the web
// arm copies into its own app directory -- see ui-demo/web-gallery.cjs. Nothing
// here calls `Stage.showWindow`; `--air-app`'s generated bootstrap does.
package demo
{
    import asaot.ui.Dirty;
    import asaot.ui.UiApp;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.events.Event;

    public class DocsWeb extends Sprite
    {
        private var model:DocsModel;
        private var app:UiApp;

        public function DocsWeb():void
        {
            addEventListener(Event.ADDED_TO_STAGE, onAdded);
        }

        private function onAdded(e:Event):void
        {
            removeEventListener(Event.ADDED_TO_STAGE, onAdded);

            this.model = new DocsModel();
            var view:DocsView = new DocsView(this.model);
            // The shell lays itself out from the stage it is given, so pinning the
            // scale mode is all the logical coordinates need: the canvas is the
            // descriptor's width x height, one CSS pixel per logical pixel.
            this.stage.scaleMode = StageScaleMode.NO_SCALE;
            this.stage.align = StageAlign.TOP_LEFT;
            this.app = new UiApp(view);
            // The data flow is not optional -- see the header.
            var self:DocsWeb = this;
            this.model.subscribe(function (d:int):void { self.app.invalidate(d); });
            this.app.mount(this.stage);
            this.app.attachRoot();

            // Land on the first page. From here on the sidebar, the widgets and the
            // content pane's wheel are the browser's real mouse events.
            this.model.doc = "start";
            this.app.invalidate(Dirty.ALL);
            this.app.reflow();
        }
    }
}