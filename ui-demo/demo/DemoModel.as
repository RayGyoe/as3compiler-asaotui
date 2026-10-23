// demo/DemoModel.as -- the demo's observable model (Deliverable 2).
//
// Shared by the AOT driver (demo/UiDemoMain.as) and the AIR driver (UiDemoAir.as). The
// split into a NAMED package (rather than the default package) is deliberate:
// mxmlc cannot resolve a default-package class imported from another file, while
// our AOT needs an explicit import -- a named package satisfies both.
package demo
{
    import asaot.ui.Observable;

    public class DemoModel extends Observable
    {
        public var account:String = "dev@example.com";
        public var password:String = "";
        public var remember:Boolean = false;
        public var status:String = "status: ready";

        public function DemoModel():void
        {
            super();
        }
    }
}