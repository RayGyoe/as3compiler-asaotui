// asaot.ui.image -- the author-facing factory for ImageNode (see ImageNode.as for
// why the file is lowercase, the class is not, and where the pixels come from).
//
//   image({ key: "pic", bitmapData: bd, scaleMode: "fit", size: [120, 80] })
//   image({ key: "avatar", src: "avatar.png", size: [40, 40], scaleMode: "stretch",
//           onLoad: function ():void { ... },
//           onError: function (msg:String):void { ... } })
//
// With no explicit `size`, the intrinsic size IS the bitmap's, which is what makes
// an image usable inside a row without measuring anything. That holds for `src`
// too, but only AFTER the load lands -- give an async image a size if it is not
// allowed to jump.
//
// `scaleMode` is validated here (fit | stretch | none, else THROW): an unknown mode
// would otherwise render as "fit" with nothing saying why.
package asaot.ui
{
    import flash.display.BitmapData;

    public function image(opts:Object = null):Node
    {
        var n:ImageNode = new ImageNode();
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "image";
        if (opts != null)
        {
            if (opts.bitmapData != null) n.bitmapData = BitmapData(opts.bitmapData);
            if (opts.src != null) n.src = String(opts.src);
            if (opts.scaleMode != null) n.scaleMode = ImageNode.checkScaleMode(String(opts.scaleMode));
            if (opts.smooth != null) n.smooth = Boolean(opts.smooth);
            if (opts.onLoad != null) n.onLoad = opts.onLoad as Function;
            if (opts.onError != null) n.onError = opts.onError as Function;
        }
        return n;
    }
}