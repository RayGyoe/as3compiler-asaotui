// probes/asmdef-rule/Lib.as -- THE COMPILER-DIFFERENCE PROBE.
//
// AS3 has a rule that a source file may contain at most ONE externally visible
// ("public") top-level definition, and that definition must be named after the
// file. AIR enforces it: putting a public package-level function in a file that is
// not named after it is a HARD ERROR --
//
//   错误: 意外发现一个具有名称"p.hello"的外部可见定义。
//
// (and the class the file *should* have provided then reports as unresolved).
//
// This file is that illegal shape on purpose. Compile it with both toolchains and
// compare: if our AOT accepts it, then code written under our compiler can fail to
// compile under AIR with no warning from us -- a silent portability trap. That is
// worth registering as a compiler gap rather than discovering later.
//
// The legal twin is p/hello.as + p/Lib.as (one definition per file, file named
// after the definition) -- see that pair for the shape mxmlc does accept.
package p
{
    public function hello():String
    {
        return "hello-from-package-scope";
    }

    public class Lib
    {
        public function Lib():void { }
    }
}