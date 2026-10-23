// air-check/Hello.as -- the smallest possible AIR smoke test.
//
// Purpose: prove the AIR SDK on THIS machine can compile (mxmlc) and run (adl)
// at all, before pointing it at the real seam. If this does not print
// AIR-HELLO-OK, nothing else in air-check/ is meaningful.
//
// WHY A Sprite ROOT CLASS INSTEAD OF A TOP-LEVEL SCRIPT: mxmlc resolves the
// document class by FILE NAME, so `Hello.as` must actually declare `class
// Hello` -- a bare top-level script fails with "cannot load the SWF's root
// class: Hello". Our own AOT accepts both forms, so the library files are
// unaffected; only this harness driver is written as a class.
//
// WHY exit() IS MANDATORY HERE: an AIR app keeps its event loop alive by
// default, so `adl app.xml` never returns and any harness that waits on it
// hangs forever. Measured: without this line adl ran for 900 s and had to be
// killed. NativeApplication.exit() is also what our own AOT registers, so the
// same driver form stays compilable by both toolchains.
package
{
    import flash.display.Sprite;
    import flash.desktop.NativeApplication;

    public class Hello extends Sprite
    {
        public function Hello()
        {
            trace('AIR-HELLO-OK');
            NativeApplication.nativeApplication.exit();
        }
    }
}