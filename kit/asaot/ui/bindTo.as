// asaot.ui.bindTo -- declarative one-way binding factory.
//
// NAME NOTE: the design doc spells this `bind(owner, field)`, and the shipped name is
// `bindTo`. That rename was FORCED once -- our AOT emits a package-level function's
// name VERBATIM into C, and `bind` collided with the POSIX socket `bind(2)`
// ("conflicting types for 'bind'") -- but the compiler has since fixed it
// (阶段二四七: machine-generated reserved-name table + `__` file-scope suffix;
// `probes/name-collision/` now compiles with 0 errors).
//
// The rename is KEPT DELIBERATELY (compiler-gaps.md G8): it no longer rests on that
// mangling staying correct -- a regression would come back as a *socket* error
// message pointing somewhere else entirely -- and `bindTo` reads as the verb phrase.
// `Binding.of` is the class-method spelling. No semantic difference.
//
// LIVE IN ITS OWN FILE: mxmlc resolves a package-level function only from a file
// named after it (here `bindTo.as`); the `Binding` class lives in Binding.as.
package asaot.ui
{
    public function bindTo(owner:Observable, field:String):Binding
    {
        return new Binding(owner, field);
    }
}