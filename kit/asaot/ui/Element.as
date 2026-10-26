// asaot.ui.Element -- a `Node` that carries accessibility metadata (design doc
// section 4.2/4.3). The metadata is only a SHAPE for now: we store role/name/value
// on the retained node so a future flash.accessibility / U6 pass can materialise
// a real tree. The doc's rule is that a control must SET its role and name; the
// reconciler asserts that rather than silently accepting a nameless control.
package asaot.ui
{
    public class Element extends Node
    {
        public var role:String;
        public var ariaName:String;
        public var ariaValue:*;
        // The design doc's `visible:` opt (section 8) -- an element that is not
        // drawn but still OCCUPIES its laid-out space. That is CSS
        // `visibility:hidden`, not `display:none`, and it maps straight onto the
        // backing object's `visible` flag.
        public var visible:Boolean;
        // DISABLED (design doc section 8). An element that cannot be interacted
        // with, INHERITED BY ITS SUBTREE: a disabled card disables every control
        // inside it. `UiNode.inert()` walks the retained parent chain, which is why
        // this is one boolean per element rather than a flag copied down.
        // Rendering: the backing's alpha is scaled by PaintKit.DISABLED_ALPHA and
        // the hover/press modulation is dropped -- one place, every kind.
        public var disabled:Boolean;
        // CLICKABLE, WHATEVER THE KIND. A `box` was the one element that could not
        // be clicked, so `box({ onClick: pick })` -- which every factory accepts
        // through OptionSupport.applyOpts -- was silently dead: the handler was
        // stored on the description and nothing ever copied it to the retained
        // node. The docs app's index rows are exactly that shape (a full-width
        // row with left-aligned text, which no repainting control provides).
        // This is Flash's own model: every display object is a hit region, and a
        // click BUBBLES, so a control nested in a clickable container reaches
        // both handlers (an author who needs one of them to stop can call
        // stopPropagation in their handler).
        public var onClick:Function;
        // RIGHT BUTTON (2026-10-27). The runtime has dispatched `rightMouseDown`
        // since the native ContextMenu landed (emit.ts:26457) and a kit control
        // could not hear it: every mouse listener in this library was one of six
        // left/over/wheel types. The coordinates ARE the argument pair -- a
        // right-click exists to say "open something HERE", and a handler without
        // the point would have to guess it from the pointer.
        //
        // AVM2 arity: called as onRightClick(x, y), so a zero-argument closure is
        // still valid (extra arguments are ignored; MISSING ones are #1063).
        public var onRightClick:Function;   // Function(stageX:Number, stageY:Number)
        // DOUBLE CLICK. Gated by the runtime on the HIT TARGET's own
        // `doubleClickEnabled` (emit.ts:26439-26443, measured on adl 51.4.1), which
        // defaults to false -- so this flag is switched on by UiNode only when a
        // handler exists. Enabling it globally would change what a fast second
        // click means for every existing control.
        public var onDoubleClick:Function;  // Function()

        public function Element(kind:String):void
        {
            super(kind);
            this.role = null;
            this.ariaName = null;
            this.ariaValue = null;
            this.visible = true;
            this.disabled = false;
            this.onClick = null;
            this.onRightClick = null;
            this.onDoubleClick = null;
        }
    }
}