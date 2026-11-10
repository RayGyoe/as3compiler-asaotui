// hymn-data.cjs -- generate the three AS3 data units the hymn demo compiles in.
//
//   HymnData.as   1000 hymns: "<number>\t<TITLE AS PRINTED>\t<body>"
//   HymnTunes.as  239 tune descriptors: "<number>\t<length>\t<chorusAt|-1>\t<voices>"
//   HymnNotes.as  239 tunes' notes: "<number>\t<v0>\t<v1>\t<v2>\t<v3>",
//                 each voice "start,dur,key;..." in centiseconds (one MIDI track per voice)
//
// WHY A GENERATOR AND NOT A RUNTIME FILE: the app must start with the whole book
// in memory (search runs over every line of every hymn) and it must do so with no
// side files beside the executable, so the data is compiled in. One literal per
// hymn keeps the generated page readable and lets the AS3 side use split().
//
// The source is the hymnbook repository's own `data/hymns.ndjson`,
// `assets/tunes/index.json` and `assets/tunes/NNNN.mid`. Point at a checkout with
// --src; the commit is recorded in the generated header, because "which hymns" is
// part of the result.
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

// ---------------------------------------------------------------- notes
// The notes come FIRST, because they decide two things the tune table needs: how long
// one pass really is, and (below) whether the metadata agrees. Each voice is
// "start,dur,key;..." in centiseconds.
const idx = JSON.parse(fs.readFileSync(tuneIndex, 'utf8'));
const noteLines = [];
const noteEnd = new Map();   // hymn number -> end of its last note, in seconds
for (const k of Object.keys(idx)) {
  const n = parseInt(k, 10);
  const mid = path.join(srcDir, 'assets', 'tunes', String(n).padStart(4, '0') + '.mid');
  if (!(n > 0) || !fs.existsSync(mid)) continue;
  let voices;
  try { voices = parseMidi(mid); } catch (e) { console.warn('[hymn-data] ' + e.message); continue; }
  while (voices.length < 4) voices.push('');
  noteLines.push([n].concat(voices.slice(0, 4)).join('\t'));
  let end = 0;
  for (const v of voices.slice(0, 4)) {
    if (!v) continue;
    for (const span of v.split(';')) {
      const q = span.split(',');
      if (q.length !== 3) continue;
      const e = (Number(q[0]) + Number(q[1])) / 100;
      if (e > end) end = e;
    }
  }
  noteEnd.set(n, end);
}
noteLines.sort((a, b) => parseInt(a, 10) - parseInt(b, 10));

// ---------------------------------------------------------------- tunes
const tuneLines = [];
// abc2mid.py writes `length` as the VERSE part when a hymn has `verse_lines` but no
// "Chorus:" label in its lyrics (tools/abc2mid.py: `quarters = float(phrase_start)`),
// while the MIDI file it emits still holds every phrase. One tune in the corpus hits
// that branch (631: 17.455 s of metadata, 28.35 s of music). Upstream then advances its
// section map on the shorter number while the notes keep sounding; this port takes the
// MIDI's own end instead, so the clock and the sound agree, and says which tune it
// changed rather than silently rewriting the corpus.
const adjusted = [];
for (const k of Object.keys(idx)) {
  const t = idx[k];
  const n = parseInt(k, 10);
  if (!(n > 0) || !(t.length > 0)) continue;
  let len = Number(t.length);
  const end = noteEnd.get(n);
  if (end != null && end > len + 0.05) {
    adjusted.push(n + ' (' + len.toFixed(2) + 's -> ' + end.toFixed(2) + 's)');
    len = Math.round(end * 1000) / 1000;
  }
  const chorusAt = (t.chorus_at == null) ? -1 : Number(t.chorus_at);
  const voices = Array.isArray(t.voices) ? t.voices.join(',') : '';
  tuneLines.push(n + '\t' + len + '\t' + chorusAt + '\t' + voices);
}
tuneLines.sort((a, b) => parseInt(a, 10) - parseInt(b, 10));

const genTune = '// HymnTunes.as -- GENERATED, do not edit.\n'
  + '//\n'
  + '// ' + tuneLines.length + ' of ' + records.length + ' hymns have a tune (hymnbook ' + commit + ').\n'
  + '// Regenerate: node ui-demo/hymn-data.cjs --src <hymnbook checkout>\n'
  + '//\n'
  + '// One literal per tune: "<number>\\t<length of one pass, s>\\t<chorus start, s or -1>\\t<voices>".\n'
  + (adjusted.length ? '// Length raised to the MIDI\'s own end for: ' + adjusted.join(', ') + '\n' : '')
  + '// `length`/`chorusAt` are what the ARRANGEMENT needs (verse, chorus, verse, chorus...).\n'
  + '// The notes are in HymnNotes.as, generated from the same tunes\' MIDI files.\n'
  + 'package hymn\n{\n    public final class HymnTunes\n    {\n'
  + '        public static const RAW:Array = [\n'
  + tuneLines.map((r) => '            "' + esc(r) + '"').join(',\n')
  + '\n        ];\n    }\n}\n';

// ---------------------------------------------------------------- notes
// A tune file holds ONE pass of the music, one MIDI track per voice
// (Soprano/Alto/Tenor/Bass, GM program 19 = church organ, every note velocity 80
// in this corpus). The demo synthesises that pass itself -- no sampler, no SF2 --
// so what it needs is plain note numbers, not the byte stream.
//
// This is hymnbook's `audio/midi.rs::parse_notes` reimplemented (tempo map across
// all tracks, one voice per track that actually has notes, notes still open at the
// end of a track closed 0.5 s later), then frozen into milliseconds so the AS3 side
// has no tempo arithmetic to get wrong.
function vlq(b, s) {
  let v = 0;
  let c;
  do { c = b[s.p]; s.p += 1; v = (v << 7) | (c & 0x7f); } while (c & 0x80);
  return v;
}

