// asaot.ui.CardNode -- a titled CONTAINER (a surface that holds other widgets).
//
// It is an Element (role "group"), like BoxNode: a card is a layout container,
// not a focusable control. Its `title` is drawn as an internal TextField (see
// CardWidget); the CHILDREN are ordinary UiNodes, so the layout engine positions
// them inside the card exactly as it would inside a `box`.
package asaot.ui
{
    import asaot.ui.kind.CardWidget;

    public class CardNode extends Element
    {
        public var title:String;

        private static var registered:Boolean = false;

        public function CardNode():void
        {
            super("card");
            if (!registered) { registered = true; Widgets.register("card", new CardWidget()); }
            this.role = "group";
            this.title = null;
        }
    }
}