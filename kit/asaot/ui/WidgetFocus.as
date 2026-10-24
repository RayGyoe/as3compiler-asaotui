// asaot.ui.WidgetFocus -- the OPTIONAL "which display object takes the keyboard"
// hook of a widget (same optional-interface pattern as WidgetTeardown / WidgetKeys).
//
// The default focus target of a node is its own `backing` Sprite: the library
// moves a ring between nodes and nothing else. An EDITABLE kind is different --
// typing has to reach a real `flash.text.TextField`, because the runtime routes
// SDL text into `stage.focus` and we deliberately do not write a second text
// pipeline (design doc 4.4). So an input kind returns its field here and UiApp
// assigns `stage.focus` to it; every other kind returns null and UiApp clears the
// stage focus instead.
package asaot.ui
{
    import flash.display.DisplayObject;

    public interface WidgetFocus
    {
        // Return the object that should receive `stage.focus`, or null when this
        // kind wants no runtime focus at all (the common case).
        function focusTarget(n:UiNode):DisplayObject;
    }
}