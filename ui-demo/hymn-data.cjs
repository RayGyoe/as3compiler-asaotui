// hymn-data.cjs -- generate the two AS3 data units the hymn demo compiles in.
//
//   HymnData.as   1000 hymns: "<number>\t<TITLE AS PRINTED>\t<body>"
//   HymnTunes.as  239 tune descriptors: "<number>\t<length>\t<chorusAt|-1>\t<voices>"
//
// WHY A GENERATOR AND NOT A RUNTIME FILE: the app must start with the whole book
// in memory (search runs over every line of every hymn) and it must do so with no
// side files beside the executable, so the data is compiled in. One literal per
// hymn keeps the generated page readable and lets the AS3 side use split().
//
// The source is the hymnbook repository's own `data/hymns.ndjson` and
// `assets/tunes/index.json`. Point at a checkout with --src; the commit is
// recorded in the generated header, because "which hymns" is part of the result.
//
// Usage:
//   node ui-demo/hymn-data.cjs --src ../hymnbook-src/hymnbook
//   node ui-demo/hymn-data.cjs --src <repo> --out ui-demo/hymn-demo
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const here = __dirname;
let srcDir = path.resolve(here, '..', 'hymnbook-src', 'hymnbook');
// The app's own source tree: --air-app compiles the app dir's src/ and nothing else.
let outDir = path.join(here, 'hymn-demo', 'src');
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 1) {
  if (argv[i] === '--src') srcDir = path.resolve(argv[++i]);
  else if (argv[i] === '--out') outDir = path.resolve(argv[++i]);
  else {
    console.error('[hymn-data] unknown argument: ' + argv[i]);
    process.exit(2);
  }
}

const ndjson = path.join(srcDir, 'data', 'hymns.ndjson');
const tuneIndex = path.join(srcDir, 'assets', 'tunes', 'index.json');
for (const f of [ndjson, tuneIndex]) {
  if (!fs.existsSync(f)) {
    console.error('[hymn-data] missing ' + f + ' -- pass --src <hymnbook checkout>');
    process.exit(2);
  }
}

function commitOf(dir) {
  try {
    return execFileSync('git', ['-C', dir, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim();
  } catch (e) {
    return '(not a git checkout)';
  }
}

// AS3 string literal escaping. A raw newline inside a literal is a LexError in
// this compiler (measured), so the body's newlines travel as \n and are turned
// back into real ones by the AS3 side's split().
function esc(s) {
  let r = '';
  for (const ch of s) {
    switch (ch) {
      case '\\': r += '\\\\'; break;
      case '"': r += '\\"'; break;
      case '\n': r += '\\n'; break;
      case '\r': break;
      case '\t': r += '\\t'; break;
      default:
        if (ch < ' ') r += '\\u' + ch.charCodeAt(0).toString(16).padStart(4, '0');
        else r += ch;
    }
  }
  return r;
}

// ---------------------------------------------------------------- hymns
const raw = fs.readFileSync(ndjson, 'utf8').split('\n').filter((l) => l.trim() !== '');
const records = [];
let skipped = 0;
for (const l of raw) {
  let o;
  try { o = JSON.parse(l); } catch (e) { skipped += 1; continue; }
  if (o.hymn_no == null || o.hymn_title == null || o.body == null) { skipped += 1; continue; }
  records.push(o.hymn_no + '\t' + o.hymn_title + '\t' + o.body);
}

const commit = commitOf(srcDir);
const genHymn = '// HymnData.as -- GENERATED, do not edit.\n'
  + '//\n'
  + '// ' + records.length + ' hymns from the Hymn Book project, `data/hymns.ndjson`\n'
  + '// (hymnbook ' + commit + '; hymn texts MIT, see that repository\'s THIRD_PARTY.md).\n'
  + '// Regenerate: node ui-demo/hymn-data.cjs --src <hymnbook checkout>\n'
  + '//\n'
  + '// One literal per hymn: "<number>\\t<TITLE AS PRINTED>\\t<body>", the body keeping its\n'
  + '// own line breaks (escaped here, unescaped by the compiler). HymnBook.load does the\n'
  + '// splitting and the verse/chorus parsing; nothing here is pre-chewed.\n'
  + 'package hymn\n{\n    public final class HymnData\n    {\n'
  + '        public static const RAW:Array = [\n'
  + records.map((r) => '            "' + esc(r) + '"').join(',\n')
  + '\n        ];\n    }\n}\n';

// ---------------------------------------------------------------- tunes
const idx = JSON.parse(fs.readFileSync(tuneIndex, 'utf8'));
const tuneLines = [];
for (const k of Object.keys(idx)) {
  const t = idx[k];
  const n = parseInt(k, 10);
  if (!(n > 0) || !(t.length > 0)) continue;
  const chorusAt = (t.chorus_at == null) ? -1 : Number(t.chorus_at);
  const voices = Array.isArray(t.voices) ? t.voices.join(',') : '';
  tuneLines.push(n + '\t' + t.length + '\t' + chorusAt + '\t' + voices);
}
tuneLines.sort((a, b) => parseInt(a, 10) - parseInt(b, 10));

const genTune = '// HymnTunes.as -- GENERATED, do not edit.\n'
  + '//\n'
  + '// ' + tuneLines.length + ' of ' + records.length + ' hymns have a tune (hymnbook ' + commit + ').\n'
  + '// Regenerate: node ui-demo/hymn-data.cjs --src <hymnbook checkout>\n'
  + '//\n'
  + '// One literal per tune: "<number>\\t<length of one pass, s>\\t<chorus start, s or -1>\\t<voices>".\n'
  + '// `length`/`chorusAt` are what the ARRANGEMENT needs (verse, chorus, verse, chorus...);\n'
  + '// the notes themselves live in the MIDI files, which this demo does not compile in\n'
  + '// because it does not synthesise audio yet (see hymn/README.md).\n'
  + 'package hymn\n{\n    public final class HymnTunes\n    {\n'
  + '        public static const RAW:Array = [\n'
  + tuneLines.map((r) => '            "' + esc(r) + '"').join(',\n')
  + '\n        ];\n    }\n}\n';

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'HymnData.as'), genHymn);
fs.writeFileSync(path.join(outDir, 'HymnTunes.as'), genTune);

const kb = (f) => (fs.statSync(path.join(outDir, f)).size / 1024).toFixed(0) + ' KB';
console.log('[hymn-data] ' + records.length + ' hymns -> HymnData.as (' + kb('HymnData.as') + ')'
  + (skipped ? ', ' + skipped + ' malformed rows skipped' : ''));
console.log('[hymn-data] ' + tuneLines.length + ' tunes -> HymnTunes.as (' + kb('HymnTunes.as') + ')');
