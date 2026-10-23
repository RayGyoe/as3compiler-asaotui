// asaot.ui.Binding -- a one-way binding to a field of an `Observable` owner.
//
// `get()` reads the field, `set(v)` writes it AND notifies the owner with
// Dirty.VALUE, which is what makes "write through the binding" reach the same
// single invalidate entry point as an explicit `notify` (design doc section
// 5.1). Field access goes through the owner as an `Object` so a binding is
// declarative (`bindTo(form, "account")`) rather than requiring an accessor pair
// on every model -- the same tradeoff the design doc chose.
//
// The `bindTo` factory lives in its own file `bindTo.as`: mxmlc resolves a
// package-level function only from a file named after it.
package asaot.ui
{
    public class Binding
    {
        public var owner:Observable;
        public var field:String;

        public function Binding(owner:Observable, field:String):void
        {
            this.owner = owner;
            this.field = field;
        }

        public static function of(owner:Observable, field:String):Binding
        {
            return new Binding(owner, field);
        }

        public function get():*
        {
            var o:Object = this.owner;
            return o[this.field];
        }

        public function set(v:*):void
        {
            var o:Object = this.owner;
            o[this.field] = v;
            if (this.owner != null) this.owner.notify(Dirty.VALUE);
        }
    }
}