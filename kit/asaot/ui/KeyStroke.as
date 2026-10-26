// asaot.ui.KeyStroke -- one parsed keystroke, e.g. "ctrl-shift-s" or "escape".
//
// WHY A PARSER AND NOT A `keyCode` NUMBER IN THE KEYMAP: a keymap is edited by
// people, and a numeric key code is unreadable, unportable and silently wrong when
// it is off by one. The string form is the one every toolkit in this space uses.
//
// THE MODIFIER RULE IS EXACT MATCH, and that is deliberate: if "ctrl-s" fired while
// Shift was also held, then "ctrl-s" and "ctrl-shift-s" would be impossible to bind
// to different actions. An unbound modifier therefore means "must NOT be held".
//
// UNKNOWN NAMES THROW. A keymap with a typo ("ctrll-s", "ctlr-s", "f13") fails at
// setKeymap() time with the offending token in the message, instead of binding an
// action to a key nobody can press (AGENTS.md 2.5: never a silent fallback).
package asaot.ui
{
    public final class KeyStroke
    {
        public var code:int;
        public var ctrl:Boolean;
        public var alt:Boolean;
        public var shift:Boolean;
        public var meta:Boolean;

        public function KeyStroke(code:int, ctrl:Boolean, alt:Boolean, shift:Boolean, meta:Boolean)
        {
            this.code = code;
            this.ctrl = ctrl;
            this.alt = alt;
            this.shift = shift;
            this.meta = meta;
        }

        // "ctrl-shift-s". Modifiers may appear in any order but MUST come first, and
        // the last segment is the key itself.
        public static function parse(s:String):KeyStroke
        {
            if (s == null) throw new Error("asaot.ui keymap: an empty keystroke is not a key.");
            var t:String = trim(s);
            if (t == "") throw new Error("asaot.ui keymap: an empty keystroke is not a key.");
            // Split by hand: the kit's String surface is narrow (see compiler-gaps) and
            // `split` is not part of it.
            var parts:Array = [];
            var start:int = 0;
            for (var c0:int = 0; c0 <= t.length; c0++)
            {
                if (c0 == t.length || t.charCodeAt(c0) == 45)
                {
                    parts.push(t.substring(start, c0));
                    start = c0 + 1;
                }
            }
            // A bare "-" (or "ctrl--") would split into empty segments. The '-' KEY is
            // not expressible in this grammar; say so rather than binding something
            // else.
            for (var i:int = 0; i < parts.length; i++)
            {
                if (String(parts[i]) == "")
                    throw new Error("asaot.ui keymap: \"" + s + "\" has an empty segment. The '-'"
                        + " key itself is not expressible in the keystroke grammar; use a named"
                        + " key (e.g. \"minus\" is not defined either -- pick another binding).");
            }
            var ctrl:Boolean = false;
            var alt:Boolean = false;
            var shift:Boolean = false;
            var meta:Boolean = false;
            var last:String = String(parts[parts.length - 1]);
            for (var j:int = 0; j < parts.length - 1; j++)
            {
                var m:String = lower(String(parts[j]));
                if (m == "ctrl" || m == "control") ctrl = true;
                else if (m == "alt" || m == "option") alt = true;
                else if (m == "shift") shift = true;
                else if (m == "cmd" || m == "command" || m == "meta") meta = true;
                else
                    throw new Error("asaot.ui keymap: unknown modifier \"" + parts[j] + "\" in \""
                        + s + "\" (accepted: ctrl, control, alt, option, shift, cmd, command, meta).");
            }
            var code:int = codeOf(lower(last));
            if (code < 0)
                throw new Error("asaot.ui keymap: unknown key \"" + last + "\" in \"" + s + "\""
                    + " (accepted: a-z, 0-9, enter, escape, tab, space, backspace, delete, insert,"
                    + " home, end, pageup, pagedown, left, up, right, down, f1..f12).");
            return new KeyStroke(code, ctrl, alt, shift, meta);
        }

        public function matches(keyCode:int, kCtrl:Boolean, kAlt:Boolean, kShift:Boolean, kMeta:Boolean):Boolean
        {
            return this.code == keyCode
                && this.ctrl == kCtrl
                && this.alt == kAlt
                && this.shift == kShift
                && this.meta == kMeta;
        }

        // AIR key codes for the named keys (Keyboard constants: ENTER = 13, ...).
        private static function codeOf(name:String):int
        {
            if (name.length == 1)
            {
                var c:int = name.charCodeAt(0);
                if (c >= 97 && c <= 122) return c - 32;       // 'a' -> 65 (KeyCode A)
                if (c >= 48 && c <= 57) return c;            // '0'..'9'
                return -1;
            }
            if (name == "enter" || name == "return") return 13;
            if (name == "escape" || name == "esc") return 27;
            if (name == "tab") return 9;
            if (name == "space") return 32;
            if (name == "backspace") return 8;
            if (name == "delete" || name == "del") return 46;
            if (name == "insert") return 45;
            if (name == "home") return 36;
            if (name == "end") return 35;
            if (name == "pageup") return 33;
            if (name == "pagedown") return 34;
            if (name == "left") return 37;
            if (name == "up") return 38;
            if (name == "right") return 39;
            if (name == "down") return 40;
            if (name.length == 2 && name.charAt(0) == "f")
            {
                var n:int = name.charCodeAt(1) - 48;
                if (n >= 1 && n <= 9) return 111 + n;        // F1 = 112 .. F9 = 120
            }
            if (name.length == 3 && name.charAt(0) == "f" && name.charAt(1) == "1")
            {
                var n2:int = (name.charCodeAt(1) - 48) * 10 + (name.charCodeAt(2) - 48);
                if (n2 >= 10 && n2 <= 12) return 111 + n2;   // F10 = 121 .. F12 = 123
            }
            return -1;
        }

        // The kit's String surface is narrow (no toLowerCase -- see compiler-gaps), so
        // folding is done by hand over the ASCII range a keystroke can contain.
        private static function lower(s:String):String
        {
            var out:String = "";
            for (var i:int = 0; i < s.length; i++)
            {
                var c:int = s.charCodeAt(i);
                if (c >= 65 && c <= 90) out = out + String.fromCharCode(c + 32);
                else out = out + s.charAt(i);
            }
            return out;
        }

        private static function trim(s:String):String
        {
            var a:int = 0;
            var b:int = s.length;
            while (a < b && s.charCodeAt(a) <= 32) a++;
            while (b > a && s.charCodeAt(b - 1) <= 32) b--;
            return s.substring(a, b);
        }
    }
}