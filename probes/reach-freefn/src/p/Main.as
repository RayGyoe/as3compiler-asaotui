// p.Main -- the document class. It names NO type except itself, on purpose:
// `Leaf` must be reached ONLY through the forced file, so the closure's post-loop
// pass is the only way in. A type annotation like `var l:Leaf` would put Leaf in
// the MAIN loop's queue and mask the defect.
//
// The call is a bare `make()` (a free function in p/Fac.as), which is how AS3
// reaches a top-level function in the same package -- `Fac.make()` is not legal
// AS3 (Fac is a file, not a namespace you can qualify from another file) and our
// compiler correctly rejects it.
package p
{
    import flash.display.Sprite;

    public class Main extends Sprite
    {
        public function Main():void
        {
            make();
        }
    }
}