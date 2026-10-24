// asaot.ui.WidgetKeys -- the OPTIONAL keyboard hook of a widget (see
// WidgetTeardown for the same pattern and the same reason).
//
// WHY A SECOND INTERFACE AND NOT A SIXTH `Widget` METHOD: `Widget` is the
// published seam every kind implements and third parties copy (CONTRIBUTING-widget
// section 4). Adding a method to it would force every existing kind -- and every
// third-party kind -- to grow a stub that returns false. An optional interface is
// one `is` test at the one call site (UiApp.onKeyDown) and costs the other 30
// kinds nothing.
//
// CONTRACT: called for the FOCUSED node's widget on every KEY_DOWN that UiApp did
// not already consume (Tab). Return true when this kind consumed the key -- the
// caller then calls preventDefault(), which is what stops the runtime's own
// default action for that key.
//
// The widget decides which keys mean anything to it. The keys that exist:
//   menu   -- Up/Down move the active row, Enter activates it, Right opens a
//             submenu, Left closes it, Escape closes the menu
//   select -- Up/Down move the active row, Enter/Space activates the trigger,
//             Escape closes the dropdown
//   dialog -- Escape calls onClose
//   drawer -- Escape calls onClose
//   input  -- Enter commits, Escape reverts to the last committed value
package asaot.ui
{
    public interface WidgetKeys
    {
        function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean;
    }
}