// control: a public PACKAGE-LEVEL FUNCTION only, in the file named after it.
//
// This is the shape mxmlc accepts. The rejected shape is the same function living
// in a differently-named file (see ../UsePkgFnViaClass.as) -- AIR then reports
// "unexpectedly found an externally visible definition with the name p.hello".
package p
{
    public function hello():String
    {
        return "hello-from-package-scope";
    }
}
