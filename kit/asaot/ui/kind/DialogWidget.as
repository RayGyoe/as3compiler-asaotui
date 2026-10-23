// asaot.ui.kind.DialogWidget -- the modal shell for DialogNode. All of the
// behaviour lives in PanelShellWidget (see its header); this class only says where
// the three fields come from.
package asaot.ui.kind
{
    import asaot.ui.DialogNode;
    import asaot.ui.Node;

    public class DialogWidget extends PanelShellWidget
    {
        override protected function openOf(desc:Node):Boolean
        {
            return DialogNode(desc).open;
        }

        override protected function closeOnScrimOf(desc:Node):Boolean
        {
            return DialogNode(desc).closeOnScrim;
        }

        override protected function onCloseOf(desc:Node):Function
        {
            return DialogNode(desc).onClose;
        }
    }
}