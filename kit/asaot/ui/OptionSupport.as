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
            // Right button / double click are Element properties too, so every
            // factory accepts them through this one place (a container is the
            // natural right-click target -- that is what a context menu is FOR).
            if (opts.onRightClick != null) n.onRightClick = (opts.onRightClick as Function);
            if (opts.onDoubleClick != null) n.onDoubleClick = (opts.onDoubleClick as Function);
            // The safe area opt is an Element property, so EVERY factory accepts it
            // (`safeArea: true` is most useful on the root container, but a bottom
            // bar that clears the home indicator is the same one line). Parsed into
            // a bitmask in UiNode.applyPayload, never here: a factory builds a
            // DESCRIPTION and must not read the environment.
            if (opts.safeArea != null) n.safeArea = opts.safeArea;
            // `tabIndex` only exists on Control. Anything else ignores it silently
            // today (a box is not a tab stop at all), which is why it is read here
            // rather than added to every factory signature.
            if (opts.tabIndex != null && (n is Control)) Control(n).tabIndex = int(Number(opts.tabIndex));
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

        // A click handler bound to ONE index, for a container that reports WHICH of
        // its cells was pressed (tabBar, and anything else built as a strip).
        //
        // It must be a FACTORY RETURNING A CLOSURE, not a closure written in the
        // caller's loop: AS3 hoists `var i` per function, not per iteration, so
        // every cell of a `for (var i ...)` loop would report the LAST index. The
        // parameter here is a fresh binding per call.
        public static function tapIndex(cb:Function, idx:int):Function
        {
            return function ():void { if (cb != null) cb(idx); };
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