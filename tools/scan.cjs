// tools/scan.cjs -- count literal occurrences of terms in a file, and print a
// slice around one anchor. Zero deps; used because this box's bash has no grep.
//   node scan.cjs <file> <term> [term...]
//   node scan.cjs <file> --at <anchor> [len]
const fs = require('fs');
const [file, ...rest] = process.argv.slice(2);
const src = fs.readFileSync(file, 'utf8');
if (rest[0] === '--at') {
  const anchor = rest[1];
  const len = Number(rest[2] || 2000);
  const i = src.indexOf(anchor);
  if (i < 0) { console.log('anchor not found: ' + anchor); process.exit(1); }
  console.log('=== ' + file + ' @ ' + i + ' ===');
  console.log(src.slice(Math.max(0, i - 300), i + len));
} else {
  for (const t of rest) {
    let n = 0, i = -1;
    while ((i = src.indexOf(t, i + 1)) >= 0) n++;
    console.log(String(n).padStart(5), t);
  }
}