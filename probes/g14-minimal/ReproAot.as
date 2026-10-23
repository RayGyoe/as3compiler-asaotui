// probes/g14-minimal/ReproAot.as -- the SMALLEST program that reproduces G14 on our
// AOT. Top-level script, one process, three lines of evidence.
//
//   line 1  `is Array`  -> expected true,  we answer false   (silently wrong)
//   line 2  `is Marker` -> expected false, we CRASH with 0xC0000005
//
// Both lines come from ONE root cause: an Array stored in an `Object`-typed slot is
// NOT boxed, so our `Object*` is really a bare `as_array*` pointer. `is Array` is
// therefore folded to a literal `false` at compile time (src/emit.ts:32576) and
// `is Marker` compiles to `as_is(o, &Marker_vt)`, which reads the array header's
// first word as a vtable pointer (src/runtime.ts:1178).
//
// EVIDENCE IS APPENDED TO A FILE, ONE LINE PER STEP, on purpose: the process is
// about to die with an access violation, and a buffered stdout would lose the very
// line that proves how far it got.
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

function emit(line:String):void
{
    var f:File = new File("g14-aot.txt");
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.APPEND);
    fs.writeUTFBytes(line + "\n");
    fs.close();
}

var o:Object = [1, 2, 3];

emit("is Array  = " + (o is Array) + "     (AIR: true)");
emit("is Marker = " + (o is Marker) + "     (AIR: false)");
emit("REACHED THE END (no crash)");
