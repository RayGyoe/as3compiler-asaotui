// probes/asmdef-rule/UseLib.as -- the mxmlc-facing driver for the illegal shape.
package
{
    import p.Lib;

    public class UseLib
    {
        private var l:Lib;
        public function UseLib():void { this.l = new Lib(); }
    }
}
