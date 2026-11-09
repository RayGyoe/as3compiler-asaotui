// tools/demo-i18n.cjs -- the docs demo's own translation catalog: extract and check.
//
// WHY A TOOL AND NOT `I18n`: the docs app has 267 sections and 60 pages whose prose
// is written INLINE, next to the live demo and the source snippet it describes. Two
// ways to translate that prose:
//
//   (a) invent 900 keys (`demo.box.s3.p2`) and wrap every literal at the call site;
//   (b) keep the English as the KEY, and keep the translations in one table.
//
// (b) is what this demo does: the source stays readable, a translator sees the
// sentence they are translating, and `tr()` costs one dictionary lookup with no
// string building (the source literal IS the key instance -- steady state allocates
// nothing, which matters because these strings are rebuilt on every describe).
// The price of (b) is that a MISS is silent: an untranslated line simply stays
// English. That price is paid HERE instead of at runtime -- this tool walks the
// demo sources, extracts every heading / prose paragraph / page blurb, and fails if
// the `zh()` table does not cover them. So the catalog cannot silently rot.
//
// WHAT IT EXTRACTS (the two ways a display string reaches the screen)
//   * `new DocSection(heading, [prose...], ...)` -- the page body, written inline.
//   * `new DocPage(..., blurb)` and `DemoText.t("...")` -- the shell's labels and
//     every explicit `tr()` call.
// A third form is NOT translated on purpose: the live demos' own widget labels
// (`text("Hello")`, `button({ label: "Save" })`) are the sample data the code
// snippet beside them shows. Translating one side of that pair would make the
// visible source disagree with the visible result, which is the opposite of what
// a component reference is for.
//
// WHAT IT ASSERTS
//   1. COVERAGE      every extracted display string has a `zh` entry.
//   2. NO STALE      every `zh` entry is still a string the demo actually shows
//                    (a renamed heading otherwise leaves a dead row forever).
//   3. SHAPE         no newline/tab in a translation, and no empty value -- those
//                    break the one-pair-per-line catalog format. Braces ARE
//                    allowed: prose quotes code (`{ padding: 24 }`), and DemoText
//                    looks a whole sentence up, so `{}` is never interpolation.
//
// USAGE (from asaotui/):
//   node tools/demo-i18n.cjs --extract        # print { "English": "" } for the files
//   node tools/demo-i18n.cjs --extract DocsData.as > temp/x.json
//   node tools/demo-i18n.cjs                  # the gate (exit 0 = complete)
'use strict';

const fs = require('fs');
const path = require('path');

const UI = path.resolve(__dirname, '..');
const DEMO = path.join(UI, 'ui-demo', 'demo');
const MESSAGES = path.join(DEMO, 'DemoMessages.as');

// ---- a tiny AS3 tokenizer, enough for argument scanning ----------------------
// Comments and string escapes are the only tricky parts; nesting is tracked by hand
// because the extracted shapes are fixed (call -> literal / array).
function tokens(src) {
    const out = [];
    let i = 0;
    const n = src.length;
    while (i < n) {
        const c = src[i];
        if (c === '/' && src[i + 1] === '/') {
            while (i < n && src[i] !== '\n') i++;
            continue;
        }
        if (c === '/' && src[i + 1] === '*') {
            i += 2;
            while (i < n && !(src[i] === '*' && src[i + 1] === '/')) i++;
            i += 2;
            continue;
        }
        if (c === '"' || c === "'") {
            const quote = c;
            let v = '';
            i++;
            while (i < n && src[i] !== quote) {
                if (src[i] === '\\') {
                    const e = src[i + 1];
                    if (e === 'n') v += '\n';
                    else if (e === 't') v += '\t';
                    else if (e === 'r') v += '\r';
                    else v += e;           // \" \\ \' and anything else copied raw
                    i += 2;
                } else {
                    v += src[i++];
                }
            }
            i++;
            out.push({ t: 'str', v: v });
            continue;
        }
        if (/[A-Za-z_$]/.test(c)) {
            let v = '';
            while (i < n && /[A-Za-z0-9_$]/.test(src[i])) v += src[i++];
            out.push({ t: 'id', v: v });
            continue;
        }
        if (/[0-9]/.test(c)) {
            let v = '';
            while (i < n && /[0-9.xXa-fA-F]/.test(src[i])) v += src[i++];
            out.push({ t: 'num', v: v });
            continue;
        }
        if (/\s/.test(c)) { i++; continue; }
        out.push({ t: 'p', v: c });
        i++;
    }
    return out;
}

