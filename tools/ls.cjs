// asaotui/tools/ls.cjs -- list a directory tree with sizes and mtimes.
//
// WHY: this machine's bash has no coreutils (no `ls`, `find`, `grep`, `stat`), and
// writing the equivalent inline with `node -e` keeps tripping over backslash
// escaping in the shell. One tiny script removes both problems.
//
// Usage: node ls.cjs [dir] [--sort=mtime|size|name] [--maxdepth=N] [--ext=.as,.cjs]
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const dir = args.find((a) => !a.startsWith('--')) || '.';
const sortBy = (args.find((a) => a.startsWith('--sort=')) || '--sort=name').split('=')[1];
const maxDepth = Number((args.find((a) => a.startsWith('--maxdepth=')) || '--maxdepth=20').split('=')[1]);
const extFilter = (args.find((a) => a.startsWith('--ext=')) || '').split('=')[1];

const rows = [];
(function walk(d, depth) {
  if (depth > maxDepth) return;
  let ents;
  try { ents = fs.readdirSync(d); } catch (e) { return; }
  for (const f of ents) {
    const q = path.join(d, f);
    let st;
    try { st = fs.statSync(q); } catch (e) { continue; }
    if (st.isDirectory()) { rows.push({ q, dir: true, size: 0, mtime: st.mtime }); walk(q, depth + 1); }
    else rows.push({ q, dir: false, size: st.size, mtime: st.mtime });
  }
})(dir, 0);

let list = rows;
if (extFilter) {
  const exts = extFilter.split(',').map((s) => s.trim().toLowerCase());
  list = list.filter((r) => r.dir || exts.some((e) => r.q.toLowerCase().endsWith(e)));
}
if (sortBy === 'mtime') list.sort((a, b) => a.mtime - b.mtime);
else if (sortBy === 'size') list.sort((a, b) => b.size - a.size);
else list.sort((a, b) => a.q.localeCompare(b.q));

const files = list.filter((r) => !r.dir);
const total = files.reduce((s, r) => s + r.size, 0);
for (const r of list) {
  const q = r.q.split(path.sep).join('/');
  const t = r.mtime.toISOString().slice(11, 19);
  console.log(r.dir ? `${t}  <dir>             ${q}/` : `${t}  ${String(r.size).padStart(9)}  ${q}`);
}
console.log(`\n${files.length} files, ${total} bytes (${(total / 1024).toFixed(1)} KB)`);