// air-check/pkgfn-probe/UseLibOnly.as -- control: import ONLY the class from the
// same file, no package-level function involved.
//
// If this compiles, the source-path setup is right and probe A/B really do isolate
// the package-level-function question. If this ALSO fails, then nothing about the
// package-level-function result can be trusted and the probe setup needs fixing
// first. A control that is not run is a control you do not have.
package
{
    import p.Lib;

    public class UseLibOnly
    {
        private var l:Lib;

        public function UseLibOnly():void
        {
            this.l = new Lib();
        }
    }
}