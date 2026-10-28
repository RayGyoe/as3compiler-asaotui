// mobile-gap-scan.cjs -- the READ-ONLY evidence behind
// reviews/nsh-mobile-support-gap-2026-10-26.md: what the kit already has, what it
// has none of, and what the compiler/back-end cannot give it yet.
//
// WHY A TOOL AND NOT A PARAGRAPH
// -----------------------------
// The mobile question ("can asaotui run on iOS/Android?") turns on a handful of
// counts -- "0 files mention TouchEvent", "37 kinds but no navStack", "Target is
// 'native' | 'wasm'". Written in prose they become stale the first time a widget
// lands, and nobody re-derives them. This script re-derives them, so the review
// can be re-checked instead of believed.
//
// It NEVER writes and never runs the compiler: it reads kit/, ui-demo/, and the
// compiler's own sources (asaotui must not touch as3compiler, so this only LOOKS).
//
// Usage:   node tools/mobile-gap-scan.cjs [--json]
// Exit:    0 = measured, 2 = a source tree is missing / unreadable.
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const compiler = path.resolve(root, '..', 'as3compiler');
const json = process.argv.includes('--json');

function fail(msg) {
  console.error('mobile-gap-scan: ' + msg);
  process.exit(2);
}

function walk(dir, ext, out) {
  if (!fs.existsSync(dir)) fail('missing directory: ' + dir);
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { if (e.name !== 'skia') walk(p, ext, out); }
    else if (p.endsWith(ext)) out.push(p);
  }
  return out;
}

function count(hay, needle) { return hay.split(needle).length - 1; }

// ---- 1. kit inventory -------------------------------------------------------
const kitFiles = walk(path.join(root, 'kit'), '.as', []);
if (kitFiles.length === 0) fail('no .as files under kit/');

const src = new Map();
for (const f of kitFiles) src.set(f, fs.readFileSync(f, 'utf8'));

