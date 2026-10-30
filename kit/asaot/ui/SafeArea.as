// asaot.ui.SafeArea -- the `safeArea:` opt: which edges of a container want the
// platform's insets added to its padding (MOBILE.md E2, 6.4).
//
// ONE SPELLING, PARSED ONCE. The opt accepts `true` (all four edges), an edge name
// ("top"), or an array of them (["top", "bottom"]), and nothing else. It is parsed
// into a BITMASK on the retained node so a re-describe that keeps the same opt
// costs a comparison, and so the fold in UiNode can ask "does this side claim the
// inset" with one `&`.
//
// WHY A MASK AND NOT FOUR BOOLEANS: the three shapes above all collapse to the same
// question per edge, and a mask makes "unchanged" a single int compare -- which
// matters because this is read on every reconcile, once per node.
package asaot.ui
{
    public final class SafeArea
    {
        public static const TOP:int = 1;
        public static const RIGHT:int = 2;
        public static const BOTTOM:int = 4;
        public static const LEFT:int = 8;
        public static const NONE:int = 0;
        public static const ALL:int = 15;

        public function SafeArea() { }

        // A null/false opt means "none" (the default in MOBILE.md 6.4). Anything
        // else must NAME its edges: an unknown string is an AUTHOR error and throws,
        // because "safeArea: 'tpo'" quietly doing nothing is the same class of bug
        // as a style field with no consumer.
        public static function maskOf(v:*):int
        {
            if (v == null || v == false) return NONE;
            if (v == true) return ALL;
            if (v is Array)
            {
                var a:Array = v as Array;
                var m:int = NONE;
                for (var i:int = 0; i < a.length; i++) m = m | edgeOf(String(a[i]));
                return m;
            }
            if (v is String) return edgeOf(String(v));
            throw new Error("asaot.ui: `safeArea` must be true, an edge name, or an array of edge names (got "
                + v + ")");
        }

        private static function edgeOf(s:String):int
        {
            if (s == "top") return TOP;
            if (s == "right") return RIGHT;
            if (s == "bottom") return BOTTOM;
            if (s == "left") return LEFT;
            throw new Error('asaot.ui: unknown `safeArea` edge "' + s + '" (use top / right / bottom / left)');
        }
    }
}