// The argument lists of one call, starting at the '(' token index.
function argSlices(tk, open) {
    const args = [];
    let depth = 0;
    let cur = [];
    for (let i = open + 1; i < tk.length; i++) {
        const t = tk[i];
        const c = t.t === 'p' ? t.v : null;
        if (c === '(' || c === '[' || c === '{') depth++;
        else if (c === ')') {
            if (depth === 0) { args.push(cur); return args; }
            depth--;
        } else if (c === ']' || c === '}') depth--;
        else if (c === ',' && depth === 0) { args.push(cur); cur = []; continue; }
        cur.push(t);
    }
    args.push(cur);
    return args;
}

// A prose argument is an array literal of paragraph literals. One element must be
// EXACTLY one string token: a concatenation would have no single key to translate,
// so it is reported rather than silently skipped.
function paragraphsOf(arg) {
    const out = [];
    let depth = 0;
    let cur = [];
    const flush = () => {
        const strs = cur.filter((t) => t.t === 'str');
        if (strs.length === 1 && cur.length === 1) out.push(strs[0].v);
        else if (strs.length > 0) out.push({ concat: strs.map((s) => s.v).join('') });
    };
    for (const t of arg) {
        const c = t.t === 'p' ? t.v : null;
        if (c === '[') { depth++; if (depth === 1) continue; }
        if (c === ']') { depth--; if (depth === 0) { flush(); cur = []; continue; } }
        if (c === ',' && depth === 1) { flush(); cur = []; continue; }
        if (depth >= 1) cur.push(t);
    }
    return out;
}

// ---- the one indirection the shell has ---------------------------------------
const INDIRECT = [{ file: 'DocsCatalog.as', name: 'GROUPS' }];

// The string literals of `const NAME:Array = [ "a", "b" ]`.
function constStrings(src, name) {
    const at = src.indexOf('const ' + name);
    if (at < 0) return [];
    const open = src.indexOf('[', at);
    const close = src.indexOf(']', open);
    if (open < 0 || close < 0) return [];
    const tk = tokens(src.slice(open, close + 1));
    return tk.filter((t) => t.t === 'str').map((t) => t.v);
}

function extractFile(file) {
    const src = fs.readFileSync(file, 'utf8');
    const tk = tokens(src);
    const found = [];          // { kind, text }
    // SHOWN VIA A VARIABLE: the index headings are `DemoText.t(String(DocsCatalog.GROUPS[i]))`.
    // The literal sits one step away from the call, so the extractor follows the only
    // indirection the shell has: a named const array of display strings. Everything
    // else passed as a variable is NOT extracted -- and then a row for it would be
    // reported stale, which is the failure mode we want (a visible missing
    // translation) rather than a silent one.
    for (const ind of INDIRECT) {
        if (path.basename(file) !== ind.file) continue;
        for (const s of constStrings(src, ind.name)) found.push({ kind: 'label', text: s });
    }
    for (let i = 0; i + 2 < tk.length; i++) {
        if (tk[i].t !== 'id' || tk[i].v !== 'new') continue;
        const name = tk[i + 1];
        if (name.t !== 'id') continue;
        if (name.v !== 'DocSection' && name.v !== 'DocPage') continue;
        if (tk[i + 2].t !== 'p' || tk[i + 2].v !== '(') continue;
        const args = argSlices(tk, i + 2);
        if (name.v === 'DocSection') {
            if (args[0] && args[0].length === 1 && args[0][0].t === 'str') {
                found.push({ kind: 'heading', text: args[0][0].v });
            }
            if (args[1]) {
                for (const p of paragraphsOf(args[1])) {
                    if (typeof p === 'string') found.push({ kind: 'prose', text: p });
                    else found.push({ kind: 'CONCAT', text: p.concat });
                }
            }
        } else if (args[3] && args[3].length === 1 && args[3][0].t === 'str') {
            found.push({ kind: 'blurb', text: args[3][0].v });
        }
    }
    // An EXPLICIT lookup: `DemoText.t("Index")`. Same table, same contract -- the
    // only difference is that the author wrote the call instead of the constructor
    // doing it.
    for (let i = 0; i + 4 < tk.length; i++) {
        if (tk[i].t !== 'id' || tk[i].v !== 'DemoText') continue;
        if (tk[i + 1].t !== 'p' || tk[i + 1].v !== '.') continue;
        if (tk[i + 2].t !== 'id' || tk[i + 2].v !== 't') continue;
        if (tk[i + 3].t !== 'p' || tk[i + 3].v !== '(') continue;
        const args = argSlices(tk, i + 3);
        if (args[0] && args[0].length === 1 && args[0][0].t === 'str') {
            found.push({ kind: 'label', text: args[0][0].v });
        }
    }
    return found;
}