const kinds = new Set();
for (const s of src.values()) {
  for (const m of s.matchAll(/Widgets\.register\(\s*"([^"]+)"/g)) kinds.add(m[1]);
}
const kindList = [...kinds].sort();

const styleFile = path.join(root, 'kit', 'asaot', 'ui', 'style', 'Style.as');
if (!fs.existsSync(styleFile)) fail('missing Style.as');
const styleFields = [...fs.readFileSync(styleFile, 'utf8').matchAll(/public var (\w+):/g)].map((m) => m[1]);

// ---- 2. what is GONE (these are the mobile blockers) -------------------------
// Each entry: token, and why it matters. A hit count of 0 is the finding.
const absent = [
  ['TouchEvent', 'touch input class usage'], ['Multitouch', 'multi-finger state'],
  ['TouchPhase', 'touch phase use'], ['safeArea', 'safe-area inset consumer'],
  ['stageOrientation', 'device rotation'], ['Capabilities', 'screen/density facts'],
  ['pixelRatio', 'HiDPI ratio'], ['softKeyboard', 'soft-keyboard rectangle'],
  ['keyboardHeight', 'keyboard inset'], ['setSelection', 'programmatic text selection'],
  ['TextEvent', 'TEXT_INPUT event'], ['accessibility', 'a11y semantics consumer'],
  ['hover', 'hover-dependent styling'], ['tabBar', 'bottom tab navigation'],
  ['bottomSheet', 'sheet presentation'], ['navStack', 'navigation stack'],
  ['inertia', 'scroll momentum'], ['rubber', 'elastic overscroll'], ['pinch', 'pinch gesture'],
  // MOBILE.md §2/§5: the declarative press/hit contract. A 0 here means the
  // semantics NSH answers with a prop (and AIR answers with needsSoftKeyboard /
  // softKeyboardType) has no name in this kit at all.
  ['hitSlop', 'enlarged touch target'], ['pointerEvents', 'touch pass-through rule'],
  ['longPress', 'long-press semantics'], ['pressDelay', 'press-in delay inside scroll'],
  ['appBar', 'page header'], ['appState', 'foreground/background'],
  ['reduceMotion', 'motion preference'], ['screenReader', 'screen-reader state'],
];

const absentHits = {};
for (const [token] of absent) {
  let n = 0;
  for (const s of src.values()) n += count(s, token);
  absentHits[token] = n;
}

// ---- 3. how coupled to the MOUSE is the kit -------------------------------
let mouseFiles = 0;
let mouseRefs = 0;
for (const s of src.values()) {
  const n = count(s, 'MouseEvent');
  if (n) { mouseFiles++; mouseRefs += n; }
}

// ---- 4. scroll / list capability words ------------------------------------
const scrollFile = path.join(root, 'kit', 'asaot', 'ui', 'kind', 'ScrollViewWidget.as');
const vlistFile = path.join(root, 'kit', 'asaot', 'ui', 'kind', 'VirtualListWidget.as');
if (!fs.existsSync(scrollFile) || !fs.existsSync(vlistFile)) fail('missing scroll/list widget sources');
const scrollSrc = fs.readFileSync(scrollFile, 'utf8');
const vlistSrc = fs.readFileSync(vlistFile, 'utf8');
const listCaps = {
  // SELF-DECLARED, and that is the point: the widget's own header says what it
  // does not do, so a green probe cannot hide a missing feel. The word counts
  // below are mentions INSIDE that comment -- 0 in code.
  selfDeclaredMissing: /WHAT A SCROLLVIEW STILL DOES NOT DO/.test(scrollSrc) ? 'yes' : 'no',
  momentumMentions: count(scrollSrc, 'momentum') + count(scrollSrc, 'inertia'),
  elasticMentions: count(scrollSrc, 'elastic'),
  pagingMentions: count(scrollSrc, 'paging') + count(scrollSrc, 'snap'),
  touchDragWords: count(scrollSrc, 'touch') + count(scrollSrc, 'finger'),
  estimatedRowHeight: count(vlistSrc, 'estimated'),
  stickyHeader: count(vlistSrc, 'sticky'),
  onVisible: count(vlistSrc, 'onVisible'),
  scrollToIndex: count(vlistSrc, 'scrollToIndex'),
  virtualListLines: vlistSrc.split('\n').length,
};

// ---- 5. compiler / back-end facts (read-only) -----------------------------
const facts = { compilerFound: fs.existsSync(compiler) };
if (facts.compilerFound) {
  const buildTs = path.join(compiler, 'src', 'build.ts');
  const emitTs = path.join(compiler, 'src', 'emit.ts');
  const indexTs = path.join(compiler, 'src', 'index.ts');
  const windowCc = path.join(compiler, 'vendor', 'window_glue.cc');
  const webCc = path.join(compiler, 'vendor', 'web_glue.cc');
  for (const f of [buildTs, emitTs, indexTs, windowCc, webCc]) {
    if (!fs.existsSync(f)) fail('missing compiler source: ' + f);
  }
  const buildSrc = fs.readFileSync(buildTs, 'utf8');
  const emitSrc = fs.readFileSync(emitTs, 'utf8');
  const indexSrc = fs.readFileSync(indexTs, 'utf8');
  const windowSrc = fs.readFileSync(windowCc, 'utf8');
  const webSrc = fs.readFileSync(webCc, 'utf8');

  facts.targets = (buildSrc.match(/export type Target = ([^;]+);/) || [, '?'])[1].trim();
  facts.packages = (buildSrc.match(/export type Package = ([^;]+);/) || [, '?'])[1].trim();
  facts.androidProjectThrows = /android-project[\s\S]{0,200}not yet implemented/.test(indexSrc);
  facts.stageSoftKeyboardRect = count(emitSrc, 'softKeyboardRect');
  facts.stageOrientation = count(emitSrc, 'stageOrientation');
  facts.emitTouchEvent = count(emitSrc, 'TouchEvent');   // the CLASS exists ...
  facts.sdlFingerInGlue = count(windowSrc, 'SDL_FINGER'); // ... the INPUT does not
  facts.sdlStartTextInput = count(windowSrc, 'SDL_StartTextInput');
  facts.sdlSetTextInputRect = count(windowSrc, 'SDL_SetTextInputRect');
  facts.emitSetSelection = count(emitSrc, 'setSelection');
  facts.emitSoftKeyboardType = count(emitSrc, 'softKeyboardType');
  facts.emitReturnKeyLabel = count(emitSrc, 'returnKeyLabel');
  facts.emitNeedsSoftKeyboard = count(emitSrc, 'needsSoftKeyboard');
  facts.emitAutoOrients = count(emitSrc, 'autoOrients');
  facts.webTouchOrPointer = count(webSrc, 'touchstart') + count(webSrc, 'pointerdown');
  facts.webKeydown = count(webSrc, 'keydown');
  facts.webKeyCallbackDiscarded = /\(void\)on_key/.test(webSrc);

  const libDirs = (p) => (fs.existsSync(p) ? fs.readdirSync(p).sort() : []);
  facts.skiaPlatforms = libDirs(path.join(compiler, 'vendor', 'skia', 'lib'));
  facts.sdlPlatforms = libDirs(path.join(compiler, 'vendor', 'sdl2', 'lib'));
}

// ---- report ---------------------------------------------------------------
if (json) {
  console.log(JSON.stringify({
    kitFiles: kitFiles.length, kinds: kindList, styleFields: styleFields.length,
    absentHits, mouse: { files: mouseFiles, refs: mouseRefs }, listCaps, facts,
  }, null, 2));
  process.exit(0);
}

const line = (k, v) => console.log('  ' + String(k).padEnd(34) + v);

console.log('== kit ==');
line('files', kitFiles.length);
line('kinds registered', kinds.size + '  (' + kindList.join(' ') + ')');
line('Style fields', styleFields.length);
line('mouse coupling', mouseFiles + ' of ' + kitFiles.length + ' files, ' + mouseRefs + ' refs');

console.log('\n== mobile tokens (0 = the blocker) ==');
for (const [token, why] of absent) {
  line(token, String(absentHits[token]).padStart(3) + '   ' + why);
}

console.log('\n== scroll / list ==');
for (const [k, v] of Object.entries(listCaps)) line(k, v);

if (facts.compilerFound) {
  console.log('\n== compiler (read-only) ==');
  line('Target', facts.targets);
  line('Package', facts.packages);
  line('android-project throws', facts.androidProjectThrows ? 'yes' : 'no');
  line('emit TouchEvent (class)', facts.emitTouchEvent);
  line('glue SDL_FINGER (input)', facts.sdlFingerInGlue);
  line('Stage.softKeyboardRect', facts.stageSoftKeyboardRect);
  line('Stage.stageOrientation', facts.stageOrientation);
  line('emit setSelection', facts.emitSetSelection);
  line('emit softKeyboardType', facts.emitSoftKeyboardType);
  line('emit returnKeyLabel', facts.emitReturnKeyLabel);
  line('emit needsSoftKeyboard', facts.emitNeedsSoftKeyboard);
  line('emit autoOrients', facts.emitAutoOrients);
  line('glue SDL_StartTextInput', facts.sdlStartTextInput);
  line('glue SDL_SetTextInputRect', facts.sdlSetTextInputRect);
  line('web touch/pointer handlers', facts.webTouchOrPointer);
  line('web keydown handlers', facts.webKeydown + (facts.webKeyCallbackDiscarded ? '  (on_key discarded)' : ''));
  line('skia prebuilt platforms', facts.skiaPlatforms.join(' ') || '(none)');
  line('sdl  prebuilt platforms', facts.sdlPlatforms.join(' ') || '(none)');
} else {
  console.log('\n== compiler ==  not found next to this worktree; back-end counts skipped');
}
