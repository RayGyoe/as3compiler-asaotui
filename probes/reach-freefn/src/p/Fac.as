// p/Fac -- a file whose only top-level declaration is a FREE FUNCTION. That is
// the one thing that makes it special: `--air-app`'s closure cannot prune a file
// whose top-level code is not a class/interface declaration, so it is FORCED into
// the kept set and its references are collected in a pass that runs AFTER the
// closure's work queue has already drained (src/reach.ts, the two loops between
// the `while (queue.length > 0)` drain and the final `kept` filter).
//
// This factory is the entire shape of G13: it names p.Leaf, and everything Leaf
// itself names -- its superclass Base, and Helper from its constructor -- is then
// never reached, because the post-loop pass marks newly discovered classes
// reachable without ever expanding them.
package p
{
    public function make():Leaf
    {
        return new Leaf();
    }
}