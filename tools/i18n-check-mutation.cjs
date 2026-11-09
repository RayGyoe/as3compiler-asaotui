// tools/i18n-check-mutation.cjs -- proof that `tools/i18n-check.cjs` actually BITES.
//
// The catalog gate asserts four source facts (key parity, no dropped interpolation,
// every `I18n.t("kit.…")` resolves, no duplicate key). A gate nobody has ever seen
// go red is a gate that might be asserting nothing, so each of the four is broken
// ON PURPOSE, one at a time, and the run must go red with the RIGHT message.
//
// The catalog is edited in place, so every case restores it and then compares the
// sha256 against the byte-identical original -- a "restore" that leaves one byte
// different would poison every later gate in the suite.
//
// USAGE (from asaotui/):   node tools/i18n-check-mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const MESSAGES = path.join(UI, 'kit', 'asaot', 'ui', 'KitMessages.as');
const SELECT = path.join(UI, 'kit', 'asaot', 'ui', 'select.as');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const CASES = [
    {
        id: 'M1',
        what: 'a key exists in en but not in zh-CN (parity)',
        file: MESSAGES,
        from: '                "kit.pagination.next": "next page",',
        to: '                "kit.pagination.nextX": "next page",',
        expect: /en has "kit\.pagination\.nextX" but zh-CN does not/
    },
    {
        id: 'M2',
        what: 'the translation drops the {n} interpolation (silent wrong sentence)',
        file: MESSAGES,
        from: '                "kit.pagination.page": "第 {n} 页",',
        to: '                "kit.pagination.page": "第 页",',
        expect: /"kit\.pagination\.page": en uses \[\{n\}\] but zh-CN uses \[\]/
    },
    {
        id: 'M3',
        what: 'the same key is declared twice in one locale (the second silently wins)',
        file: MESSAGES,
        from: '                "kit.select.label": "select",',
        to: '                "kit.select.label": "select",\n                "kit.select.label": "dropdown",',
        expect: /duplicate key "kit\.select\.label" in en\(\)/
    },
    {
        id: 'M4',
        what: 'a factory asks for a kit key that no catalog has (renamed key)',
        file: SELECT,
        from: 'I18n.t("kit.select.label")',
        to: 'I18n.t("kit.select.nom")',
        expect: /select\.as: "kit\.select\.nom" is not in the en catalog/
    }
];

let caught = 0;
const problems = [];
const lines = [];

for (const c of CASES) {
    const before = sha(c.file);
    const original = fs.readFileSync(c.file, 'utf8');
    if (original.indexOf(c.from) < 0) {
        problems.push(c.id + ': the anchor is not in ' + path.basename(c.file) + ' -- ' + JSON.stringify(c.from));
        lines.push(c.id + ' ANCHOR-MISSING  ' + c.what);
        continue;
    }
    fs.writeFileSync(c.file, original.replace(c.from, c.to));
    const r = spawnSync(process.execPath, [path.join(__dirname, 'i18n-check.cjs')], { cwd: UI, encoding: 'utf8' });
    const out = (r.stdout || '') + (r.stderr || '');
    // Restore BEFORE judging, so a bad case can never leave the tree dirty.
    fs.writeFileSync(c.file, original);
    const restored = sha(c.file) === before;

    const red = r.status !== 0;
    const right = c.expect.test(out);
    if (red && right && restored) {
        caught++;
        lines.push(c.id + ' CAUGHT  ' + c.what + '  [' + path.basename(c.file) + ']');
    } else {
        if (!red) problems.push(c.id + ': the checker stayed GREEN -- ' + c.what);
        else if (!right) problems.push(c.id + ': red, but for the wrong reason -- ' + c.what + '\n    '
            + out.split(/\r?\n/).filter((l) => /FAIL|RESULT|catalog:/.test(l)).slice(0, 4).join('\n    '));
        if (!restored) problems.push(c.id + ': RESTORE FAILED, ' + path.basename(c.file) + ' is not byte-identical');
        lines.push(c.id + ' MISSED  ' + c.what + '  [' + path.basename(c.file) + ']');
    }
    console.log(c.id + ' ' + (red && right ? 'CAUGHT' : 'MISSED') + ' -- ' + c.what
        + (restored ? ' (restored byte-identical)' : ' (RESTORE FAILED)'));
}

// The unmutated tree must be green, otherwise "caught" above means nothing.
const clean = spawnSync(process.execPath, [path.join(__dirname, 'i18n-check.cjs')], { cwd: UI, encoding: 'utf8' });
const cleanOk = clean.status === 0;
console.log('baseline: ' + (cleanOk ? 'PASS' : 'FAIL'));
if (!cleanOk) {
    problems.push('the restored tree does not pass i18n-check');
}

console.log('');
console.log('MUTATION i18n-check: ' + caught + '/' + CASES.length + ' caught, ' + problems.length + ' problem(s)');
for (const p of problems) console.log('  PROBLEM ' + p);
if (lines.length) console.log(lines.join('\n'));
console.log('RESULT: ' + (caught === CASES.length && problems.length === 0 ? 'PASS' : 'FAIL'));
process.exit(caught === CASES.length && problems.length === 0 ? 0 : 1);
