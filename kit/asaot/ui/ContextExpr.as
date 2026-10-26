// asaot.ui.ContextExpr -- the `context` half of a keymap entry, e.g.
//   "login"                  the focused node is inside a `keyContext: "login"`
//   "login > modal"          ... inside both, and login is the ANCESTOR
//   "os == macos && editor"  an "os=macos" context is active AND an "editor" one is
//   "!im"                    no "im" context is active
//
// THE CONTEXT SET is the list of `keyContext` strings from the focused node up to
// the root, innermost FIRST. A context string is either a bare name ("editor") or a
// `name=value` pair ("os=macos") -- so `os == macos` is a lookup for that PAIR, not
// a second syntax for the same thing. (This is the design doc's section 6.2 grammar;
// the one deviation is that the key-value separator in a context string is `=`,
// because a context string is data the author writes, not an expression.)
//
// `a > b` is "a is an ANCESTOR of b": since the list is innermost-first, that is
// "an index of a is GREATER than an index of b". Getting that backwards is the one
// mistake this syntax invites, so it is stated once here and pinned by the probe.
//
// THE AST IS NESTED ARRAYS, not classes: a predicate is parsed once (at setKeymap)
// and walked per keypress, and this is the smallest shape that does both without
// allocating per key.
package asaot.ui
{
    public final class ContextExpr
    {
        public var source:String;

        private var root:Array;
        private var pos:int;
        private var text:String;

        public function ContextExpr(source:String)
        {
            this.source = source;
            this.root = null;
        }

        public static function parse(s:String):ContextExpr
        {
            var e:ContextExpr = new ContextExpr(s);
            e.text = s;
            e.pos = 0;
            e.skipWs();
            if (e.pos >= e.text.length)
                throw new Error("asaot.ui keymap: an empty `context` is not a predicate.");
            e.root = e.parseOr();
            e.skipWs();
            if (e.pos < e.text.length)
                throw new Error("asaot.ui keymap: unexpected \"" + e.text.substring(e.pos)
                    + "\" at " + e.pos + " in context \"" + s + "\".");
            return e;
        }

        public function matches(contexts:Array):Boolean
        {
            if (this.root == null) return false;
            return eval(this.root, contexts);
        }

        // ---- grammar ------------------------------------------------------
        private function parseOr():Array
        {
            var left:Array = parseAnd();
            while (true)
            {
                this.skipWs();
                if (!this.eat("||")) break;
                var right:Array = parseAnd();
                left = ["or", left, right];
            }
            return left;
        }

        private function parseAnd():Array
        {
            var left:Array = parseUnary();
            while (true)
            {
                this.skipWs();
                if (!this.eat("&&")) break;
                var right:Array = parseUnary();
                left = ["and", left, right];
            }
            return left;
        }

        private function parseUnary():Array
        {
            this.skipWs();
            if (this.eat("!")) return ["not", parseUnary()];
            if (this.eat("("))
            {
                var inner:Array = parseOr();
                this.skipWs();
                if (!this.eat(")"))
                    throw new Error("asaot.ui keymap: missing \")\" in context \"" + this.text + "\".");
                return inner;
            }
            return parseRelation();
        }

        // atom (">" atom)*  -- a > b > c folds to (a > b) && (b > c).
        private function parseRelation():Array
        {
            var acc:Array = null;
            var prev:Array = parseAtom();
            while (true)
            {
                this.skipWs();
                if (!this.eat(">")) break;
                var next:Array = parseAtom();
                var pair:Array = ["above", prev, next];
                acc = acc == null ? pair : ["and", acc, pair];
                prev = next;
            }
            return acc == null ? prev : acc;
        }

        private function parseAtom():Array
        {
            this.skipWs();
            var name:String = this.readIdent();
            if (name == "") 
                throw new Error("asaot.ui keymap: expected a context name at " + this.pos
                    + " in \"" + this.text + "\".");
            this.skipWs();
            if (this.eat("=="))
            {
                this.skipWs();
                return ["eq", name, this.readValue()];
            }
            if (this.eat("!="))
            {
                this.skipWs();
                return ["ne", name, this.readValue()];
            }
            return ["id", name];
        }

        private function readIdent():String
        {
            var start:int = this.pos;
            while (this.pos < this.text.length && isIdentChar(this.text.charCodeAt(this.pos))) this.pos++;
            return this.text.substring(start, this.pos);
        }

        // Bare word, or a quoted string (single or double) so a value may contain
        // spaces. An unterminated quote is an error, never a silent empty value.
        private function readValue():String
        {
            var q:int = this.pos < this.text.length ? this.text.charCodeAt(this.pos) : 0;
            if (q == 34 || q == 39)
            {
                this.pos++;
                var start:int = this.pos;
                while (this.pos < this.text.length && this.text.charCodeAt(this.pos) != q) this.pos++;
                if (this.pos >= this.text.length)
                    throw new Error("asaot.ui keymap: unterminated quote in context \"" + this.text + "\".");
                var v:String = this.text.substring(start, this.pos);
                this.pos++;
                return v;
            }
            var w:String = this.readIdent();
            if (w == "")
                throw new Error("asaot.ui keymap: expected a value after \"==\" at " + this.pos
                    + " in \"" + this.text + "\".");
            return w;
        }

        private function eat(tok:String):Boolean
        {
            if (this.text.substr(this.pos, tok.length) == tok)
            {
                this.pos += tok.length;
                return true;
            }
            return false;
        }

        private function skipWs():void
        {
            while (this.pos < this.text.length && this.text.charCodeAt(this.pos) <= 32) this.pos++;
        }

        private static function isIdentChar(c:int):Boolean
        {
            if (c >= 97 && c <= 122) return true;    // a-z
            if (c >= 65 && c <= 90) return true;     // A-Z
            if (c >= 48 && c <= 57) return true;     // 0-9
            return c == 95 || c == 46 || c == 45;    // _ . -
        }

        // ---- evaluation ---------------------------------------------------
        private static function eval(node:Array, ctx:Array):Boolean
        {
            var kind:String = node[0];
            if (kind == "or") return eval(node[1], ctx) || eval(node[2], ctx);
            if (kind == "and") return eval(node[1], ctx) && eval(node[2], ctx);
            if (kind == "not") return !eval(node[1], ctx);
            if (kind == "above")
            {
                // a is an ANCESTOR of b: the list is innermost-first, so a's index is
                // the LARGER one.
                var m:int = ctx == null ? 0 : ctx.length;
                for (var i:int = 0; i < m; i++)
                {
                    if (!atomAt(node[1], ctx[i])) continue;
                    for (var j:int = 0; j < i; j++)
                    {
                        if (atomAt(node[2], ctx[j])) return true;
                    }
                }
                return false;
            }
            if (kind == "id" || kind == "eq" || kind == "ne")
            {
                var n:int = ctx == null ? 0 : ctx.length;
                // `ne` is "NO context carries this pair" -- the negation is over the
                // whole set, not per entry (a per-entry test would make `!=` mean
                // "some context is not this", which is true almost always).
                for (var k:int = 0; k < n; k++)
                {
                    if (atomAt(node, ctx[k])) return kind != "ne";
                }
                return kind == "ne";
            }
            return false;
        }

        // One atom against ONE context string.
        private static function atomAt(node:Array, c:String):Boolean
        {
            if (c == null) return false;
            var kind:String = node[0];
            var eq:int = c.indexOf("=");
            var name:String = eq < 0 ? c : c.substring(0, eq);
            var value:String = eq < 0 ? "" : c.substring(eq + 1);
            if (kind == "id") return name == node[1];
            if (kind == "eq") return name == node[1] && value == node[2];
            return false;
        }
    }
}