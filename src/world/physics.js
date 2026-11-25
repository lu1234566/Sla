// Física simples e determinística para um personagem cilíndrico contra
// colisores prismáticos verticais (polígono convexo no plano XZ + faixa em Y).
// Suficiente para um greybox: ilhas, degraus, pilares, plataformas móveis,
// portão e ponte líquida (colisores que ligam/desligam). Sem dependências.

export class PrismCollider {
  /**
   * @param {number[][]} poly vértices [x,z] em coordenadas locais (convexo)
   * @param {number} yMin base
   * @param {number} yMax topo (piso caminhável)
   * @param {object} opts {x,z,tags,name}
   */
  constructor(poly, yMin, yMax, opts = {}) {
    this.local = poly;
    this.x = opts.x || 0;
    this.z = opts.z || 0;
    this.yMin = yMin;
    this.yMax = yMax;
    this.enabled = opts.enabled !== false;
    this.tags = opts.tags || {}; // {safe, cover, water, area}
    this.name = opts.name || '';
    this.prevY = yMax;
    this.dy = 0; // deslocamento vertical no último quadro (plataformas móveis)
    this.dx = 0;
    this.dz = 0;
    this._rebuild();
  }

  _rebuild() {
    const pts = this.local.map(([x, z]) => [x + this.x, z + this.z]);
    // garante orientação consistente e calcula normais para fora
    let cx = 0, cz = 0;
    for (const p of pts) { cx += p[0]; cz += p[1]; }
    cx /= pts.length; cz /= pts.length;
    this.cx = cx; this.cz = cz;
    this.pts = pts;
    this.normals = pts.map((a, i) => {
      const b = pts[(i + 1) % pts.length];
      let nx = b[1] - a[1], nz = -(b[0] - a[0]);
      const len = Math.hypot(nx, nz) || 1;
      nx /= len; nz /= len;
      if ((cx - a[0]) * nx + (cz - a[1]) * nz > 0) { nx = -nx; nz = -nz; }
      return [nx, nz];
    });
    let r = 0;
    for (const p of pts) r = Math.max(r, Math.hypot(p[0] - cx, p[1] - cz));
    this.radius = r;
  }

  /** Move o colisor (registra o delta para carregar o personagem). */
  moveTo(x, yMax, z) {
    const h = this.yMax - this.yMin;
    this.dx += x - this.x;
    this.dz += z - this.z;
    this.dy += yMax - this.yMax;
    this.x = x; this.z = z;
    this.yMax = yMax; this.yMin = yMax - h;
    this._rebuild();
  }

  /**
   * Distância assinada do ponto ao polígono (negativa dentro) e o vetor de
   * empurrão unitário para fora.
   */
  signedDistance(px, pz) {
    const { pts, normals } = this;
    let maxD = -Infinity, maxI = 0;
    for (let i = 0; i < pts.length; i++) {
      const d = (px - pts[i][0]) * normals[i][0] + (pz - pts[i][1]) * normals[i][1];
      if (d > maxD) { maxD = d; maxI = i; }
    }
    if (maxD <= 0) return { d: maxD, nx: normals[maxI][0], nz: normals[maxI][1] };
    // fora: ponto mais próximo nas arestas
    let best = Infinity, bx = 0, bz = 0;
    for (let i = 0; i < pts.length; i++) {
      const a = pts[i], b = pts[(i + 1) % pts.length];
      const ex = b[0] - a[0], ez = b[1] - a[1];
      const t = Math.max(0, Math.min(1, ((px - a[0]) * ex + (pz - a[1]) * ez) / (ex * ex + ez * ez || 1)));
      const qx = a[0] + ex * t, qz = a[1] + ez * t;
      const dd = (px - qx) ** 2 + (pz - qz) ** 2;
      if (dd < best) { best = dd; bx = qx; bz = qz; }
    }
    const d = Math.sqrt(best) || 1e-6;
    return { d, nx: (px - bx) / d, nz: (pz - bz) / d };
  }
}

// --- Fábricas de formas -------------------------------------------------------

export function boxPoly(w, d, rot = 0) {
  const hw = w / 2, hd = d / 2;
  const c = Math.cos(rot), s = Math.sin(rot);
  return [[-hw, -hd], [hw, -hd], [hw, hd], [-hw, hd]].map(([x, z]) => [x * c + z * s, -x * s + z * c]);
}

export function ngonPoly(r, n, rot = 0) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const a = rot + (i / n) * Math.PI * 2;
    out.push([Math.cos(a) * r, Math.sin(a) * r]);
  }
  return out;
}

// --- Mundo físico -------------------------------------------------------------

