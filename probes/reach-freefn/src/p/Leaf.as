// p.Leaf -- reached ONLY from the forced file p/Fac.as (never from Main). Two
// distinct references hang off it, so the defect shows up twice and in two
// different shapes:
//   * `extends Base`  -> "unknown superclass 'Base' of 'p_Leaf'"
//   * `new Helper()`  -> "unknown type 'Helper'" / "unknown class Helper"
package p
{
    public class Leaf extends Base
    {
        public var tag:String;

        public function Leaf():void
        {
            super("leaf");
            this.tag = "leaf";
            var h:Helper = new Helper();
            this.tag = this.tag + h.suffix;
        }
    }
}