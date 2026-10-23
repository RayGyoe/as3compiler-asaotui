// p.Helper -- named only from Leaf's constructor. Second casualty of G13: not a
// superclass, just a referenced class, to show the defect is not specific to
// inheritance.
package p
{
    public class Helper
    {
        public var suffix:String;

        public function Helper():void
        {
            this.suffix = "!";
        }
    }
}