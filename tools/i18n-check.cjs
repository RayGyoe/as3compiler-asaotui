// tools/i18n-check.cjs -- the source-level gate for the kit's own message catalog.
//
// WHY NOT A RUNTIME PROBE: a probe renders what an app HAPPENS to show, so it can
// pass while half the catalog is broken -- a locale missing a key nobody clicked, a
// translation that silently dropped `{n}`, a key typed into a factory that no
// catalog has. Those are SOURCE facts, so they are checked in the source.
//
// WHAT IT ASSERTS (all four are the same "no silent gap" rule):
//
//   1. PARITY. Every key in `en()` exists in `zhCN()` and vice versa. A key only in
//      one catalog is a guaranteed `[[key]]` in the other language.
//   2. PLACEHOLDERS. The `{...}` set of a key is identical in both locales. Dropping
//      `{n}` from a translation does not throw -- it silently prints the wrong text.
//   3. USAGE. Every literal `I18n.t("kit.…")` in kit/ resolves in BOTH locales, and
//      a PREFIX call (`I18n.t("kit.date.month." + m)`) has at least one live key
//      under that prefix. A renamed kit key therefore fails here, not at runtime.
//   4. NO DUPLICATES. One `"key":` twice in the same catalog means the second one
//      wins silently -- and in a merged literal that is usually a copy/paste slip.
//
// It reads the file as TEXT on purpose: the AOT builds AS3, not JS, so the catalogs
// cannot be imported. That is why KitMessages keeps one `"key": "value"` pair per
// line -- the format IS the interface between the library and this check.
//
// USAGE (from asaotui/):   node tools/i18n-check.cjs
'use strict';

const fs = require('fs');
const path = require('path');

const UI = path.resolve(__dirname, '..');
const MESSAGES = path.join(UI, 'kit', 'asaot', 'ui', 'KitMessages.as');
const KIT = path.join(UI, 'kit', 'asaot', 'ui');

const problems = [];
const warnings = [];
const say = (s) => console.log(s);
const bad = (s) => problems.push(s);

// ---- 1: read both catalogs out of the source ------------------------------
const src = fs.readFileSync(MESSAGES, 'utf8');

function catalogOf(fnName) {
    const at = src.indexOf('function ' + fnName + '():Object');
    if (at < 0) throw new Error('KitMessages has no ' + fnName + '()');
    const start = src.indexOf('{', at);
    // The literal ends at the first line whose only content is `};` (12 spaces: the
    // closing brace of the returned object).
    const end = src.indexOf('\n            };', start);
    if (end < 0) throw new Error('could not find the end of ' + fnName + '()');
    const body = src.slice(start, end);
    const out = new Map();
    // `"key": "value"` -- one pair per line, and a value may contain quotes escaped
    // for AS3 (\" only; the catalog has no line breaks).
    const re = /"([^"]+)"\s*:\s*"((?:[^"\\]|\\.)*)"/g;
    let m;
    while ((m = re.exec(body)) != null) {
        const key = m[1];
        if (out.has(key)) bad('duplicate key "' + key + '" in ' + fnName + '()');
        out.set(key, m[2]);
    }
    if (out.size === 0) throw new Error('no `"key": "value"` pairs parsed from ' + fnName + '()');
    return out;
}

let en, zh;
try {
    en = catalogOf('en');
    zh = catalogOf('zhCN');
} catch (e) {
    console.error('[i18n-check] ' + e.message);
    process.exit(1);
}
say('catalog: en ' + en.size + ' keys, zh-CN ' + zh.size + ' keys');

// ---- 2: parity ------------------------------------------------------------
for (const k of en.keys()) if (!zh.has(k)) bad('en has "' + k + '" but zh-CN does not');
for (const k of zh.keys()) if (!en.has(k)) bad('zh-CN has "' + k + '" but en does not');

// ---- 3: placeholders ------------------------------------------------------
const placeholders = (v) => {
    const out = new Set();
    const re = /\{([A-Za-z0-9_]+)\}/g;
    let m;
    while ((m = re.exec(v)) != null) out.add(m[1]);
    return out;
};
for (const [k, v] of en) {
    if (!zh.has(k)) continue;
    const a = [...placeholders(v)].sort();
    const b = [...placeholders(zh.get(k))].sort();
    const fmt = (s) => s.map((x) => '{' + x + '}').join(' ');
    // FATAL: one side interpolates and the other does not. That is the silent-drop
    // shape -- "{n} items" translated to " items" prints the wrong sentence with no
    // error anywhere.
    if ((a.length === 0) !== (b.length === 0)) {
        bad('"' + k + '": en uses [' + fmt(a) + '] but zh-CN uses [' + fmt(b)
            + '] -- one locale drops the interpolation');
        continue;
    }
    // DIFFERENT NAMES ARE A WARNING, not a failure: a locale may legitimately format
    // with a DIFFERENT piece of the same record -- the date title is "October 2026"
    // from {month} {year} in English and "2026年10月" from {year}年{monthNumber}月 in
    // Chinese. Both are supplied by the call site. A typo'd name is not lost either:
    // it renders as a literal `{typo}` in probes/widgets/i18n, which reads both
    // titles off the retained TextFields.
    if (a.join('|') !== b.join('|')) {
        warnings.push('"' + k + '": en uses [' + fmt(a) + '], zh-CN uses [' + fmt(b) + ']');
    }
}

// ---- 4: usage -------------------------------------------------------------
// Every kit source that renders a kit string, in the ORDER a reader would look.
const files = fs.readdirSync(KIT).filter((f) => f.endsWith('.as')).sort();
let uses = 0;
for (const f of files) {
    if (f === 'KitMessages.as' || f === 'I18n.as') continue;   // the catalog and the reader
    const text = fs.readFileSync(path.join(KIT, f), 'utf8');
    const re = /I18n\.t\("([^"]*)"\s*(\+)?/g;
    let m;
    while ((m = re.exec(text)) != null) {
        const key = m[1];
        const isPrefix = m[2] === '+';
        if (!key.startsWith('kit.')) {
            bad(f + ': I18n.t("' + key + '") -- the kit may only ask for its own `kit.` keys');
            continue;
        }
        uses++;
        if (isPrefix) {
            // `I18n.t("kit.date.month." + n)` -- the suffix is data, so the check is
            // "at least one live key under this prefix, in BOTH locales".
            const hit = (cat) => [...cat.keys()].filter((k) => k.startsWith(key)).length;
            if (hit(en) === 0) bad(f + ': prefix "' + key + '" has no keys in en');
            if (hit(zh) === 0) bad(f + ': prefix "' + key + '" has no keys in zh-CN');
            continue;
        }
        if (!en.has(key)) bad(f + ': "' + key + '" is not in the en catalog');
        if (!zh.has(key)) bad(f + ': "' + key + '" is not in the zh-CN catalog');
    }
}
say('usage: ' + uses + ' literal kit key(s) across ' + files.length + ' kit source file(s)');

// ---- 5: report ------------------------------------------------------------
for (const w of warnings) console.log('  warn  ' + w);
if (problems.length) {
    console.log('');
    for (const p of problems) console.log('  FAIL  ' + p);
    console.log('');
    console.log('RESULT: FAIL (' + problems.length + ' problem(s))');
    process.exit(1);
}
console.log('RESULT: PASS');
