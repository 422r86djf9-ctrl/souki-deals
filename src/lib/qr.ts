// Générateur de QR code sans internet (versions 1 à 4, correction M), d'après la norme ISO/IEC 18004.
// Assez pour « SOUKIDEALS:SHOP:ABCD2345 » et les codes des bons. Sortie : matrice ou SVG.

const ALNUM = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';

// Correction M : [mots de correction par bloc, tailles des blocs de données]
const VERSIONS: { ec: number; blocks: number[] }[] = [
  { ec: 10, blocks: [16] },
  { ec: 16, blocks: [28] },
  { ec: 26, blocks: [44] },
  { ec: 18, blocks: [32, 32] },
];

function gfMul(x: number, y: number): number {
  let z = 0;
  for (let i = 7; i >= 0; i--) {
    z = (z << 1) ^ ((z >>> 7) * 0x11d);
    z ^= ((y >>> i) & 1) * x;
  }
  return z & 0xff;
}

function rsDivisor(degree: number): number[] {
  const r = new Array<number>(degree).fill(0);
  r[degree - 1] = 1;
  let root = 1;
  for (let i = 0; i < degree; i++) {
    for (let j = 0; j < r.length; j++) {
      r[j] = gfMul(r[j], root);
      if (j + 1 < r.length) r[j] ^= r[j + 1];
    }
    root = gfMul(root, 0x02);
  }
  return r;
}

function rsRemainder(data: number[], divisor: number[]): number[] {
  const r = divisor.map(() => 0);
  for (const b of data) {
    const factor = b ^ (r.shift() as number);
    r.push(0);
    divisor.forEach((coef, i) => {
      r[i] ^= gfMul(coef, factor);
    });
  }
  return r;
}

function utf8(text: string): number[] {
  const out: number[] = [];
  for (const ch of text) {
    let c = ch.codePointAt(0) as number;
    if (c < 0x80) out.push(c);
    else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
    else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    else {
      c -= 0;
      out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    }
  }
  return out;
}

// Bits des données (mode alphanumérique si possible, sinon octets)
function dataBits(text: string): number[] {
  const bits: number[] = [];
  const put = (v: number, n: number) => {
    for (let i = n - 1; i >= 0; i--) bits.push((v >>> i) & 1);
  };
  if ([...text].every((c) => ALNUM.includes(c))) {
    put(0b0010, 4);
    put(text.length, 9);
    for (let i = 0; i + 1 < text.length; i += 2) put(ALNUM.indexOf(text[i]) * 45 + ALNUM.indexOf(text[i + 1]), 11);
    if (text.length % 2) put(ALNUM.indexOf(text[text.length - 1]), 6);
  } else {
    const bytes = utf8(text);
    put(0b0100, 4);
    put(bytes.length, 8);
    bytes.forEach((b) => put(b, 8));
  }
  return bits;
}

function codewords(text: string): { version: number; data: number[] } {
  const bits = dataBits(text);
  for (let v = 1; v <= VERSIONS.length; v++) {
    const info = VERSIONS[v - 1];
    const capacity = info.blocks.reduce((a, b) => a + b, 0);
    if (bits.length > capacity * 8) continue;
    const b = [...bits];
    for (let i = 0; i < 4 && b.length < capacity * 8; i++) b.push(0);
    while (b.length % 8) b.push(0);
    const bytes: number[] = [];
    for (let i = 0; i < b.length; i += 8) bytes.push(parseInt(b.slice(i, i + 8).join(''), 2));
    for (let pad = 0xec; bytes.length < capacity; pad ^= 0xec ^ 0x11) bytes.push(pad);
    // Blocs, correction d'erreurs, puis entrelacement
    const divisor = rsDivisor(info.ec);
    const blocks: number[][] = [];
    const ecs: number[][] = [];
    let k = 0;
    for (const size of info.blocks) {
      const d = bytes.slice(k, k + size);
      k += size;
      blocks.push(d);
      ecs.push(rsRemainder(d, divisor));
    }
    const out: number[] = [];
    const maxLen = Math.max(...info.blocks);
    for (let i = 0; i < maxLen; i++) blocks.forEach((bl) => i < bl.length && out.push(bl[i]));
    for (let i = 0; i < info.ec; i++) ecs.forEach((e) => out.push(e[i]));
    return { version: v, data: out };
  }
  throw new Error('Texte trop long pour le QR code');
}