function parseMidi(file) {
  const b = fs.readFileSync(file);
  if (b.toString('ascii', 0, 4) !== 'MThd') throw new Error('not a MIDI file: ' + file);
  const fmt = b.readUInt16BE(8);
  const tracks = b.readUInt16BE(10);
  const tpq = b.readUInt16BE(12);
  if (b.readUInt32BE(4) !== 6) throw new Error('unexpected MThd length in ' + file);
  let p = 8 + 6;
  const spans = [];   // { track, startTick, endTick, key }
  const tempos = [[0, 500000]];
  for (let t = 0; t < tracks; t += 1) {
    if (b.toString('ascii', p, p + 4) !== 'MTrk') throw new Error('missing MTrk in ' + file);
    const len = b.readUInt32BE(p + 4);
    const end = p + 8 + len;
    const s = { p: p + 8 };
    let tick = 0;
    let rs = null;
    const open = [];   // { key, start }
    while (s.p < end) {
      tick += vlq(b, s);
      const st = b[s.p];
      if (st === 0xff) {
        s.p += 1;
        const ty = b[s.p];
        s.p += 1;
        const l = vlq(b, s);
        if (ty === 0x51) tempos.push([tick, (b[s.p] << 16) | (b[s.p + 1] << 8) | b[s.p + 2]]);
        s.p += l;
        continue;
      }
      if (st === 0xf0 || st === 0xf7) { s.p += 1; s.p += vlq(b, s); continue; }
      let status = st;
      if (st & 0x80) { rs = st; s.p += 1; } else status = rs;
      const hi = status & 0xf0;
      if (hi === 0x90 || hi === 0x80) {
        const key = b[s.p];
        const vel = b[s.p + 1];
        s.p += 2;
        if (hi === 0x90 && vel > 0) open.push({ key, start: tick });
        else {
          const i = open.findIndex((o) => o.key === key);
          if (i >= 0) { const o = open.splice(i, 1)[0]; spans.push({ track: t, start: o.start, end: tick, key: o.key }); }
        }
      } else if (hi === 0xc0) s.p += 1;
      else if (hi === 0xd0) s.p += 1;
      else s.p += 2;
    }
    for (const o of open) spans.push({ track: t, start: o.start, end: o.start + tpq / 2, key: o.key });
    p = end;
  }
  if (fmt === 2) throw new Error('format 2 timing in ' + file);
  tempos.sort((a, c) => a[0] - c[0]);
  const secs = (tick) => {
    let acc = 0;
    let last = 0;
    let us = 500000;
    for (const [at, per] of tempos) {
      if (at >= tick) break;
      acc += ((at - last) * us) / tpq / 1e6;
      last = at;
      us = per;
    }
    return acc + ((tick - last) * us) / tpq / 1e6;
  };
  // Voice index = order of tracks that actually hold notes, exactly like
  // parse_notes; a track with no notes is not a voice.
  const trackVoice = new Map();
  const perVoice = [];
  for (const s of spans) {
    if (!trackVoice.has(s.track)) { trackVoice.set(s.track, perVoice.length); perVoice.push([]); }
    const v = trackVoice.get(s.track);
    // Centiseconds: the corpus' notes all land on 10 ms boundaries in practice and a
    // tenth of that on an organ onset is below anything audible, while it takes a
    // third off the generated text.
    perVoice[v].push([Math.round(secs(s.start) * 100), Math.round(secs(s.end) * 100), s.key]);
  }
  return perVoice.map((list) => list
    .sort((a, c) => a[0] - c[0] || a[2] - c[2])
    .map(([a, z, k]) => a + ',' + Math.max(1, z - a) + ',' + k)
    .join(';'));
}

const genNotes = '// HymnNotes.as -- GENERATED, do not edit.\n'
  + '//\n'
  + '// The notes of ' + noteLines.length + ' tunes, from their MIDI files (hymnbook ' + commit + ').\n'
  + '// Regenerate: node ui-demo/hymn-data.cjs --src <hymnbook checkout>\n'
  + '//\n'
  + '// One literal per tune: "<number>\\t<v0>\\t<v1>\\t<v2>\\t<v3>", where a voice is\n'
  + '// "start,dur,key;..." in CENTISECONDS (MIDI key 69 = A4 = 440 Hz); an absent voice is empty.\n'
  + '// Milliseconds rather than ticks: the tempo map is applied once, here, so the\n'
  + '// synthesiser has no tempo arithmetic to get wrong.\n'
  + 'package hymn\n{\n    public final class HymnNotes\n    {\n'
  + '        public static const RAW:Array = [\n'
  + noteLines.map((r) => '            "' + esc(r) + '"').join(',\n')
  + '\n        ];\n    }\n}\n';

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'HymnData.as'), genHymn);
fs.writeFileSync(path.join(outDir, 'HymnTunes.as'), genTune);
fs.writeFileSync(path.join(outDir, 'HymnNotes.as'), genNotes);

const kb = (f) => (fs.statSync(path.join(outDir, f)).size / 1024).toFixed(0) + ' KB';
console.log('[hymn-data] ' + records.length + ' hymns -> HymnData.as (' + kb('HymnData.as') + ')'
  + (skipped ? ', ' + skipped + ' malformed rows skipped' : ''));
console.log('[hymn-data] ' + tuneLines.length + ' tunes -> HymnTunes.as (' + kb('HymnTunes.as') + ')');
console.log('[hymn-data] ' + noteLines.length + ' note tables -> HymnNotes.as (' + kb('HymnNotes.as') + ')');
