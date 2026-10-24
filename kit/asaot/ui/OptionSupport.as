// asaot.ui.OptionSupport -- the shared plumbing behind the factory functions
// (design doc section 4.2).
//
// WHY A CLASS AND NOT PACKAGE-LEVEL HELPERS: mxmlc (the AIR reference compiler)
// resolves a package-level function only from a file NAMED after it, so free
// helper functions shared across several factories cannot be resolved. Grouping
// them as statics on one class sidesteps that without changing the public
// factory surface. (Our AOT resolves free functions either way.)
package asaot.ui
{
    import asaot.ui.style.StyleRefinement;

    public class OptionSupport
    {
        public static function opt(opts:Object, name:String, dflt:String):String
        {
            if (opts == null) return dflt;
            var v:Object = opts[name];
            return v == null ? dflt : String(v);
        }

        public static function applyOpts(n:Element, opts:Object):void
        {
            if (opts == null) return;
            if (opts.key != null) n.key = opts.key;
            // `style` is the explicit partial; otherwise the shorthand keys in
            // `opts` themselves (size, gap, padding, background, text, ...) are
            // read by StyleRefinement.from, which ignores key/role/ariaName/etc.
            if (opts.style != null) n.style = StyleRefinement(opts.style);
            else n.style = StyleRefinement.from(opts);
            if (opts.keyContext != null) n.keyContext = String(opts.keyContext);
            if (opts.role != null) n.role = String(opts.role);
            if (opts.ariaName != null) n.ariaName = String(opts.ariaName);
            if (n.ariaName == null) n.ariaName = "";
            if (opts.visible != null) n.visible = Boolean(opts.visible);
            // `disabled` is an Element property, so EVERY factory gets it through
            // this one line -- no factory needs to know about it.
            if (opts.disabled != null) n.disabled = Boolean(opts.disabled);
            // onClick is an Element property too, so a CONTAINER can carry a
            // handler -- the docs index rows are exactly box({ onClick: pick }).
            // The retained node mirrors Element.onClick (UiNode.applyPayload), but
            // nothing ever copied it onto the descriptor, so every container click
            // handler was null and the row was dead to the mouse.
            if (opts.onClick != null) n.onClick = (opts.onClick as Function);
        }

        public static function addChildren(n:Node, children:Array):void
        {
            if (children == null) return;
            var m:int = children.length;
            for (var i:int = 0; i < m; i++)
            {
                n.addChild(Node(children[i]));
            }
        }

        // "A single value or a list" -- NOT `Array(v)`.
        //
        // `Array(v)` is the Array CONSTRUCTOR called as a function, so it always
        // creates a new array: `Array([1,2])` is a 1-element array HOLDING [1,2]
        // (length 1, `Array(a) === a` is false, `Array(3).length` is 3). Measured on
        // adl 51.4.1 with our AOT agreeing on all 8 shapes -- probes/array-coerce/.
        // Using it as a coercion here is what produced
        // "#1034 cannot convert [object BoxNode] to asaot.ui.Node" from dialog()'s
        // footer: the cast was handed the OUTER array, which stringifies to its
        // single element's "[object BoxNode]".
        public static function list(v:*):Array
        {
            if (v == null) return null;
            if (v is Array) return v as Array;
            var one:Array = [v];
            return one;
        }
    }
}