const MASKS: ((x: number, y: number) => boolean)[] = [
  (x, y) => (x + y) % 2 === 0,
  (_x, y) => y % 2 === 0,
  (x) => x % 3 === 0,
  (x, y) => (x + y) % 3 === 0,
  (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
  (x, y) => ((x * y) % 2) + ((x * y) % 3) === 0,
  (x, y) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0,
  (x, y) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0,
];

function build(version: number, data: number[], mask: number): boolean[][] {
  const size = version * 4 + 17;
  const m: boolean[][] = Array.from({ length: size }, () => new Array<boolean>(size).fill(false));
  const fn: boolean[][] = Array.from({ length: size }, () => new Array<boolean>(size).fill(false));
  const set = (x: number, y: number, dark: boolean) => {
    m[y][x] = dark;
    fn[y][x] = true;
  };
  // Lignes de synchronisation
  for (let i = 0; i < size; i++) {
    set(6, i, i % 2 === 0);
    set(i, 6, i % 2 === 0);
  }
  // Repères des trois coins
  for (const [cx, cy] of [
    [3, 3],
    [size - 4, 3],
    [3, size - 4],
  ]) {
    for (let dy = -4; dy <= 4; dy++)
      for (let dx = -4; dx <= 4; dx++) {
        const x = cx + dx;
        const y = cy + dy;
        if (x >= 0 && x < size && y >= 0 && y < size) {
          const d = Math.max(Math.abs(dx), Math.abs(dy));
          set(x, y, d !== 2 && d !== 4);
        }
      }
  }
  // Repère d'alignement (versions 2 à 4)
  if (version >= 2) {
    const a = version * 4 + 10;
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) set(a + dx, a + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
  }
  // Informations de format (correction M = 00) et module sombre
  const fmt = (() => {
    const d = (0 << 3) | mask;
    let rem = d;
    for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
    return ((d << 10) | rem) ^ 0x5412;
  })();
  const bit = (i: number) => ((fmt >>> i) & 1) === 1;
  for (let i = 0; i <= 5; i++) set(8, i, bit(i));
  set(8, 7, bit(6));
  set(8, 8, bit(7));
  set(7, 8, bit(8));
  for (let i = 9; i < 15; i++) set(14 - i, 8, bit(i));
  for (let i = 0; i < 8; i++) set(size - 1 - i, 8, bit(i));
  for (let i = 8; i < 15; i++) set(8, size - 15 + i, bit(i));
  set(8, size - 8, true);
  // Données en zigzag, avec le masque
  let i = 0;
  for (let right = size - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5;
    for (let vert = 0; vert < size; vert++) {
      for (let j = 0; j < 2; j++) {
        const x = right - j;
        const upward = ((right + 1) & 2) === 0;
        const y = upward ? size - 1 - vert : vert;
        if (!fn[y][x]) {
          const dark = i < data.length * 8 ? ((data[i >>> 3] >>> (7 - (i & 7))) & 1) === 1 : false;
          m[y][x] = dark !== MASKS[mask](x, y);
          i++;
        }
      }
    }
  }
  return m;
}

// Pénalités de la norme : on garde le masque le plus lisible
function penalty(m: boolean[][]): number {
  const n = m.length;
  let p = 0;
  const lines: boolean[][] = [];
  for (let y = 0; y < n; y++) lines.push(m[y]);
  for (let x = 0; x < n; x++) lines.push(m.map((r) => r[x]));
  const f1 = [true, false, true, true, true, false, true, false, false, false, false].join();
  const f2 = [false, false, false, false, true, false, true, true, true, false, true].join();
  for (const l of lines) {
    let run = 1;
    for (let i = 1; i <= n; i++) {
      if (i < n && l[i] === l[i - 1]) run++;
      else {
        if (run >= 5) p += 3 + (run - 5);
        run = 1;
      }
    }
    for (let i = 0; i + 11 <= n; i++) {
      const s = l.slice(i, i + 11).join();
      if (s === f1 || s === f2) p += 40;
    }
  }
  let dark = 0;
  for (let y = 0; y < n; y++)
    for (let x = 0; x < n; x++) {
      if (m[y][x]) dark++;
      if (x < n - 1 && y < n - 1 && m[y][x] === m[y][x + 1] && m[y][x] === m[y + 1][x] && m[y][x] === m[y + 1][x + 1]) p += 3;
    }
  p += Math.floor(Math.abs(dark * 20 - n * n * 10) / (n * n)) * 10;
  return p;
}

export function qrMatrix(text: string): boolean[][] {
  const { version, data } = codewords(text);
  let best: boolean[][] | null = null;
  let bestP = Infinity;
  for (let mask = 0; mask < 8; mask++) {
    const m = build(version, data, mask);
    const p = penalty(m);
    if (p < bestP) {
      bestP = p;
      best = m;
    }
  }
  return best as boolean[][];
}

// SVG carré de « px » pixels, avec la marge blanche obligatoire de 4 modules
export function qrSvg(text: string, px: number, color = '#1a1a1f'): string {
  const m = qrMatrix(text);
  const n = m.length + 8;
  let path = '';
  m.forEach((row, y) =>
    row.forEach((dark, x) => {
      if (dark) path += `M${x + 4} ${y + 4}h1v1h-1z`;
    }),
  );
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}" viewBox="0 0 ${n} ${n}" shape-rendering="crispEdges"><rect width="${n}" height="${n}" fill="#fff"/><path d="${path}" fill="${color}"/></svg>`;
}