export class PhysicsWorld {
  constructor() { this.colliders = []; }
  add(c) { this.colliders.push(c); return c; }
  remove(c) { this.colliders = this.colliders.filter((x) => x !== c); }
  /** Zera deltas de movimento (chamar uma vez por quadro, após o personagem). */
  endFrame() { for (const c of this.colliders) { c.dx = 0; c.dy = 0; c.dz = 0; } }

  /** Raio vertical para baixo: topo mais alto sob (x,z) abaixo de yFrom. */
  groundAt(x, z, yFrom = Infinity, filter = null) {
    let best = null;
    for (const c of this.colliders) {
      if (!c.enabled || (filter && !filter(c))) continue;
      if (c.yMax > yFrom) continue;
      if (Math.hypot(x - c.cx, z - c.cz) > c.radius + 0.01) continue;
      if (c.signedDistance(x, z).d <= 0 && (!best || c.yMax > best.yMax)) best = c;
    }
    return best;
  }
}

/** Personagem cilíndrico (posição = pés). */
export class CharacterBody {
  constructor({ radius = 0.32, height = 1.35, stepHeight = 0.45, ledgeAssist = 0.22 } = {}) {
    this.radius = radius;
    this.ledgeAssist = ledgeAssist;
    this.height = height;
    this.stepHeight = stepHeight;
    this.pos = { x: 0, y: 0, z: 0 };
    this.vel = { x: 0, y: 0, z: 0 };
    this.grounded = false;
    this.ground = null; // colisor sob os pés
    this.timeSinceGrounded = 0;
  }

  /**
   * Integra um passo. `gravity` negativo. Retorna eventos {landed, hitHead}.
   */
  step(world, dt, gravity, { snap = true } = {}) {
    const p = this.pos, v = this.vel;
    const r = this.radius;
    const ev = { landed: false, hitHead: false, impactSpeed: 0 };

    // carrega com a plataforma sob os pés
    if (this.grounded && this.ground) {
      p.x += this.ground.dx; p.z += this.ground.dz;
      if (this.ground.dy) p.y += this.ground.dy;
    }

    v.y += gravity * dt;
    p.x += v.x * dt;
    p.z += v.z * dt;

    // no chão sobe degraus; no ar há uma pequena tolerância de borda (ledge assist)
    const wasGrounded = this.grounded;
    const stepUp = wasGrounded ? this.stepHeight : this.ledgeAssist;

    // resolução horizontal
    for (let iter = 0; iter < 3; iter++) {
      let moved = false;
      for (const c of world.colliders) {
        if (!c.enabled) continue;
        if (c.yMax <= p.y + stepUp || c.yMin >= p.y + this.height) continue;
        if (Math.hypot(p.x - c.cx, p.z - c.cz) > c.radius + r) continue;
        const { d, nx, nz } = c.signedDistance(p.x, p.z);
        if (d < r) {
          const push = r - d;
          p.x += nx * push; p.z += nz * push;
          const vn = v.x * nx + v.z * nz;
          if (vn < 0) { v.x -= vn * nx; v.z -= vn * nz; }
          moved = true;
        }
      }
      if (!moved) break;
    }

    // vertical
    const prevY = p.y;
    p.y += v.y * dt;

    // teto
    if (v.y > 0) {
      for (const c of world.colliders) {
        if (!c.enabled) continue;
        if (c.yMin < prevY + this.height - 0.01 || c.yMin > p.y + this.height) continue;
        if (c.signedDistance(p.x, p.z).d < r * 0.5) { p.y = c.yMin - this.height; v.y = 0; ev.hitHead = true; break; }
      }
    }

    // chão: o topo mais alto sob o pé (com tolerância de borda) dentro do alcance de degrau
    const footR = r * 0.65;
    let best = null;
    const reachDown = wasGrounded && snap && v.y <= 0 ? 0.3 : 0;
    const top = Math.max(prevY, p.y) + stepUp;
    for (const c of world.colliders) {
      if (!c.enabled) continue;
      if (c.yMax > top) continue;
      if (c.yMax < p.y - reachDown - 0.001) continue;
      if (Math.hypot(p.x - c.cx, p.z - c.cz) > c.radius + footR) continue;
      if (c.signedDistance(p.x, p.z).d > footR) continue;
      if (!best || c.yMax > best.yMax) best = c;
    }
    if (best && v.y <= 0.001) {
      if (!wasGrounded) { ev.landed = true; ev.impactSpeed = -v.y; }
      p.y = best.yMax;
      v.y = 0;
      this.grounded = true;
      this.ground = best;
      this.timeSinceGrounded = 0;
    } else {
      this.grounded = false;
      this.ground = null;
      this.timeSinceGrounded += dt;
    }
    return ev;
  }

  /** O pé está inteiramente sobre o colisor (bom ponto de retorno)? */
  wellSupported() {
    if (!this.grounded || !this.ground) return false;
    return this.ground.signedDistance(this.pos.x, this.pos.z).d < -this.radius * 1.6;
  }
}
