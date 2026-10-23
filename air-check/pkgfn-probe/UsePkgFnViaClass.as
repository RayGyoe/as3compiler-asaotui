// air-check/pkgfn-probe/UsePkgFnViaClass.as -- probe B: this file FIRST pulls in
// p::Lib (so Lib.as is definitely compiled), and THEN imports the package-level
// function from that very file.
//
// If this compiles while probe A does not, then the rule is "a package-level
// function becomes importable once some class from its file is already in the
// compilation" -- which is a workable pattern (each file exposes a token class)
// but a fragile one to rely on silently. If it also fails, the pattern is simply
// unavailable and factories must be static methods on a class.
package
{
    import p.Lib;
    import p.hello;

    public class UsePkgFnViaClass
    {
        private var l:Lib;

        public function UsePkgFnViaClass():void
        {
            var s:String = hello();
        }
    }
}