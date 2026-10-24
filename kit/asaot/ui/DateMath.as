// asaot.ui.DateMath -- the calendar arithmetic of `datePicker`, without `Date`.
//
// WHY NOT `flash.utils`/`Date`: a Date carries a timezone and a clock, and a calendar
// grid must not depend on either. These are pure integer functions of (year, month,
// day), so the same grid comes out anywhere -- and a probe can pin the numbers by hand
// (2026-10-01 is a THURSDAY, index 4 below; verified independently against
// Date.UTC(2026,9,1).getUTCDay()).
//
// Statics on a class, not package functions: mxmlc resolves a package-level function
// only from a file named after it (compiler-gaps G7), and the factory needs four of
// them.
//
// WEEKDAYS ARE 0..6 = SUNDAY..SATURDAY, the same convention as Date.getDay().
package asaot.ui
{
    public final class DateMath
    {
        // Sakamoto's method. `t` is the month offset table (January-first).
        public static function weekday(y:int, m:int, d:int):int
        {
            var t:Array = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
            var yy:int = m < 3 ? y - 1 : y;
            var v:int = yy + int(yy / 4) - int(yy / 100) + int(yy / 400)
                + int(t[m - 1]) + d;
            return int(v % 7);
        }

        public static function daysInMonth(y:int, m:int):int
        {
            if (m == 2)
            {
                var leap:Boolean = (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
                return leap ? 29 : 28;
            }
            if (m == 4 || m == 6 || m == 9 || m == 11) return 30;
            return 31;
        }

        // "2026-10-05": a date is an ISO string everywhere in this kit, so a value
        // compares and sorts as text and needs no parse to be stored.
        public static function iso(y:int, m:int, d:int):String
        {
            return String(y) + "-" + pad2(m) + "-" + pad2(d);
        }

        public static function pad2(v:int):String
        {
            return v < 10 ? "0" + v : String(v);
        }

        // Month arithmetic that stays inside 1..12 (delta may be negative).
        public static function addMonths(y:int, m:int, delta:int):Object
        {
            var idx:int = (y * 12) + (m - 1) + delta;
            var ny:int = int(Math.floor(idx / 12));
            var nm:int = idx - ny * 12 + 1;
            return { year: ny, month: nm };
        }

        public function DateMath() { }
    }
}