// asaot.ui.EnvBase -- the writable end of `Env`: a plain record of the platform
// facts plus the notification channel, so an implementation only has to write
// VALUES.
//
// WHY A BASE CLASS AND NOT "implement Env by hand each time": every implementation
// would otherwise repeat nine fields, nine getters, nine compare-before-notify
// paths and the Observable wiring -- and the two that must not drift are the
// compare and the notify. A desktop build and a simulated phone in a probe differ
// in what they SET, not in how a change is announced.
//
// SUBSCRIBER SAFETY: `notify` is synchronous and iterates a snapshot COUNT, so a
// listener that subscribes or cancels during the callback cannot make this loop
// skip or revisit an entry (same contract as Observable's own notify). A listener
// that writes the Env from inside a callback re-enters notify; that is the caller's
// own recursion, exactly like a model listener writing its model.
package asaot.ui
{
    import asaot.ui.style.Edges;

    import flash.geom.Rectangle;

    public class EnvBase extends Observable implements Env
    {
        protected var _safeArea:Edges;
        protected var _keyboardRect:Rectangle;
        protected var _pixelRatio:Number;
        protected var _hasTouch:Boolean;
        protected var _hasHover:Boolean;
        protected var _reduceMotion:Boolean;
        protected var _appState:String;
        protected var _isDark:Boolean;
        protected var _locale:String;

        public function EnvBase():void
        {
            super();
            // The neutral answer: a plain desktop window with a mouse. Every
            // non-neutral fact is something a platform shell must SAY.
            this._safeArea = Edges.of(0, 0, 0, 0);
            this._keyboardRect = new Rectangle(0, 0, 0, 0);
            this._pixelRatio = 1;
            this._hasTouch = false;
            this._hasHover = true;
            this._reduceMotion = false;
            this._appState = "active";
            this._isDark = false;
            this._locale = "";
        }

        public function get safeArea():Edges { return this._safeArea; }
        public function get keyboardRect():Rectangle { return this._keyboardRect; }
        public function get pixelRatio():Number { return this._pixelRatio; }
        public function get hasTouch():Boolean { return this._hasTouch; }
        public function get hasHover():Boolean { return this._hasHover; }
        public function get reduceMotion():Boolean { return this._reduceMotion; }
        public function get appState():String { return this._appState; }
        public function get isDark():Boolean { return this._isDark; }
        public function get locale():String { return this._locale; }

        // ---- the platform-facing writers ---------------------------------
        //
        // Every one of them is COMPARE-BEFORE-NOTIFY: a platform that re-reports
        // the same insets on every rotation tick must not turn into a reflow per
        // tick. They MUTATE the held object instead of allocating a new one, because
        // these run on platform callbacks and the kit's rule is that a hot path
        // allocates nothing -- so a consumer must read the values, never hold the
        // object across a change. (`UiApp` reads and folds them in the same frame;
        // that is the only consumer today.)
        public function setSafeArea(t:Number, r:Number, b:Number, l:Number):void
        {
            if (this._safeArea.top == t && this._safeArea.right == r
                && this._safeArea.bottom == b && this._safeArea.left == l) return;
            this._safeArea.top = t; this._safeArea.right = r;
            this._safeArea.bottom = b; this._safeArea.left = l;
            this.notify(Dirty.VALUE);
        }

        public function setKeyboardRect(x:Number, y:Number, w:Number, h:Number):void
        {
            var k:Rectangle = this._keyboardRect;
            if (k.x == x && k.y == y && k.width == w && k.height == h) return;
            k.x = x; k.y = y; k.width = w; k.height = h;
            this.notify(Dirty.VALUE);
        }

        public function setPixelRatio(v:Number):void
        {
            if (this._pixelRatio == v) return;
            this._pixelRatio = v;
            this.notify(Dirty.VALUE);
        }

        public function setHasTouch(v:Boolean):void
        {
            if (this._hasTouch == v) return;
            this._hasTouch = v;
            this.notify(Dirty.VALUE);
        }

        // The one that reaches 103 branches: see UiApp.setHasHover.
        public function setHasHover(v:Boolean):void
        {
            if (this._hasHover == v) return;
            this._hasHover = v;
            this.notify(Dirty.VALUE);
        }

        public function setReduceMotion(v:Boolean):void
        {
            if (this._reduceMotion == v) return;
            this._reduceMotion = v;
            this.notify(Dirty.VALUE);
        }

        public function setAppState(v:String):void
        {
            if (v != "active" && v != "inactive" && v != "background")
            {
                throw new Error('asaot.ui: Env.appState must be "active", "inactive" or "background" (got "'
                    + v + '")');
            }
            if (this._appState == v) return;
            this._appState = v;
            this.notify(Dirty.VALUE);
        }

        public function setDark(v:Boolean):void
        {
            if (this._isDark == v) return;
            this._isDark = v;
            this.notify(Dirty.VALUE);
        }

        public function setLocale(v:String):void
        {
            if (this._locale == v) return;
            this._locale = v;
            this.notify(Dirty.VALUE);
        }
    }
}
