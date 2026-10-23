// G9Cases.as -- the truthiness matrix for G9, written ONCE and driven by two
// hosts: G9Air.as (mxmlc -> adl, real AIR runtime) and G9Aot.as (our AOT ->
// native). Only the output channel differs, never the cases -- otherwise the
// A/B would be comparing two different questions.
//
// The question G9 asks: when a value is stored into a slot STATICALLY declared
// `Object`, does `Boolean(...)` still see the primitive (AS3 semantics) or does
// it degrade to a pointer test? AIR's answer is the reference.
package
{
    public class G9Cases
    {
        private static var lines:Array = [];
        private static var fails:int = 0;

        private static function say(s:String):void
        {
            lines.push(s);
        }

        // Helper that returns `false` through a `*` return type, so the value
        // reaching the Object slot is "dynamic" at the call site -- the exact
        // shape the UI kit's `Binding.get():*` has.
        private static function getFalse():* { return false; }

        public static function run():String
        {
            lines = [];
            fails = 0;

            // ---- A) the G9 shape: static Object slot holding a primitive ----
            var o:Object = getFalse();
            tag('A1.obj.false(Boolean)', Boolean(o), false);
            tag('A1.obj.false(typeof)', typeof(o), 'boolean');
            tag('A1.obj.false(String)', String(o), 'false');
            tag('A1.obj.false(isBoolean)', (o is Boolean), true);
            tag('A1.obj.false(==false)', (o == false), true);
            tag('A1.obj.false(===false)', (o === false), true);
            tag('A1.obj.false(Number)', Number(o), 0);
            tag('A1.obj.false(==null)', (o == null), false);
            if (o) { say('A1.obj.false(if) = TAKEN'); fails++; }
            else { say('A1.obj.false(if) = skipped'); }

            // ---- B) other primitives through the same Object slot ----
            var z:Object = 0;
            tag('B1.obj.zero(Boolean)', Boolean(z), false);
            tag('B1.obj.zero(typeof)', typeof(z), 'number');

            var s:Object = '';
            tag('B2.obj.emptyStr(Boolean)', Boolean(s), false);
            tag('B2.obj.emptyStr(typeof)', typeof(s), 'string');

            var n:Object = Math.sqrt(-1);           // NaN
            tag('B3.obj.NaN(Boolean)', Boolean(n), false);

            var t:Object = 'x';
            tag('B4.obj.str(Boolean)', Boolean(t), true);

            var k:Object = 5;
            tag('B5.obj.five(Boolean)', Boolean(k), true);
            tag('B5.obj.five(typeof)', typeof(k), 'number');

            var nu:Object = null;
            tag('B6.obj.null(Boolean)', Boolean(nu), false);

            // ---- C) control arms that already behave correctly in our AOT ----
            var a:* = getFalse();
            tag('C1.star.false(Boolean)', Boolean(a), false);

            var bb:Boolean = false;
            var ob:Object = bb;
            tag('C2.boolThenObj(Boolean)', Boolean(ob), false);

            // ---- D) : NOT the ES3 rule. Measured on AIR 51.4.1:
            // typeof is "boolean" and Boolean(wrapper) is false -- AVM2 keeps Boolean
            // wrappers transparent to both types of test. (ES3 would say object/true.)
            var w:Object = new Boolean(false);
            tag('D1.newBoolean(false).typeof', typeof(w), 'boolean');
            tag('D1.newBoolean(false).isBoolean', (w is Boolean), true);
            tag('D1.newBoolean(false).Boolean', Boolean(w), false);
            tag('D1.newBoolean(false).String', String(w), 'false');

            // ---- E) dynamic property read into an Object slot ----
            var holder:Object = {};
            holder.flag = false;
            var p:Object = holder.flag;
            tag('E1.prop.false(Boolean)', Boolean(p), false);
            tag('E1.prop.false(typeof)', typeof(p), 'boolean');

            say('---- ' + lines.length + ' checks, ' + fails + ' failures ----');
            return lines.join('\n');
        }

        private static function tag(name:String, got:*, want:*):void
        {
            var ok:Boolean = (String(got) == String(want));
            if (!ok) fails++;
            say('GOT ' + name + ' = ' + String(got) + (ok ? '' : '   <<< WANT ' + String(want)));
        }
    }
}