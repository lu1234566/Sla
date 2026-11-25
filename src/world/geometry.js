// Geometria 2D auxiliar para colisores (recorte, casco convexo, polígonos).

/** Octógono com arestas alinhadas aos eixos (apótema = r·cos 22,5°). */
export function octagon(r, cx = 0, cz = 0) {
  const out = [];
  for (let i = 0; i < 8; i++) {
    const a = Math.PI / 8 + (i / 8) * Math.PI * 2;
    out.push([cx + Math.cos(a) * r, cz + Math.sin(a) * r]);
  }
  return out;
}

export function ngon(r, n, cx = 0, cz = 0, rot = 0) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const a = rot + (i / n) * Math.PI * 2;
    out.push([cx + Math.cos(a) * r, cz + Math.sin(a) * r]);
  }
  return out;
}

export function rect(x0, z0, x1, z1) {
  return [[x0, z0], [x1, z0], [x1, z1], [x0, z1]];
}

/** Sutherland–Hodgman: mantém a parte do polígono com nx·x + nz·z <= d. */
export function clipPoly(poly, nx, nz, d) {
  const out = [];
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i], b = poly[(i + 1) % poly.length];
    const da = nx * a[0] + nz * a[1] - d;
    const db = nx * b[0] + nz * b[1] - d;
    if (da <= 0) out.push(a);
    if ((da < 0 && db > 0) || (da > 0 && db < 0)) {
      const t = da / (da - db);
      out.push([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]);
    }
  }
  return out;
}

/** Polígono convexo menos um retângulo alinhado -> até 4 peças convexas. */
export function subtractRect(poly, x0, z0, x1, z1) {
  const pieces = [];
  pieces.push(clipPoly(poly, 0, 1, z0)); // norte (z <= z0)
  pieces.push(clipPoly(poly, 0, -1, -z1)); // sul (z >= z1)
  let mid = clipPoly(clipPoly(poly, 0, -1, -z0), 0, 1, z1);
  pieces.push(clipPoly(mid, 1, 0, x0)); // oeste
  pieces.push(clipPoly(mid, -1, 0, -x1)); // leste
  return pieces.filter((p) => p.length >= 3);
}

/** Anel entre dois polígonos de mesma contagem/orientação -> trapézios convexos. */
export function ringPieces(outer, inner) {
  return outer.map((o, i) => {
    const j = (i + 1) % outer.length;
    return [o, outer[j], inner[j], inner[i]];
  });
}

/** Casco convexo (monotone chain) de pontos [x,z]. */
export function hull2D(points) {
  const pts = [...points].sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  if (pts.length < 3) return pts;
  const cross = (o, a, b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  const lower = [];
  for (const p of pts) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) lower.pop();
    lower.push(p);
  }
  const upper = [];
  for (let i = pts.length - 1; i >= 0; i--) {
    const p = pts[i];
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) upper.pop();
    upper.push(p);
  }
  upper.pop(); lower.pop();
  return lower.concat(upper);
}

/** Ponto dentro de polígono convexo. */
export function insideConvex(poly, x, z) {
  let sign = 0;
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i], b = poly[(i + 1) % poly.length];
    const c = (b[0] - a[0]) * (z - a[1]) - (b[1] - a[1]) * (x - a[0]);
    if (Math.abs(c) < 1e-9) continue;
    const s = Math.sign(c);
    if (!sign) sign = s;
    else if (s !== sign) return false;
  }
  return true;
}

export function translatePoly(poly, dx, dz) { return poly.map(([x, z]) => [x + dx, z + dz]); }
