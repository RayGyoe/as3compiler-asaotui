// tools/callback-arity.cjs -- the AUTHOR-CALLBACK ARITY contract, as a source scan.
//
// WHY THIS GATE EXISTS
// --------------------
// On AVM2, calling a closure with MORE arguments than it declares is fine (the
// extras are dropped), but calling it with FEWER throws
// "Error #1063: Argument count mismatch". Our runtime reproduces that faithfully,
// and the frame guard then recovers the frame -- so the author's handler simply
// never runs and the only trace is one console line. That is exactly how the docs
// shipped a broken slider: SliderWidget called `onChange()` while every docs page
// (and the whole point of the callback) declares `function (v:Number)`. The page
// rendered, the click threw #1063, the knob never moved, and no gate noticed --
// probes/widgets/form only ever clicked BOUND controls, so the `onChange` branch was
// never executed anywhere.
//
// WHAT IT CHECKS (two directions, because either one is a #1063)
//   1. INVOCATIONS inside kit/: every call to a VALUE callback passes exactly one
//      argument, and every ZERO-argument hook is called with none. This is the
//      direction that broke.
//   2. DECLARATIONS in ui-demo/demo + probes/: every handler written for a value
//      callback declares exactly one parameter, and every zero-argument hook's
//      handler declares none. This is the direction an author breaks.
//
// HOW THE SOURCE IS READ
//   `//` comments are stripped (with string awareness, so `"a // b"` survives) and
//   `/* */` blocks are skipped, because the kit legitimately talks ABOUT these calls
//   in prose (`calls onChange(value)`) and prose must not be graded as code.
//
// WHAT IT CANNOT SEE (stated, not hidden): a handler passed BY REFERENCE --
// `onChange: this.tabChanged` or `n.onChange = cb.onChange`. Resolving the arity of
// the referenced method needs types and a call graph; the behavioural half of the
// contract is probes/widgets/callback's job.
//
// USAGE (from asaotui/):   node tools/callback-arity.cjs
// Exit 0 = every call site and every declaration matches; 1 = at least one does not.
'use strict';

const fs = require('fs');
const path = require('path');

const UI = path.resolve(__dirname, '..');

// The callbacks that carry a VALUE: called with exactly one argument, declared with
// exactly one parameter.
const VALUE_CBS = ['onChange', 'onCommit', 'onToggle', 'onSelect', 'onNavigate', 'onQuery', 'onSubmit', 'onError'];
// The ZERO-argument hooks, graded the OTHER way: called with nothing, declared with
// nothing. `onClick` is the container contract; `onLoad` is the image load's (the
// completion carries nothing to pass -- the pixels are on the node, and whoever needs
// the size reads it from there).
const ZERO_CBS = ['onClick', 'onLoad'];
const ALL_CBS = VALUE_CBS.concat(ZERO_CBS);
const isZero = (cb) => ZERO_CBS.indexOf(cb) >= 0;

// ---- source walking --------------------------------------------------------
function asFiles(root) {
  const out = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith('.as')) out.push(p);
    }
  };
  walk(path.join(UI, root));
  return out;
}

