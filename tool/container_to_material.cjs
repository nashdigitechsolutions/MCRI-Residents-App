// Rewrites `Container(decoration: BoxDecoration(color: …, borderRadius: …,
// border: Border.all(…)), padding/margin/constraints…, child: …)` at given
// line numbers into an equivalent `Material(…)`, so ListTiles inside get a
// Material ancestor (no "ink splashes may be invisible" assertion) and
// show their tap ripple.
//
//   node tool/container_to_material.cjs <file.dart> <line> [<line>…]
const fs = require('fs');
const [file, ...lines] = process.argv.slice(2);
let src = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');

function matchParen(s, open) {
  let depth = 0, str = null;
  for (let i = open; i < s.length; i++) {
    const ch = s[i];
    if (str) {
      if (ch === '\\') { i++; continue; }
      if (ch === str) str = null;
      continue;
    }
    if (ch === "'" || ch === '"') { str = ch; continue; }
    if (ch === '(' || ch === '[' || ch === '{') depth++;
    else if (ch === ')' || ch === ']' || ch === '}') { depth--; if (depth === 0) return i; }
  }
  throw new Error('unbalanced');
}

function splitArgs(body) {
  const out = []; let depth = 0, str = null, cur = '';
  for (let i = 0; i < body.length; i++) {
    const ch = body[i];
    if (str) { cur += ch; if (ch === '\\') { cur += body[++i]; continue; } if (ch === str) str = null; continue; }
    if (ch === "'" || ch === '"') { str = ch; cur += ch; continue; }
    if ('([{'.includes(ch)) depth++;
    if (')]}'.includes(ch)) depth--;
    if (ch === ',' && depth === 0) { if (cur.trim()) out.push(cur.trim()); cur = ''; continue; }
    cur += ch;
  }
  if (cur.trim()) out.push(cur.trim());
  return out.map((a) => { const k = a.indexOf(':'); return [a.slice(0, k).trim(), a.slice(k + 1).trim()]; });
}

// Process bottom-up so earlier line numbers stay valid.
for (const ln of lines.map(Number).sort((a, b) => b - a)) {
  const lineStart = src.split('\n').slice(0, ln - 1).join('\n').length + (ln > 1 ? 1 : 0);
  const at = src.indexOf('Container(', lineStart);
  if (at < 0 || at > lineStart + 400) throw new Error(`no Container( near line ${ln}`);
  const open = at + 'Container'.length;
  const close = matchParen(src, open);
  const args = Object.fromEntries(splitArgs(src.slice(open + 1, close)));
  const deco = args.decoration;
  if (!deco || !deco.startsWith('BoxDecoration(')) throw new Error(`line ${ln}: no BoxDecoration`);
  const d = Object.fromEntries(splitArgs(deco.slice('BoxDecoration('.length, matchParen(deco, 'BoxDecoration'.length))));
  if (!d.color) throw new Error(`line ${ln}: decoration has no color`);
  const extra = Object.keys(d).filter((k) => !['color', 'borderRadius', 'border'].includes(k));
  if (extra.length) throw new Error(`line ${ln}: unsupported decoration keys ${extra}`);
  let side = null;
  if (d.border) {
    const m = d.border.match(/^Border\.all\(([\s\S]*)\)$/);
    if (!m) throw new Error(`line ${ln}: border is not Border.all`);
    side = `BorderSide(${m[1]})`;
  }
  const inner = ['padding', 'constraints', 'width', 'height', 'alignment'].filter((k) => args[k]);
  let child = args.child;
  if (inner.length) child = `Container(${inner.map((k) => `${k}: ${args[k]}`).join(', ')}, child: ${child},)`;
  const shape = d.borderRadius || side
    ? `shape: RoundedRectangleBorder(${d.borderRadius ? `borderRadius: ${d.borderRadius},` : ''}${side ? `side: ${side},` : ''}),`
    : '';
  let out = `Material(color: ${d.color}, ${shape} clipBehavior: Clip.antiAlias, child: ${child},)`;
  if (args.margin) out = `Padding(padding: ${args.margin}, child: ${out},)`;
  const unknown = Object.keys(args).filter((k) => !['decoration', 'child', 'margin', ...inner].includes(k));
  if (unknown.length) throw new Error(`line ${ln}: unsupported Container args ${unknown}`);
  src = src.slice(0, at) + out + src.slice(close + 1);
  console.log(`${file}:${ln} → Material`);
}
fs.writeFileSync(file, src);
