// probes/g14-minimal/Marker.as -- the `is` target that turns the bug into a crash.
//
// Deliberately trivial: it only has to be a USER class with its own vtable, so that
// `o is Marker` compiles to `as_is(o, &Marker_vt)` and the runtime has to read
// something out of `o`. Any user class does (see compiler-gaps.md G14).
package
{
    public class Marker
    {
        public var tag:int = 7;
    }
}
