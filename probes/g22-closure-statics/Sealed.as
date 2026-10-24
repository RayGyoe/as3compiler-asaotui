// Sealed.as -- a class whose static is seeded by a runtime call, not a literal.
//
// AS3 has no `static {}` block (mxmlc rejects it), so the "the initializer needs
// main()-time evaluation" case is a static var whose initializer calls a function.
// `VALUE` therefore joins the `_cinit` set through the field-initializer path, and
// nothing but closures reads it.
package {
    public class Sealed {
        public static var VALUE:String = seed();

        private static function seed():String {
            return "block-set";
        }
    }
}