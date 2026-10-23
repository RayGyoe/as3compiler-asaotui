// air-check/pkgfn-probe/UsePkgFn.as -- probe A: import the package-level function
// DIRECTLY, with no other reason for Lib.as to be compiled.
//
// Expected if AIR maps `import p.hello` to the file p/hello.as: a warning
// "找不到定义 p.hello" plus "所调用的方法 hello 可能未定义".
package
{
    import p.hello;

    public class UsePkgFn
    {
        public function UsePkgFn():void
        {
            var s:String = hello();
        }
    }
}