// asaot.ui.Observable -- the minimal "I changed" source at the root of the data
// flow (design doc section 5.1).
//
// A small fixed array of listeners, called SYNCHRONOUSLY in registration order.
// Subscription is low-frequency (constructor / mount), so it never touches a hot
// path. `notify` does no drawing and no layout -- it only tells the scheduler.
package asaot.ui
{
    public class Observable
    {
        protected var listeners:Array;

        public function Observable():void
        {
            this.listeners = [];
        }

        public function subscribe(listener:Function):Subscription
        {
            var i:int = this.listeners.indexOf(listener);
            if (i < 0) this.listeners.push(listener);
            return new Subscription(this, listener);
        }

        public function unsubscribe(s:Subscription):void
        {
            if (s == null) return;
            var i:int = this.listeners.indexOf(s.listener);
            if (i >= 0) this.listeners.splice(i, 1);
        }

        public function notify(dirty:int):void
        {
            var n:int = this.listeners.length;
            for (var i:int = 0; i < n; i++)
            {
                var fn:Function = this.listeners[i];
                fn(dirty);
            }
        }
    }
}
