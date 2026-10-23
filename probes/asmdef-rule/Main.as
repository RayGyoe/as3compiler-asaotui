// probes/asmdef-rule/Main.as -- drives the illegal shape in p/Lib.as.
//
// Our AOT accepts a top-level script here (AIR does not), so this file is written
// in the form BOTH compilers can consume: an explicit main entry that touches the
// illegal file. For mxmlc the same shape is driven by UseLib.as (a class).
import p.Lib;

var l:Lib = new Lib();
trace("asmdef-rule: p.Lib constructed");
