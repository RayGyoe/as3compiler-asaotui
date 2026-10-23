// asaot.ui.Subscription -- the handle `Observable.subscribe` returns, so the
// owner can be unsubscribed without keeping the listener function around.
package asaot.ui
{
    public class Subscription
    {
        public var owner:Observable;
        public var listener:Function;

        public function Subscription(owner:Observable, listener:Function):void
        {
            this.owner = owner;
            this.listener = listener;
        }

        public function cancel():void
        {
            if (this.owner != null) this.owner.unsubscribe(this);
        }
    }
}
