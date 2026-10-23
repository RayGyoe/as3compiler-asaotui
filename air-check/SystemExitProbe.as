// air-check/SystemExitProbe.as -- the probe that PINNED the System.exit finding.
//
// WHY THIS EXISTS: while building the AIR arm we hit `System.exit(0)` failing on
// OUR compiler with the misleading message "undefined variable 'System' at top
// level" (System is a hand-written pseudo-class in src/emit.ts that handles gc /
// output / setClipboard / disposeXML / useCodePage, but NOT exit). Per AGENTS.md
// section 1.5 the question "is this a legacy gap (AIR has it, we lack it) or a
// non-issue (AIR lacks it too)?" may NOT be answered by intuition -- it needs a
// real AIR reference. mxmlc IS that reference. Measured with AIR 51.4.1:
//
//   System.exit()          -> ERROR "incorrect number of arguments. 1 required"
//   System.exit(0)         -> compiles
//   System.exit(3)         -> compiles
//   System.exit(true)      -> ERROR "Boolean cannot be implicitly coerced to uint"
//   var f:Function = System.exit;  -> compiles (so the member really exists)
//   System.definitelyNotAMemberXYZ() -> ERROR "method ... is not defined"
//                                       (negative control: proves a compile
//                                        failure does distinguish "exists" from
//                                        "does not exist")
//
// CONCLUSION: AIR declares `flash.system.System.exit(code:uint):void` -- one
// REQUIRED uint, no default, and NOT a Boolean (unlike NativeProcess.exit(force:Boolean)).
// Our compiler has no such member => LEGACY GAP, not "AIR has it neither".
//
// THIS FILE IS DELIBERATELY THE ZERO-ARGUMENT FORM (see the header's line 1 of
// the table): it must keep FAILING on mxmlc so the "1 required" evidence stays in
// the repo. Run:  mxmlc -output=sysprobe.swf SystemExitProbe.as   (expected: exit 2)
package
{
    import flash.display.Sprite;
    import flash.system.System;

    public class SystemExitProbe extends Sprite
    {
        public function SystemExitProbe()
        {
            System.exit();
        }
    }
}
