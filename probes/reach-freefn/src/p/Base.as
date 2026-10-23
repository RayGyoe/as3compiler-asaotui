// p.Base -- Leaf's superclass. Nothing but Leaf names it, and Leaf is reached
// only from the forced file, so this class is the first casualty of G13.
package p
{
    public class Base
    {
        public var kind:String;

        public function Base(k:String):void
        {
            this.kind = k;
        }
    }
}