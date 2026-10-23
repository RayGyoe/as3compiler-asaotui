// asaot.ui.image -- the author-facing factory for ImageNode (see ImageNode.as for
// why the file is lowercase, the class is not, and why the source is a BitmapData).
//
//   image({ key: "pic", bitmapData: bd, scaleMode: "fit", size: [120, 80] })
//
// With no explicit `size`, the intrinsic size IS the bitmap's, which is what makes
// an image usable inside a row without measuring anything.
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
            if (opts.scaleMode != null) n.scaleMode = String(opts.scaleMode);
            if (opts.smooth != null) n.smooth = Boolean(opts.smooth);
        }
        return n;
    }
}