// ---- the catalog ------------------------------------------------------------
function catalog() {
    const src = fs.readFileSync(MESSAGES, 'utf8');
    const at = src.indexOf('function zh():Object');
    if (at < 0) throw new Error('DemoMessages has no zh()');
    const start = src.indexOf('{', at);
    // BRACE MATCHING, not a marker string: the table's indentation is a style
    // choice, and a gate that fails because a block was re-indented is a gate that
    // gets deleted. Strings are skipped so a `}` inside a sentence counts.
    let end = -1;
    let depth = 0;
    for (let i = start; i < src.length; i++) {
        const c = src[i];
        if (c === '"') {
            i++;
            while (i < src.length && src[i] !== '"') { if (src[i] === '\\') i++; i++; }
            continue;
        }
        if (c === '{') depth++;
        else if (c === '}') {
            depth--;
            if (depth === 0) { end = i; break; }
        }
    }
    if (end < 0) throw new Error('could not find the end of zh()');
    const body = src.slice(start, end);
    const map = new Map();
    const re = /"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"/g;
    let m;
    while ((m = re.exec(body)) != null) {
        const k = m[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\');
        if (map.has(k)) throw new Error('duplicate key in zh(): ' + JSON.stringify(k.slice(0, 60)));
        map.set(k, m[2]);
    }
    return map;
}

const files = fs.readdirSync(DEMO).filter((f) => /^Docs.*\.as$/.test(f)).sort();

if (process.argv[2] === '--extract') {
    const only = process.argv[3];
    const picked = only ? files.filter((f) => f === only) : files;
    if (only && picked.length === 0) { console.error('no such file: ' + only); process.exit(2); }
    const seen = new Map();
    for (const f of picked) {
        for (const e of extractFile(path.join(DEMO, f))) {
            if (e.kind === 'CONCAT') { console.error('CONCAT in ' + f + ': ' + JSON.stringify(e.text)); continue; }
            if (!seen.has(e.text)) seen.set(e.text, f);
        }
    }
    const out = {};
    for (const k of [...seen.keys()].sort()) out[k] = '';
    console.log(JSON.stringify(out, null, 2));
    process.exit(0);
}

// ---- the gate ---------------------------------------------------------------
const problems = [];
const shown = new Map();       // english -> "file:kind", first sighting
let total = 0;
const perKind = { heading: 0, prose: 0, blurb: 0, label: 0 };
const concats = [];
for (const f of files) {
    for (const e of extractFile(path.join(DEMO, f))) {
        if (e.kind === 'CONCAT') { concats.push(f + ': ' + JSON.stringify(e.text.slice(0, 70))); continue; }
        total++;
        perKind[e.kind] = (perKind[e.kind] || 0) + 1;
        if (!shown.has(e.text)) shown.set(e.text, f + ':' + e.kind);
    }
}
console.log('demo text: ' + total + ' display string(s) -- ' + perKind.heading + ' headings, '
    + perKind.prose + ' prose paragraphs, ' + perKind.blurb + ' blurbs, '
    + perKind.label + ' labels');
console.log('           ' + shown.size + ' distinct after de-duplication');
if (concats.length) {
    for (const c of concats) problems.push('a prose element is concatenated, so it has no single key -- ' + c);
}

const zh = catalog();
let translated = 0;
for (const [en, where] of shown) {
    if (!zh.has(en)) { problems.push('missing zh for ' + JSON.stringify(en.slice(0, 70)) + '   [' + where + ']'); continue; }
    translated++;
    const v = zh.get(en);
    if (v === '') problems.push('empty zh for ' + JSON.stringify(en.slice(0, 50)));
    // The catalog is one pair per line; an escape here would break that format (and
    // a tab/newline inside a paragraph would break the block arithmetic besides).
    if (/\\[ntr]/.test(v) || /[\n\t]/.test(v)) {
        problems.push('zh for ' + JSON.stringify(en.slice(0, 50)) + ' contains a newline/tab');
    }
}
let stale = 0;
for (const k of zh.keys()) if (!shown.has(k)) { stale++; problems.push('stale zh row, the demo no longer shows it: ' + JSON.stringify(k.slice(0, 70))); }
console.log('catalog: ' + zh.size + ' row(s), ' + translated + '/' + shown.size + ' covered, ' + stale + ' stale');

if (problems.length) {
    console.log('');
    const shownProblems = problems.slice(0, 40);
    for (const p of shownProblems) console.log('  FAIL  ' + p);
    if (problems.length > shownProblems.length) console.log('  ... and ' + (problems.length - shownProblems.length) + ' more');
    console.log('');
    console.log('RESULT: FAIL (' + problems.length + ' problem(s))');
    process.exit(1);
}
console.log('RESULT: PASS');
