// asaot.ui.kind.DrawerWidget -- the side-sheet shell for DrawerNode. All of the
// behaviour lives in PanelShellWidget; the drawer's edge anchoring is pure style
// (the factory patches a different layer), so there is nothing to do here but read
// the three fields.
package asaot.ui.kind
{
    import asaot.ui.DrawerNode;
    import asaot.ui.Node;

    public class DrawerWidget extends PanelShellWidget
    {
        override protected function openOf(desc:Node):Boolean
        {
            return DrawerNode(desc).open;
        }

        override protected function closeOnScrimOf(desc:Node):Boolean
        {
            return DrawerNode(desc).closeOnScrim;
        }

        override protected function onCloseOf(desc:Node):Function
        {
            return DrawerNode(desc).onClose;
        }
    }
}