// Strip comments but KEEP every character position meaningful enough to report a
// line number: the stripped text keeps its newlines and the removed span becomes
// spaces, so offsets still map to (file, line).
function stripComments(src) {
  let out = '';
  let i = 0;
  let inStr = null;
  while (i < src.length) {
    const c = src[i];
    const n = src[i + 1];
    if (inStr) {
      out += c;
      if (c === '\\') { out += n === undefined ? '' : n; i += 2; continue; }
      if (c === inStr) inStr = null;
      i++;
      continue;
    }
    if (c === '"' || c === "'") { inStr = c; out += c; i++; continue; }
    if (c === '/' && n === '/') {
      while (i < src.length && src[i] !== '\n') { out += ' '; i++; }
      continue;
    }
    if (c === '/' && n === '*') {
      while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) { out += src[i] === '\n' ? '\n' : ' '; i++; }
      out += '  ';
      i += 2;
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

const lineOf = (text, idx) => text.slice(0, idx).split('\n').length;

// The argument text between `(` at `open` and its matching `)`. String-aware.
function argsAt(text, open) {
  let depth = 0;
  let i = open;
  let inStr = null;
  for (; i < text.length; i++) {
    const c = text[i];
    if (inStr) {
      if (c === '\\') { i++; continue; }
      if (c === inStr) inStr = null;
      continue;
    }
    if (c === '"' || c === "'") { inStr = c; continue; }
    if (c === '(') depth++;
    else if (c === ')') {
      depth--;
      if (depth === 0) return text.slice(open + 1, i);
    }
  }
  return null;   // unbalanced -- reported as a violation rather than guessed at
}

// How many top-level parameters a parameter list has (0 for empty / whitespace).
function countParams(list) {
  if (list == null) return -1;
  const t = list.trim();
  if (t === '') return 0;
  let depth = 0;
  let count = 1;
  for (const c of t) {
    if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') depth--;
    else if (c === ',' && depth === 0) count++;
  }
  return count;
}

const violations = [];
let invocations = 0;
let declarations = 0;

// ---- 1: invocations in kit/ ------------------------------------------------
for (const file of asFiles('kit')) {
  const raw = fs.readFileSync(file, 'utf8');
  const text = stripComments(raw);
  const rel = path.relative(UI, file).split(path.sep).join('/');
  for (const cb of ALL_CBS) {
    // NOTE the mandatory dot: a METHOD DECLARATION (`static function onClick(n, e)`) is
    // how PanelShellWidget names its private listener, and grading it as an invocation
    // was false positive #2.
    const re = new RegExp('\\.' + cb + '\\s*\\(', 'g');
    let m;
    while ((m = re.exec(text))) {
      const open = text.indexOf('(', m.index);
      // A receiver that starts with an UPPERCASE letter is a CLASS, i.e. a static
      // method that happens to share the name (`PanelShellWidget.onClick(n, e)`),
      // not the author's callback field. Measured false positive #1.
      const before = text.slice(Math.max(0, m.index - 60), m.index);
      const recv = /([A-Za-z_$][\w$]*)$/.exec(before);
      if (recv && /^[A-Z]/.test(recv[1])) continue;
      const args = argsAt(text, open);
      invocations++;
      if (args == null) {
        violations.push(rel + ':' + lineOf(text, open) + ': .' + cb + '( ... ) has unbalanced parentheses');
        continue;
      }
      const n = countParams(args);
      if (isZero(cb)) {
        if (n !== 0) {
          violations.push(rel + ':' + lineOf(text, open) + ': .' + cb + '() must be called with NO arguments (it is a zero-argument hook), got ' + n);
        }
      } else if (n !== 1) {
        violations.push(rel + ':' + lineOf(text, open) + ': .' + cb + '(...) must be called with exactly ONE argument (the new value -- a zero-argument call throws #1063 on `function (v:T)` handlers); got ' + n);
      }
    }
  }
}

// ---- 2: declarations in the demo and the probes ----------------------------
for (const root of ['ui-demo/demo', 'probes']) {
  let files;
  try { files = asFiles(root); } catch (e) { continue; }
  for (const file of files) {
    const text = stripComments(fs.readFileSync(file, 'utf8'));
    const rel = path.relative(UI, file).split(path.sep).join('/');
    for (const cb of ALL_CBS) {
      // `onChange: function (v:Number):void {`  -- and the same inside a docs snippet
      // string, which is a PRINTED contract and is graded like code on purpose.
      const re = new RegExp('\\b' + cb + '\\s*:\\s*function\\b', 'g');
      let m;
      while ((m = re.exec(text))) {
        const open = text.indexOf('(', m.index);
        if (open < 0) continue;
        const list = argsAt(text, open);
        declarations++;
        if (list == null) {
          violations.push(rel + ':' + lineOf(text, m.index) + ': ' + cb + ' handler has unbalanced parentheses');
          continue;
        }
        const n = countParams(list);
        if (isZero(cb)) {
          if (n !== 0) {
            violations.push(rel + ':' + lineOf(text, m.index) + ': an ' + cb + ' handler must declare NO parameters (it is called as ' + cb + '()), got ' + n);
          }
        } else if (n !== 1) {
          violations.push(rel + ':' + lineOf(text, m.index) + ': a ' + cb + ' handler must declare exactly ONE parameter (the new value), got ' + n);
        }
      }
    }
  }
}

// ---- report ----------------------------------------------------------------
console.log('[callback-arity] ' + invocations + ' invocation(s) in kit/, '
  + declarations + ' handler declaration(s) in ui-demo + probes/');
if (violations.length === 0) {
  console.log('[callback-arity] callbacks and invocations agree: 0 violations');
  process.exit(0);
}
console.log('[callback-arity] ' + violations.length + ' violation(s):');
for (const v of violations) console.log('  ' + v);
process.exit(1);