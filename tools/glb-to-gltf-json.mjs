// Converte todos os .glb de <origem> em glTF JSON com buffers embutidos
// (<destino>/<mesmo caminho>.gltf.json). Usado no build "artifact", cujo host
// não serve .glb; o GLTFLoader do three.js lê os dois formatos.
// Uso: node tools/glb-to-gltf-json.mjs public/models dist-artifact/models
import fs from 'node:fs';
import path from 'node:path';

const [src, dst] = process.argv.slice(2);
if (!src || !dst) { console.error('uso: glb-to-gltf-json.mjs <origem> <destino>'); process.exit(1); }

function convert(file) {
  const b = fs.readFileSync(file);
  if (b.readUInt32LE(0) !== 0x46546c67) throw new Error(`não é GLB: ${file}`);
  let off = 12, json = null, bin = null;
  while (off < b.length) {
    const len = b.readUInt32LE(off), type = b.readUInt32LE(off + 4);
    const chunk = b.subarray(off + 8, off + 8 + len);
    if (type === 0x4e4f534a) json = JSON.parse(chunk.toString('utf8'));
    else if (type === 0x004e4942) bin = chunk;
    off += 8 + len;
  }
  if (bin && json.buffers?.length) json.buffers[0].uri = 'data:application/octet-stream;base64,' + Buffer.from(bin).toString('base64');
  return JSON.stringify(json);
}

let n = 0;
for (const f of fs.readdirSync(src, { recursive: true })) {
  const full = path.join(src, f);
  if (!fs.statSync(full).isFile()) continue;
  const out = path.join(dst, f);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  if (f.endsWith('.glb')) {
    fs.writeFileSync(out.replace(/\.glb$/, '.gltf.json'), convert(full));
    const stale = out;
    if (fs.existsSync(stale)) fs.rmSync(stale);
    n++;
  } else fs.copyFileSync(full, out);
}
console.log(`${n} modelos convertidos para glTF JSON em ${dst}`);
