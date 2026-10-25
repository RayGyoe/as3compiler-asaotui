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
// The widget decides which keys mean anything to it. The keys that exist today --
// kept HERE, in one place, because "which control answers to which arrow" is the
// one part of this contract a reader cannot guess from the interface:
//   menu        -- Up/Down move the active row (wrap), Enter/Space activate it,
//                  Escape closes the menu
//   select      -- Up/Down move the active row (wrap), Enter/Space activate it,
//                  Escape closes the dropdown, Down/Enter opens it when shut
//   combobox    -- as select, plus typing (the field owns the text)
//   datePicker  -- Left/Right walk days (wrap), Up/Down a week, Enter/Space pick,
//                  Escape closes; when shut, Enter/Space/Down open it
//   dialog / drawer / popover / toastHost (PanelShell)
//               -- Escape calls onClose
//   input       -- Enter commits, Escape reverts to the last committed value
//                  (Space and the arrows belong to the field)
//   textArea    -- Escape reverts; Enter is NOT consumed (it inserts a newline)
//   tree        -- Up/Down walk the flat row list (wrap), Left/Right collapse/expand,
//                  Home/End, Enter/Space select
//   virtualList -- Up/Down one row, PageUp/PageDown one window, Home/End
//   list        -- Up/Down one row (CLAMPED at the ends), Home/End
//   table       -- Up/Down one body row (clamped), PageUp/PageDown one window,
//                  Home/End; under `virtual` a move also scrolls the window
//   tabs        -- Left/Right one segment (WRAP: a strip is a ring), Home/End
//
// WRAP vs CLAMP is not taste: a tree/tab strip/menu is a RING or a spatial structure,
// so leaving one end enters the other; a list/grid is a SEQUENCE, and its ends are
// walls (the ARIA listbox/grid model). Each widget's onKey says which and why.
package asaot.ui
{
    public interface WidgetKeys
    {
        function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean;
    }
}