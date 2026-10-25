// asaot.ui.ImageNode -- a picture, fitted into its solved rect.
//
// Copy of the ChipNode recipe: class `ImageNode`, lowercase factory `image.as`
// (compiler-gaps.md G7), `role` mandatory, self-registration once from the ctor.
//
// TWO SOURCES, ONE WIDGET
// -----------------------
//   bitmapData -- pixels the caller already has (an [Embed], an SWC symbol, a
//                 procedural BitmapData). Nothing is loaded, nothing is async.
//   src        -- a URL or a path, loaded through `flash.display.Loader` by the
//                 widget itself (see ImageWidget for the state machine).
//
// `src` exists because "I have a file name" is the common case and hand-rolling a
// Loader per call site (plus its COMPLETE/IO_ERROR wiring, plus the torn-down-node
// guard) is exactly the kind of code that gets the async part wrong once per app.
// It is also the only place the library owns runtime I/O, so the contract is
// spelled out here:
//
//   * the path is resolved by the RUNTIME, relative to the process's working
//     directory (that is what adl and the AOT both do for a relative
//     URLRequest). A build with a local file read only -- no libcurl -- reports
//     IOError #2035/#2036 through `onError` instead of hanging;
//   * while a load is in flight the widget keeps the placeholder geometry
//     (the author's `size`, else 64x64) and the intrinsic size is unknown, so an
//     auto-sized image must be given a size or it will jump when the pixels land;
//   * a COMPLETED load marks the node for re-measure, so an auto-sized image
//     grows to the real pixel size on the following frame;
//   * `bitmapData` wins over `src` when both are set: the caller who hands over
//     pixels is not asking for a network fetch.
//
// SCALE MODES ARE FOUR, AND UNKNOWN ONES THROW. "fit" (contain, the default),
// "stretch" (fill the box, aspect ignored), "none" (1:1, centred) and "cover"
// (fill the box, aspect preserved, the overflow CLIPPED).
//
// "cover" landed on 2026-10-26, along with the machinery that makes it honest: the
// widget writes a `scrollRect` window of exactly the content box onto the Bitmap, so
// the overflow is really clipped rather than painted outside its own box (and the
// clip is part of the parent's render fingerprint, so a resize repaints). The note
// this file carried before that -- "clipping is the scrollView's job, so a cover
// mode is refused" -- described the toolkit before `scrollRect` was used for a
// single object; the scrollView owns a viewport of a SUBTREE, which is a different
// problem. "letterbox"/"zoom" still throw: both used to fall into the contain
// branch, and "zoom" (which reads as cover) did not zoom at all.
//
// ARITY IS PART OF THE CONTRACT (see UiNode's payload block, AVM2 throws #1063):
//   onLoad()          -- no arguments. Fired once per successful load.
//   onError(message)  -- exactly one: the IOError's own text (which carries AIR's
//                        error number, e.g. "Error #2035: URL not found...").
package asaot.ui
{
    import asaot.ui.kind.ImageWidget;

    import flash.display.BitmapData;

    public class ImageNode extends Element
    {
        public var bitmapData:BitmapData;
        // A URL or a file path for Loader.load; null when the pixels are supplied.
        public var src:String;
        // "fit" (contain, the default) | "stretch" | "none" (1:1, centred) |
        // "cover" (fill, aspect preserved, clipped to the content box).
        public var scaleMode:String;
        public var smooth:Boolean;
        // See the arity block in the header.
        public var onLoad:Function;
        public var onError:Function;

        private static var registered:Boolean = false;

        // Unknown VALUES throw rather than falling back to "fit": a silently ignored
        // `scaleMode: "zoom"` is a picture at the wrong size with nothing on screen
        // saying why (AGENTS.md 2.5). Called from the factory, i.e. at describe time,
        // where the author still has a call site to fix.
        public static function checkScaleMode(v:String):String
        {
            if (v == "fit" || v == "stretch" || v == "none" || v == "cover") return v;
            throw new Error("asaot.ui: scaleMode \"" + v + "\" is not supported (accepted: fit, stretch, none, cover)");
        }

        public function ImageNode():void
        {
            super("image");
            if (!registered) { registered = true; Widgets.register("image", new ImageWidget()); }
            this.role = "img";
            this.bitmapData = null;
            this.src = null;
            this.scaleMode = "fit";
            this.smooth = true;
            this.onLoad = null;
            this.onError = null;
        }
    }
}