// probes/bind-truthy/BindProbe.as -- measure what `Binding.get()` actually
// returns at the type level, instead of guessing.
//
// WHY THIS EXISTS: probes/widgets/form/Main.as reports that a radio bound with
// `selected: bindTo(model, "radioSel")` (model value FALSE) is painted SELECTED,
// and that the bound switch paints an empty track. Both are consistent with one
// hypothesis: the bound value arrives as something TRUTHY even when the model
// says false. Two candidate mechanisms:
//   (a) the KIT is wrong -- e.g. `Boolean(opts.selected)` slugging a Binding
//       object that was not recognised by `is Binding`;
//   (b) the COMPILER is wrong -- `Binding.get():*` goes through a dynamic field
//       read (`as_dyn_get`), and the boxed `*` value loses its tag on the way
//       into an `Object`-typed local, so `Boolean(o)` becomes "pointer != NULL".
// These have very different consequences (fix the kit vs register a gap), so
// this probe separates them by printing the exact runtime answers.
//
// This one is a CONSOLE probe: it never opens a window, so it cannot block, and
// every answer is printed on stdout as it is computed. It also writes the same
// text to bind-truthy.txt, because a crash discards stdout.
//
// Expectations below are HAND-DERIVED from the AS3 spec, not from a run:
//   * `Binding.get()` returns `*` -- a tagged value. For a Boolean field, the
//     spec says the value IS the Boolean false, so:
//         Boolean(get())  === false
//         get() is Boolean === true     (the runtime tag is BOOLEAN)
//         String(get())    === "false"
//         get() == null    === false    (false is not null!)
//   * an `is` test against a class must be TRUE for an instance of that class,
//     whether reached through a local, a `*`, or an object-literal field.
// Any line that disagrees with the above is a BUG, and which line fails tells us
// whether it is the kit or the compiler.
import asaot.ui.*;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

class BindModel extends Observable
{
    public var flagFalse:Boolean = false;
    public var flagTrue:Boolean = true;
    public var num:Number = 0;
    public var txt:String = "";
}

var buf:String = "";
function say(k:String, v:*):void
{
    var line:String = k + " = " + v;
    buf = buf + line + "\n";
    trace(line);
}

var m:BindModel = new BindModel();
var b:Binding = bindTo(m, "flagFalse");

say("--- the binding object itself ---", "");
say("bindTo(...) is Binding", (b is Binding));
say("Binding.of(...) is Binding", (Binding.of(m, "flagTrue") is Binding));

say("--- a FALSE field: what does get() hand back? ---", "");
var sS:Object = b.get();                    // * -> Object
var sB:Boolean = b.get();                   // * -> Boolean
var sA:* = b.get();                         // * kept dynamic
say("Object-typed: is Boolean", (sS is Boolean));
say("Object-typed: == null", (sS == null));
say("Object-typed: Boolean(v)", Boolean(sS));
say("Object-typed: String(v)", String(sS));
say("Boolean-typed (coerced)", sB);
say("Any-typed: is Boolean", (sA is Boolean));
say("Any-typed: Boolean(v)", Boolean(sA));
say("Any-typed: String(v)", String(sA));

say("--- the same, for a TRUE field ---", "");
var tb:Binding = bindTo(m, "flagTrue");
say("Boolean(tb.get())", Boolean(tb.get()));
say("String(tb.get())", String(tb.get()));

say("--- a Binding inside an object literal (the opts path) ---", "");
var opts:Object = { selected: b, another: tb };
say("opts.selected is Binding", (opts.selected is Binding));
say("opts.selected == null", (opts.selected == null));
say("Boolean(opts.selected)", Boolean(opts.selected));
say("opts.another is Binding", (opts.another is Binding));

say("--- which branch would radio.as take? ---", "");
var branch:String = "NEITHER";
if (opts.selected is Binding) branch = "is-Binding branch (correct)";
else if (opts.selected != null) branch = "else branch -> Boolean(object) = TRUE (BUG)";
say("radio.as branch", branch);
say("=> n.selected would become", (opts.selected is Binding) ? "the field value" : Boolean(opts.selected));

say("--- write-back: does set() reach the owner? ---", "");
b.set(true);
say("after b.set(true), model.flagFalse", m.flagFalse);
b.set(false);
say("after b.set(false), model.flagFalse", m.flagFalse);

// ============================================================================
// BLAST RADIUS. The line above shows `Boolean(x)` is wrong when x is an
// Object-typed slot holding a boxed scalar. That is only a curiosity until we
// know which AUTHOR-FACING spellings reach such a slot. Every case below holds
// the value FALSE, so the CORRECT answer is `false` on every single line.
// ============================================================================
say("--- blast radius: which spellings hit a boxed Object slot? ---", "");
say("1 typed field        m.flagFalse", Boolean(m.flagFalse));
say("2 typed dyn index    m[\"flagFalse\"]", Boolean(m["flagFalse"]));
var dyn:Object = m;
say("3 Object-typed recv  dyn.flagFalse", Boolean(dyn.flagFalse));
var dynStar:* = m;
say("4 *-typed recv       dynStar.flagFalse", Boolean(dynStar.flagFalse));
var lit:Object = { flag: false };
say("5 object literal     lit.flag", Boolean(lit.flag));
say("6 literal dyn index  lit[\"flag\"]", Boolean(lit["flag"]));
var litStar:* = { flag: false };
say("7 literal via *      litStar.flag", Boolean(litStar.flag));
var arr:Array = [false];
say("8 array element      arr[0]", Boolean(arr[0]));
var vt:* = arr[0];
say("9 array elem via *   (as *)", Boolean(vt));
var num:Number = 0;
say("10 Number 0          num", Boolean(num));
var str:String = "";
say("11 empty String      str", Boolean(str));

// The same question asked the way a KIT does it: an option bag is Object-typed,
// so `opts.visible` is a dynamic read of a boxed Boolean.
var opts2:Object = { visible: false, password: false, tabEnabled: false };
say("12 option bag        opts2.visible", Boolean(opts2.visible));
say("13 option bag        opts2[\"password\"]", Boolean(opts2["password"]));

// And the `if` STATEMENT form, which is what OptionSupport actually writes.
var tookIf:String = "no";
if (opts2.tabEnabled) tookIf = "YES (wrong)";
say("14 if(opts2.tabEnabled), value false ->", tookIf);
var tookIf2:String = "no";
var tf:* = opts2.tabEnabled;
if (tf) tookIf2 = "YES (wrong)";
say("15 if(*-typed copy), value false ->", tookIf2);

// The exact analogue of Boolean(sS): an Object-DECLARED local fed a boxed value.
var q:Object = b.get();
var tookIf3:String = "no";
if (q) tookIf3 = "YES (wrong)";
say("16 if(Object-declared local from *), value false ->", tookIf3);
var qb:Boolean = b.get();
var tookIf4:String = "no";
if (qb) tookIf4 = "YES (wrong)";
say("17 if(Boolean-declared local), value false ->", tookIf4);

var f:File = new File("bind-truthy.txt");
var fs:FileStream = new FileStream();
fs.open(f, FileMode.WRITE);
fs.writeUTFBytes(buf);
fs.close();
trace("WROTE bind-truthy.txt");