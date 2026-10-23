// probes/name-collision/p/Names.as -- is the  collision a NAME or a CLASS?
//
// Our AOT emits a user function into C under its own name, unmangled, at file
// scope. So any AS3 function named after a libc/POSIX/Windows symbol should break
// the C build. Testing several names at once separates "bind is unlucky" from
// "any collision breaks", which is the difference between a footnote and a rule.
//
// (All of these sit in ONE file on purpose -- the AIR rule probes/asmdef-rule
// covers is a SEPARATE question; this probe is only about our own codegen.)
package p
{
    public function div(a:int, b:int):int { return a / b; }
    public function free(a:int):int { return a; }
    public function stat(a:int):int { return a; }
    public function time(a:int):int { return a; }
    public function open(a:int, b:int):int { return a + b; }
    public function close(a:int):int { return a; }
    public function read(a:int):int { return a; }
    public function exit(a:int):int { return a; }
}
