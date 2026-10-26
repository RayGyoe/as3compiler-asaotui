// asaot.ui.ActionRegistry -- named actions and the keymap that fires them
// (design doc section 6.1-6.3).
//
// AN ACTION IS A STRING ID WITH A FUNCTION BEHIND IT, because a keymap is DATA: it
// has to name an action without naming a closure, and it has to be replaceable at
// runtime (that is the whole point of a configurable keymap). `Control.action` was
// declared in the first commit and nothing ever dispatched it; `UiApp` consults it
// now, so Enter/Space on a focused control runs the action instead of onClick.
//
// ONE DEVIATION FROM THE DESIGN DOC, stated rather than hidden: `setKeymap` takes
// an ARRAY OF OBJECTS, not a JSON string. There is no `JSON` class in this
// compiler (grep `classMap.set('JSON'` -> no match), so a JSON-string API would
// have to ship a parser and would still be unverifiable against `mxmlc`. An AS3
// object literal is the same data with the same shape, needs no parser, and fails
// at compile time when it is malformed.
//
// MATCHING IS FIRST-ENTRY-WINS, in declaration order. Specificity ranking (the
// design doc leaves it open) is deliberately NOT invented here: a keymap is read
// top to bottom, and a system where moving a line changes nothing is harder to
// reason about than one where it does.
package asaot.ui
{
    public final class ActionRegistry
    {
        private static var handlers:Object = {};
        private static var schemas:Object = {};
        // Parsed entries: [{ ctx:ContextExpr, strokes:[{s:KeyStroke, id:String, payload:Object, text:String}] }]
        // null when no keymap was set -- the per-keypress cost is one null test.
        private static var entries:Array = null;

        // ---- actions -------------------------------------------------------
        public static function register(id:String, handler:Function, schema:Object = null):void
        {
            if (id == null || id == "")
                throw new Error("asaot.ui.ActionRegistry.register: an action needs a non-empty id"
                    + " (it is what a keymap refers to).");
            if (handler == null)
                throw new Error("asaot.ui.ActionRegistry.register(\"" + id + "\"): a null handler"
                    + " would make the action unreachable; pass a function.");
            handlers[id] = handler;
            schemas[id] = schema;
        }

        public static function unregister(id:String):void
        {
            handlers[id] = null;
            schemas[id] = null;
        }

        public static function has(id:String):Boolean
        {
            return id != null && handlers[id] != null;
        }

        public static function schemaOf(id:String):Object
        {
            return schemas[id];
        }

        public static function actionCount():int
        {
            var c:int = 0;
            for (var k:String in handlers)
            {
                if (handlers[k] != null) c++;
            }
            return c;
        }

        // Runs an action. A miss THROWS: a keymap entry pointing at an action nobody
        // registered is a programming error, and silently swallowing it would make
        // "my shortcut does nothing" undebuggable (AGENTS.md 2.5).
        public static function dispatch(id:String, payload:Object = null):Boolean
        {
            var f:Function = handlers[id] as Function;
            if (f == null)
                throw new Error("asaot.ui.ActionRegistry: no handler registered for action \""
                    + id + "\". Register it with ActionRegistry.register(id, handler) before"
                    + " binding it in a keymap.");
            // Called with the payload even when the handler declares no parameters:
            // AVM2 ignores EXTRA arguments and throws only on MISSING ones.
            f(payload);
            return true;
        }

        // ---- keymap --------------------------------------------------------
        //
        //   ActionRegistry.setKeymap([
        //       { context: "login", bindings: { "enter": "login.submit" } },
        //       { context: "login > modal", bindings: { "escape": "modal.cancel" } },
        //       { context: "login && os == macos", bindings: { "cmd-k": "palette.open" } },
        //       { context: "editor", bindings: { "ctrl-s": ["doc.save", { force: false }] } }
        //   ]);
        //
        // Every string, key and payload shape is validated HERE, once. A typo in a
        // context predicate or a keystroke therefore fails at install time with the
        // offending text, not at 3am on the one key the user pressed.
        public static function setKeymap(map:Array):void
        {
            if (map == null || !(map is Array))
                throw new Error("asaot.ui.ActionRegistry.setKeymap: expected an ARRAY of"
                    + " { context, bindings } entries (there is no JSON class in this compiler,"
                    + " so a JSON string is not accepted).");
            var built:Array = [];
            for (var i:int = 0; i < map.length; i++)
            {
                var e:Object = map[i];
                if (e == null)
                    throw new Error("asaot.ui.ActionRegistry.setKeymap: entry " + i + " is null.");
                var ctxText:String = e.context == null ? null : String(e.context);
                if (ctxText == null || ctxText == "")
                    throw new Error("asaot.ui.ActionRegistry.setKeymap: entry " + i
                        + " has no `context`. Every entry names the context it applies to"
                        + " (use a shared context string for a global binding).");
                var expr:ContextExpr = ContextExpr.parse(ctxText);
                var b:Object = e.bindings;
                if (b == null)
                    throw new Error("asaot.ui.ActionRegistry.setKeymap: entry " + i
                        + " (\"" + ctxText + "\") has no `bindings` object.");
                var strokes:Array = [];
                for (var key:String in b)
                {
                    var ks:KeyStroke = KeyStroke.parse(key);
                    var v:* = b[key];
                    var id:String = null;
                    var payload:Object = null;
                    if (v is Array)
                    {
                        var pair:Array = v as Array;
                        if (pair.length == 0)
                            throw new Error("asaot.ui.ActionRegistry.setKeymap: \"" + key
                                + "\" in \"" + ctxText + "\" has an empty [action, payload] pair.");
                        id = String(pair[0]);
                        payload = pair.length > 1 ? (pair[1] as Object) : null;
                    }
                    else id = String(v);
                    if (id == null || id == "")
                        throw new Error("asaot.ui.ActionRegistry.setKeymap: \"" + key
                            + "\" in \"" + ctxText + "\" names no action.");
                    strokes.push({ s: ks, id: id, payload: payload, text: key });
                }
                if (strokes.length == 0)
                    throw new Error("asaot.ui.ActionRegistry.setKeymap: entry " + i + " (\""
                        + ctxText + "\") binds no keys. An empty entry is a mistake, not a"
                        + " no-op.");
                built.push({ ctx: expr, strokes: strokes });
            }
            entries = built.length == 0 ? null : built;
        }

        public static function clearKeymap():void
        {
            entries = null;
        }

        public static function keymapEntryCount():int
        {
            return entries == null ? 0 : entries.length;
        }

        public static function bindingCount():int
        {
            if (entries == null) return 0;
            var c:int = 0;
            for (var i:int = 0; i < entries.length; i++)
            {
                c = c + (entries[i].strokes as Array).length;
            }
            return c;
        }

        // Test/tooling hook: forget EVERYTHING (actions and keymap). Static state is
        // process-wide, so a probe that installs a keymap must be able to start from
        // a known-empty registry.
        public static function reset():void
        {
            handlers = {};
            schemas = {};
            entries = null;
        }

        // ---- the per-keypress lookup ---------------------------------------
        //
        // `contexts` is innermost-first (UiApp builds it from the focus chain).
        // Returns { id:String, payload:Object } or null. Never throws: an unmatched
        // key must fall through to the built-ins (text input, Tab, widget keys).
        public static function lookup(keyCode:int, ctrl:Boolean, alt:Boolean,
                                      shift:Boolean, meta:Boolean,
                                      contexts:Array):Object
        {
            if (entries == null) return null;
            for (var i:int = 0; i < entries.length; i++)
            {
                var e:Object = entries[i];
                if (!ContextExpr(e.ctx).matches(contexts)) continue;
                var strokes:Array = e.strokes as Array;
                for (var j:int = 0; j < strokes.length; j++)
                {
                    var st:Object = strokes[j];
                    if (KeyStroke(st.s).matches(keyCode, ctrl, alt, shift, meta))
                        return { id: String(st.id), payload: st.payload };
                }
            }
            return null;
        }

        public function ActionRegistry() { }
    }
}