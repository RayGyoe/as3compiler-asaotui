// probes/name-collision/p/Bind.as -- does a public package-level function whose
// NAME collides with a libc/socket symbol survive codegen?
//
// A package-level function is emitted into C under its OWN name (no mangling), so
//  should collide with the POSIX/socket bind(2) if any header declares it.
// This probe exists to verify that claim rather than repeat it.
package p
{
    public function bind(owner:int, field:int):int
    {
        return owner + field;
    }
}
