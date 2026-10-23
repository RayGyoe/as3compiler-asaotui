// asaot.ui.Widgets -- the kind -> Widget registry (see Widget.as for the why).
//
// Keyed by the same `String` that ends up in `Node.kind`, so the reconciler's
// existing kind plumbing is untouched.
package asaot.ui
{
    public class Widgets
    {
        private static var registry:Object = {};

        public static function register(kind:String, w:Widget):void
        {
            registry[kind] = w;
        }

        // Loud on miss. A widget whose Node class forgot to register would
        // otherwise render as an invisible, unclickable hole -- the "compiles and
        // runs but silently wrong" failure AGENTS.md section 2.5 forbids.
        public static function require(kind:String):Widget
        {
            var w:Widget = registry[kind];
            if (w == null)
            {
                throw new Error("asaot.ui: no Widget registered for kind '" + kind
                    + "'. Its Node class must call Widgets.register() from its constructor"
                    + " (see kit/asaot/ui/kind/).");
            }
            return w;
        }

        public static function has(kind:String):Boolean
        {
            return registry[kind] != null;
        }
    }
}