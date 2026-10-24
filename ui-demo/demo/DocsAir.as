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
package demo
{
    import asaot.ui.Dirty;
    import asaot.ui.UiApp;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.events.Event;

    public class DocsAir extends Sprite
    {
        private var model:DocsModel;
        private var app:UiApp;

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

            // Land on the first page; the window's first frame is painted after this
            // returns to AIR's event loop.
            this.model.doc = "start";
            this.app.invalidate(Dirty.ALL);
            this.app.reflow();
        }
    }
}