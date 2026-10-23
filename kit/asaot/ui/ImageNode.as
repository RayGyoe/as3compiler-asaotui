// asaot.ui.ImageNode -- a bitmap, fitted into its solved rect.
//
// Copy of the ChipNode recipe: class `ImageNode`, lowercase factory `image.as`
// (compiler-gaps.md G7), `role` mandatory, self-registration once from the ctor.
//
// WHY THE SOURCE IS A `BitmapData` AND NOT A URL
// ----------------------------------------------
// This library is pure AS3 with no loader layer, and every demo is built with
// `--air-app`, where an embedded resource arrives as a `BitmapData` anyway. So the
// widget takes the pixels the caller already has, and loading stays the caller's
// business (`flash.display.Loader`, an SWC symbol, or a procedurally built
// BitmapData). Handing it a path would mean inventing a loading story this library
// does not have; AGENTS.md section 2.5 forbids silently doing half of it.
package asaot.ui
{
    import asaot.ui.kind.ImageWidget;

    import flash.display.BitmapData;

    public class ImageNode extends Element
    {
        public var bitmapData:BitmapData;
        // "fit" (contain, the default) | "stretch" | "none" (1:1, centred).
        // There is no "fill"/cover: covering a box means clipping, which is the
        // scrollView's job, not a scale mode this widget can honour without one.
        public var scaleMode:String;
        public var smooth:Boolean;

        private static var registered:Boolean = false;

        public function ImageNode():void
        {
            super("image");
            if (!registered) { registered = true; Widgets.register("image", new ImageWidget()); }
            this.role = "img";
            this.bitmapData = null;
            this.scaleMode = "fit";
            this.smooth = true;
        }
    }
}
