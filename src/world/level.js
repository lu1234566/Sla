// Jardim Mineral — setor da fatia vertical (GDD 12).
// Roteiro: chegada (Farol Nulo) → cisterna (nó, maré baixa, condutor) →
// ponte líquida (maré alta) → praça do guardião (placas, relé com Lume) →
// santuário (eco, atalho, descanso/save).
import * as THREE from 'three';
import { PrismCollider } from './physics.js';
import { octagon, ngon, rect, subtractRect, ringPieces, hull2D, insideConvex, translatePoly } from './geometry.js';
import { buildIsland, waterMaterial, mulberry } from './visuals.js';
import { mat, glowMat, PALETTE } from '../core/palette.js';
import { AREAS } from '../systems/PuzzleGraph.js';

export const LAYOUT = {
  A: { x: 0, z: 36, r: 7.5 },
  B: { x: 0, z: 14, r: 10, hole: [-3, 11, 3, 17], floorY: -3.5, depth: 4.4 },
  C: { x: 0, z: -16, r: 14, plazaR: 8.5, floorY: -2.2, depth: 3.0 },
  D: { scale: 2.4, top: 3.3, z: -40.5 },
};
const { A, B, C, D } = LAYOUT;
const V = (x, y, z) => new THREE.Vector3(x, y, z);

/** Centraliza a geometria de uma peça no próprio centro (para girar no lugar). */
function repivot(mesh) {
  mesh.geometry = mesh.geometry.clone();
  mesh.geometry.computeBoundingBox();
  const c = mesh.geometry.boundingBox.getCenter(new THREE.Vector3());
  mesh.geometry.translate(-c.x, -c.y, -c.z);
  mesh.position.add(c);
  mesh.updateMatrixWorld(true);
}
const lerp = (a, b, t) => a + (b - a) * t;

export class Level {
  constructor(assets, physics) {
    this.assets = assets;
    this.physics = physics;
    this.group = new THREE.Group();
    this.group.name = 'JardimMineral';
    this.cameraBlockers = [];
    this.scannables = [];
    this.nodes = [];
    this.plates = [];
    this.echoes = [];
    this.hazards = [];
    this.animated = [];
    this.rnd = mulberry(2026);
    this.time = 0;

    this.buildArrival();
    this.buildCistern();
    this.buildBridges();
    this.buildGarden();
    this.buildSanctuary();
    this.buildEchoes();
  }

  // --- utilidades ----------------------------------------------------------------

  collider(poly, yMin, yMax, tags = {}, opts = {}) {
    return this.physics.add(new PrismCollider(poly, yMin, yMax, { tags, ...opts }));
  }

  /** Laje com topo e lados (visual + colisor). poly em coordenadas do mundo. */
  slab(poly, yTop, yBottom, o = {}) {
    let cx = 0, cz = 0;
    for (const [x, z] of poly) { cx += x; cz += z; }
    cx /= poly.length; cz /= poly.length;
    const local = translatePoly(poly, -cx, -cz);
    const shape = new THREE.Shape();
    local.forEach(([x, z], i) => (i ? shape.lineTo(x, -z) : shape.moveTo(x, -z)));
    const h = yTop - yBottom;
    const geo = new THREE.ExtrudeGeometry(shape, { depth: h, bevelEnabled: false });
    geo.rotateX(-Math.PI / 2);
    const mesh = new THREE.Mesh(geo, [o.top || mat('areia'), o.side || mat('rocha')]);
    mesh.position.set(cx, yBottom, cz);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    this.group.add(mesh);
    if (o.block !== false) this.cameraBlockers.push(mesh);
    const col = o.collide === false ? null : this.collider(local, yBottom, yTop, o.tags || { safe: true }, { x: cx, z: cz, name: o.name });
    return { mesh, col, local, cx, cz, h };
  }

  deco(name, x, y, z, o = {}) {
    const p = this.assets.prop(name, o);
    p.position.set(x, y, z);
    p.rotation.y = o.rot ?? this.rnd() * Math.PI * 2;
    this.group.add(p);
    if (o.collide) {
      const r = o.collide === true ? Math.max(p.userData.size.x, p.userData.size.z) * 0.42 : o.collide;
      this.collider(ngon(r, 8, x, z), y - 0.5, y + p.userData.size.y, { cover: !!o.cover }, { name });
    }
    if (o.block) this.cameraBlockers.push(p);
    return p;
  }

  scatter(names, center, rMin, rMax, count, y = 0, o = {}) {
    for (let i = 0; i < count; i++) {
      const a = this.rnd() * Math.PI * 2;
      const r = rMin + this.rnd() * (rMax - rMin);
      const x = center.x + Math.cos(a) * r, z = center.z + Math.sin(a) * r;
      if (o.avoid && o.avoid(x, z)) continue;
      const name = names[Math.floor(this.rnd() * names.length)];
      const h = (o.hMin ?? 0.5) + this.rnd() * ((o.hMax ?? 1.2) - (o.hMin ?? 0.5));
      this.deco(name, x, y, z, { height: h, tone: o.tone, variant: Math.floor(this.rnd() * 3) });
    }
  }

  island(cfg, holes, top, thickness, seed, extra = {}) {
    const poly = octagon(cfg.r);
    const isl = buildIsland({ poly, holes, top, thickness, rootDepth: cfg.r * 1.05, seed, ...extra });
    isl.position.set(cfg.x, 0, cfg.z);
    this.group.add(isl);
    this.cameraBlockers.push(isl.children[0]);
    return isl;
  }

  scannable(pos, key, kind, extra = {}) {
    const s = { pos, key, kind, ...extra };
    this.scannables.push(s);
    return s;
  }

  // --- A: Farol Nulo (chegada) ----------------------------------------------------

  buildArrival() {
    this.island(A, [], 0, 1.4, 11);
    this.collider(octagon(A.r, A.x, A.z), -1.4, 0, { safe: true, area: AREAS.ARRIVAL }, { name: 'ilhaA' });
    // mirante: rocha elevada de onde se salta e plana até a cisterna
    this.slab(rect(-2.5, 29.4, 2.5, 32.8), 0.9, -0.6, { name: 'mirante', tags: { safe: true } });
    this.deco('stone2', -2.2, 0.9, 30.2, { height: 0.35, tone: 'rocha' });
    this.deco('stone4', 2.0, 0.9, 32.2, { height: 0.3, tone: 'escura' });
    // Farol Nulo: coluna com cristal adormecido
    this.deco('column', -4.6, 0, 39.6, { height: 4.6, rot: 0.3, collide: 0.75, block: true });
    const beacon = this.deco('gemBlue', -4.6, 4.6, 39.6, { height: 1.3, rot: 0 });
    this.animated.push((t) => { beacon.rotation.y = t * 0.3; });
    this.beaconLight = new THREE.PointLight(PALETTE.ressonancia, 6, 14, 2);
    this.beaconLight.position.set(-4.6, 5.4, 39.6);
    this.group.add(this.beaconLight);
    this.deco('columnBroken2', 4.8, 0, 38.8, { height: 2.0, collide: 0.75 });
    this.deco('columnBroken', 3.6, 0, 41.8, { height: 0.9, rot: 1.2 });
    this.deco('rockCluster1', -5.2, 0, 33.4, { height: 1.0, tone: 'rocha' });
    this.deco('rock3', 5.2, 0, 34.0, { height: 1.1, tone: 'rocha', collide: 0.55 });
    this.deco('crystal2', 4.3, 0, 32.8, { height: 0.9 });
    this.deco('crystal3', 4.8, 0, 32.4, { height: 0.6 });
    this.deco('plant3', 2.5, 0, 42.6, { height: 0.9 });
    this.deco('plant1', -2.4, 0, 43.2, { height: 0.6 });
    this.deco('plant5', -5.8, 0, 36.6, { height: 0.9 });
    this.deco('plant2', 6.0, 0, 37.0, { height: 1.0 });
    this.start = { pos: V(0, 0, 40.5), yaw: Math.PI };
  }

  // --- B: Cisterna --------------------------------------------------------------------

  buildCistern() {
    const [hx0, hz0, hx1, hz1] = B.hole;
    const holeLocal = rect(hx0 - B.x, hz0 - B.z, hx1 - B.x, hz1 - B.z);
    this.island(B, [holeLocal], 0, B.depth, 23, { rootDepth: B.r * 0.9 });
    for (const piece of subtractRect(octagon(B.r, B.x, B.z), hx0, hz0, hx1, hz1)) {
      this.collider(piece, -B.depth, 0, { safe: true, area: AREAS.CISTERN_TOP }, { name: 'ilhaB' });
    }
    // fundo da cisterna
    this.slab(rect(hx0, hz0, hx1, hz1), B.floorY, -B.depth, { top: mat('#8F7A63'), side: mat('rochaEscura'), name: 'fundo', block: false });
    this.cisternRect = rect(hx0, hz0, hx1, hz1);

    // água da cisterna
    const w = new THREE.Mesh(new THREE.PlaneGeometry(hx1 - hx0, hz1 - hz0), waterMaterial({ opacity: 0.82, energy: 0.25, scale: 1.4 }));
    w.rotation.x = -Math.PI / 2;
    w.position.set((hx0 + hx1) / 2, 0, (hz0 + hz1) / 2);
    this.group.add(w);
    this.cisternWater = w;
    this.hazards.push({ poly: this.cisternRect, levelAt: (lv) => lerp(-4.1, -0.45, lv), mesh: w });

    // escada de cristal na parede oeste (sólida só na maré baixa)
    this.crystalSteps = [];
    for (let i = 1; i <= 8; i++) {
      const top = B.floorY + i * 0.4375;
      const zc = 11.3 + (8 - i) * 0.6;
      const geo = new THREE.BoxGeometry(1.25, 0.32, 0.6);
      const m = new THREE.Mesh(geo, mat('#58D6C4', { emissive: PALETTE.ressonancia, emissiveIntensity: 0.45, roughness: 0.3 }));
      m.position.set(-2.38, top - 0.16, zc);
      m.castShadow = true;
      this.group.add(m);
      const col = this.collider(rect(-1.25 / 2, -0.3, 1.25 / 2, 0.3), top - 0.35, top, { safe: false }, { x: -2.38, z: zc, name: 'degrauCristal' });
      this.crystalSteps.push({ mesh: m, col, top });
    }

    // condutor de cobre no fundo
    const cond = new THREE.Group();
    cond.position.set(0, B.floorY, 14);
    const base = new THREE.Mesh(new THREE.CylinderGeometry(0.9, 1.05, 0.3, 8), mat('rochaEscura'));
    base.position.y = 0.15;
    base.receiveShadow = true;
    cond.add(base);
    const rotor = new THREE.Group();
    rotor.position.y = 0.3;
    const pipe = this.assets.prop('pipeT', { height: 0.8 });
    pipe.rotation.x = Math.PI / 2;
    pipe.position.set(0, 0.45, -0.1);
    rotor.add(pipe);
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.75, 0.08, 6, 16), mat('cobre', { metalness: 0.35, roughness: 0.45 }));
    ring.rotation.x = Math.PI / 2;
    ring.position.y = 0.12;
    rotor.add(ring);
    cond.add(rotor);
    this.group.add(cond);
    this.collider(ngon(0.95, 8, 0, 14), B.floorY - 0.2, B.floorY + 0.3, { safe: true }, { name: 'baseCondutor' });
    this.conductor = { pos: V(0, B.floorY, 14), radius: 1.9, rotor, angle: 0, target: 0 };
    this.scannable(V(0, B.floorY + 1, 14), 'scan.conductor', 'conductor');

    // trilha de circuito: fundo -> parede norte -> topo -> emissor
    this.circuitMat = mat('#8A5A35', { emissive: PALETTE.cobre, emissiveIntensity: 0.15 }).clone();
    const strip = (w2, h2, d2, x, y, z) => {
      const m = new THREE.Mesh(new THREE.BoxGeometry(w2, h2, d2), this.circuitMat);
      m.position.set(x, y, z);
      this.group.add(m);
    };
    strip(0.22, 0.04, 2.3, 0, B.floorY + 0.02, 12.15);
    strip(0.22, 3.5, 0.04, 0, B.floorY + 1.75, hz0 + 0.03);
    strip(0.22, 0.04, 5.4, 0, 0.02, 8.25);

    // nó de ressonância da cisterna
    this.addNode('node_cisterna', V(6.0, 0, 17.5), AREAS.CISTERN_TOP);

    // emissor da ponte (borda norte)
    this.emitter = this.buildEmitter(V(0, 0, 5.6));
    this.emitterC = this.buildEmitter(V(0, 0, -3.9), true);
    this.scannable(V(0, 1.2, 5.6), 'scan.emitter', 'emitter');

    // plataformas de flutuação (sobem na maré alta) -> eco opcional
    this.floaters = [];
    const fl = [[11.9, 13.0, 0.35], [14.6, 11.0, 1.1], [17.0, 8.6, 1.85]];
    fl.forEach(([x, z, hi], i) => {
      const g = buildIsland({ poly: ngon(1.15, 6, 0, 0, Math.PI / 6), top: 0, thickness: 0.5, rootDepth: 1.2, seed: 100 + i, topMat: mat('areiaClara') });
      const glow = new THREE.Mesh(new THREE.CircleGeometry(0.9, 6), glowMat(1.2));
      glow.rotation.x = Math.PI / 2;
      glow.position.y = -1.6;
      g.add(glow);
      g.position.set(x, hi, z);
      this.group.add(g);
      const col = this.collider(ngon(1.15, 6, 0, 0, Math.PI / 6), hi - 0.5, hi, { safe: false }, { x, z, name: 'flutuante' });
      this.floaters.push({ g, col, x, z, hi, lo: -7 - i, phase: i * 1.7 });
    });
    const perch = this.slab(ngon(1.6, 8, 19.0, 5.6), 2.55, -1.2, { name: 'pilarEco', tags: { safe: true } });
    const perchRoot = buildIsland({ poly: ngon(1.6, 8), top: -1.2, thickness: 0.1, rootDepth: 3, seed: 77 });
    perchRoot.position.set(19.0, 0, 5.6);
    this.group.add(perchRoot);
    void perch;

    // decoração
    this.deco('columnBroken', -7.2, 0, 18.2, { height: 1.4, rot: 0.4 });
    this.deco('column', 7.4, 0, 9.0, { height: 3.6, collide: 0.6, block: true });
    this.deco('columnBroken2', -6.8, 0, 9.4, { height: 2.4, collide: 0.75 });
    this.deco('rock5', 4.6, 0, 21.0, { height: 0.9, tone: 'rocha', collide: 0.45 });
    this.deco('rock6', -4.8, 0, 21.4, { height: 1.0, tone: 'rocha', collide: 0.5 });
    this.deco('rockCluster2', 8.2, 0, 15.0, { height: 0.6, tone: 'escura' });
    this.deco('crystal1', 7.4, 0, 19.0, { height: 0.9 });
    this.deco('crystal2b', 7.9, 0, 18.4, { height: 0.7 });
    this.deco('crystal5', 5.2, 0, 19.6, { height: 0.45 });
    this.deco('plant3', -8.0, 0, 13.6, { height: 0.9 });
    this.deco('plant1', 3.6, 0, 7.2, { height: 0.6 });
    this.deco('plant2', -3.2, 0, 7.4, { height: 1.1 });
    this.deco('crystal3', -2.6, B.floorY, 16.6, { height: 0.5 });
    this.deco('stone3', 2.4, B.floorY, 16.4, { height: 0.35, tone: 'escura' });
    this.deco('pipeStraight', 2.4, B.floorY, 12.0, { height: 0.5, rot: 0 });
  }

  buildEmitter(pos, receiver = false) {
    const g = new THREE.Group();
    g.position.copy(pos);
    for (const sx of [-1.55, 1.55]) {
      const post = this.assets.prop('columnBroken2', { height: 1.3, tone: 'ceramica' });
      post.position.set(sx, 0, 0);
      g.add(post);
      const cap = new THREE.Mesh(new THREE.OctahedronGeometry(0.22), glowMat(0.4));
      cap.position.set(sx, 1.55, 0);
      g.add(cap);
      g.userData.caps = (g.userData.caps || []).concat(cap);
    }
    if (!receiver) {
      const lip = new THREE.Mesh(new THREE.BoxGeometry(2.7, 0.12, 0.5), mat('cobre', { metalness: 0.3, roughness: 0.5 }));
      lip.position.set(0, 0.06, -0.9);
      g.add(lip);
    }
    for (const sx of [-1.55, 1.55]) this.collider(ngon(0.45, 8, pos.x + sx, pos.z), -0.5, 1.35, {}, { name: 'emissor' });
    this.group.add(g);
    return g;
  }

  addNode(id, pos, area) {
    const g = new THREE.Group();
    g.position.copy(pos);
    const ped = new THREE.Mesh(new THREE.CylinderGeometry(0.75, 0.95, 0.45, 8), mat('ceramica'));
    ped.position.y = 0.22;
    ped.castShadow = true;
    ped.receiveShadow = true;
    g.add(ped);
    const ringMat = mat('#2FA3A0', { emissive: PALETTE.ressonancia, emissiveIntensity: 0.8 }).clone();
    const outer = new THREE.Mesh(new THREE.TorusGeometry(0.85, 0.16, 6, 16), mat('ceramica'));
    outer.position.y = 1.55;
    outer.castShadow = true;
    g.add(outer);
    const inner = new THREE.Mesh(new THREE.TorusGeometry(0.62, 0.05, 6, 24), ringMat);
    inner.position.y = 1.55;
    g.add(inner);
    const core = this.assets.prop('crystal3', { height: 0.55 });
    core.position.y = 1.28;
    g.add(core);
    const supports = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.7, 0.18), mat('cobre', { metalness: 0.3, roughness: 0.5 }));
    supports.position.set(0, 0.8, 0);
    g.add(supports);
    // círculo de interação no chão (forma + cor, não depende só da cor)
    const circle = new THREE.Mesh(new THREE.RingGeometry(2.2, 2.35, 32), new THREE.MeshBasicMaterial({ color: PALETTE.ressonancia, transparent: true, opacity: 0.35, depthWrite: false }));
    circle.rotation.x = -Math.PI / 2;
    circle.position.y = 0.03;
    g.add(circle);
    this.group.add(g);
    this.collider(ngon(0.9, 8, pos.x, pos.z), pos.y - 0.5, pos.y + 0.45, { safe: true }, { name: id });
    const node = { id, pos, area, radius: 2.4, group: g, outer, inner, ringMat, core, circle, hold: 0 };
    this.nodes.push(node);
    this.scannable(pos.clone().add(V(0, 2.2, 0)), 'scan.node', 'node', { node });
    return node;
  }

  // --- pontes ---------------------------------------------------------------------

  buildBridges() {
    // ponte líquida (maré alta + condutor)
    const len = 9.0, w = 2.6, bz = 1.2;
    const geo = new THREE.BoxGeometry(w, 0.8, len);
    geo.translate(0, -0.4, 0);
    this.bridgeMat = waterMaterial({ opacity: 0.9, energy: 0.6, scale: 1.2, flow: [0, -0.8], deep: '#1C7F86', shallow: '#3DB8B0', wave: 0.0 });
    this.bridge = new THREE.Mesh(geo, this.bridgeMat);
    this.bridge.position.set(0, -0.02, bz);
    this.bridge.visible = false;
    this.group.add(this.bridge);
    this.bridgeCol = this.collider(rect(-w / 2, -len / 2, w / 2, len / 2), -0.8, -0.02, { safe: false }, { x: 0, z: bz, name: 'ponteLiquida', enabled: false });
    this.bridgeCol.enabled = false;

    // atalho de cerâmica (abre após o eco)
    const sgeo = new THREE.BoxGeometry(1.6, 0.5, len);
    sgeo.translate(0, -0.25, 0);
    this.shortcut = new THREE.Mesh(sgeo, [mat('ceramica'), mat('ceramica'), mat('areiaClara'), mat('rocha'), mat('ceramica'), mat('ceramica')]);
    this.shortcut.position.set(-3.2, -14, bz);
    this.bridgeZ = bz;
    this.shortcut.castShadow = true;
    this.shortcut.receiveShadow = true;
    this.shortcut.visible = false;
    this.group.add(this.shortcut);
    this.shortcutCol = this.collider(rect(-0.8, -len / 2, 0.8, len / 2), -0.5, 0, { safe: true }, { x: -3.2, z: bz, name: 'atalho' });
    this.shortcutCol.enabled = false;
    this.shortcutT = 0;
  }

  // --- C: Jardim Mineral e praça do guardião --------------------------------------

  buildGarden() {
    const pr = C.plazaR;
    this.island(C, [octagon(pr)], 0, C.depth, 31);
    const outer = octagon(C.r, C.x, C.z), inner = octagon(pr, C.x, C.z);
    for (const piece of ringPieces(outer, inner)) this.collider(piece, -C.depth, 0, { safe: true, area: AREAS.GARDEN }, { name: 'ilhaC' });
    this.plazaPoly = inner;
    this.slab(inner, C.floorY, -C.depth, { top: mat('#A88566'), side: mat('rochaEscura'), name: 'praca', block: false, tags: { safe: true, area: AREAS.PLAZA } });

    const L = (x, z) => [C.x + x, C.z + z];
    // degraus sul e leste
    const ap = pr * Math.cos(Math.PI / 8);
    for (let i = 1; i <= 4; i++) {
      const top = -0.44 * i;
      const z0 = ap - 0.6 * i, z1 = z0 + 0.6;
      this.slab([L(-1.2, z0), L(1.2, z0), L(1.2, z1), L(-1.2, z1)], top, -C.depth, { top: mat('areiaClara'), side: mat('ceramica'), name: 'degrauSul' });
      const x0 = ap - 0.6 * i, x1 = x0 + 0.6;
      this.slab([L(x0, -1.2), L(x1, -1.2), L(x1, 1.2), L(x0, 1.2)], top, -C.depth, { top: mat('areiaClara'), side: mat('ceramica'), name: 'degrauLeste' });
    }
    // poleiro central do guardião
    this.slab(ngon(1.3, 6, C.x, C.z), -0.15, -C.depth, { top: mat('areiaClara'), side: mat('rocha'), name: 'poleiro', tags: {} });
    // pedras e cristais quebram a silhueta do poleiro
    [[1.25, 0.4, 'rock4', 1.3], [-1.1, 0.9, 'rock6', 1.1], [0.3, -1.35, 'rock7', 1.5], [-0.9, -0.8, 'crystal2b', 0.9]].forEach(([x, z, n, hgt]) => {
      this.deco(n, C.x + x, C.floorY, C.z + z, { height: hgt, tone: 'rocha' });
    });

    // água da praça
    const pshape = new THREE.Shape();
    octagon(pr).forEach(([x, z], i) => (i ? pshape.lineTo(x, -z) : pshape.moveTo(x, -z)));
    const pgeo = new THREE.ShapeGeometry(pshape);
    pgeo.rotateX(-Math.PI / 2);
    const pw = new THREE.Mesh(pgeo, waterMaterial({ opacity: 0.84, energy: 0.22, scale: 1.1 }));
    pw.position.set(C.x, 0, C.z);
    this.group.add(pw);
    this.plazaWater = pw;
    this.hazards.push({ poly: inner, levelAt: (lv) => lerp(-2.75, -0.4, lv), mesh: pw });

    // cristais de cobertura (bloqueiam a visão do guardião)
    this.covers = [];
    const cov = [[-6.0, 4.0, 0.8, 2.6], [-6.3, -2.8, 0.8, 3.0], [0.9, -7.0, 0.8, 2.8], [6.2, -4.0, 0.75, 2.5], [4.4, 5.5, 0.7, 2.3]];
    cov.forEach(([x, z, r, h], i) => {
      const [wx, wz] = L(x, z);
      const g = this.deco('gemBlue', wx, C.floorY, wz, { height: h, rot: i * 1.3, variant: i });
      g.scale.x *= 1.15;
      const g2 = this.deco(i % 2 ? 'crystal1' : 'crystal2', wx + 0.6, C.floorY, wz + 0.3, { height: h * 0.45, variant: i + 1 });
      void g2;
      this.collider(ngon(r, 8, wx, wz), C.floorY - 0.5, C.floorY + h, { cover: true }, { name: 'cobertura' });
      this.covers.push({ x: wx, z: wz, r: r + 0.15 });
    });

    // placas de circuito (a do triângulo conduz)
    const plateDefs = [
      { id: 'triangulo', glyph: 3, correct: true, at: [1.2, -5.9] },
      { id: 'circulo', glyph: 0, correct: false, at: [-6.2, 0.8] },
      { id: 'quadrado', glyph: 4, correct: false, at: [5.6, 4.3] },
    ];
    for (const d of plateDefs) {
      const [wx, wz] = L(...d.at);
      const g = new THREE.Group();
      g.position.set(wx, C.floorY + 0.02, wz);
      const base = new THREE.Mesh(new THREE.CylinderGeometry(0.85, 0.9, 0.06, 8), mat('cobre', { metalness: 0.35, roughness: 0.5 }));
      base.position.y = 0.03;
      g.add(base);
      const gm = mat('#2A4F57', { emissive: PALETTE.ressonancia, emissiveIntensity: 0.05 }).clone();
      const glyphGeo = d.glyph === 0 ? new THREE.RingGeometry(0.32, 0.46, 24) : new THREE.RingGeometry(0.3, 0.48, d.glyph, 1, d.glyph === 4 ? Math.PI / 4 : Math.PI / 2);
      glyphGeo.rotateX(-Math.PI / 2);
      const glyph = new THREE.Mesh(glyphGeo, gm);
      glyph.position.y = 0.07;
      g.add(glyph);
      if (!d.correct) {
        const crack = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.02, 1.2), mat('salVivo'));
        crack.rotation.y = 0.7;
        crack.position.y = 0.075;
        crack.visible = false;
        g.add(crack);
        g.userData.crack = crack;
      }
      this.group.add(g);
      const plate = { ...d, pos: V(wx, C.floorY, wz), group: g, glyphMat: gm, radius: 1.1, revealed: false };
      this.plates.push(plate);
      this.scannable(V(wx, C.floorY + 0.8, wz), d.correct ? 'scan.plateGood' : 'scan.plateBad', 'plate', { plate });
    }

    // relé remoto sobre coluna alta (inalcançável: Lume leva o sinal)
    const [rx, rz] = L(-4.6, -10.4);
    this.deco('column', rx, 0, rz, { height: 5.2, rot: 0, collide: 0.75, block: true });
    const lever = this.deco('lever', rx, 5.2, rz, { height: 0.7, rot: Math.PI });
    const relayGem = this.deco('crystal3', rx + 0.35, 5.2, rz, { height: 0.6 });
    this.relay = { pos: V(rx, 6.3, rz + 0.6), lever, gem: relayGem, active: false };
    this.scannable(V(rx, 6.0, rz), 'scan.relay', 'relay');
    this.relayBeamMat = new THREE.MeshBasicMaterial({ color: PALETTE.ressonancia, transparent: true, opacity: 0, depthWrite: false });

    // nó de maré do jardim
    const [nx, nz] = L(-9.0, 6.5);
    this.addNode('node_jardim', V(nx, 0, nz), AREAS.GARDEN);

    // portão norte (abre com o relé)
    const gz = C.z - C.r * Math.cos(Math.PI / 8) + 0.35;
    for (const sx of [-1.95, 1.95]) this.deco('column', sx, 0, gz, { height: 4.2, rot: 0, collide: 0.72, block: true });
    const lintel = new THREE.Mesh(new THREE.BoxGeometry(5.0, 0.6, 1.0), mat('ceramica'));
    lintel.position.set(0, 4.5, gz);
    lintel.castShadow = true;
    this.group.add(lintel);
    const door = new THREE.Mesh(new THREE.BoxGeometry(3.0, 3.6, 0.45), [mat('ceramica'), mat('ceramica'), mat('ceramica'), mat('ceramica'), mat('petroleo'), mat('petroleo')]);
    door.position.set(0, 1.8, gz);
    door.castShadow = true;
    const doorGlyph = new THREE.Mesh(new THREE.RingGeometry(0.4, 0.6, 3, 1, Math.PI / 2), mat('#2A4F57', { emissive: PALETTE.ressonancia, emissiveIntensity: 0.1 }).clone());
    doorGlyph.position.set(0, 0.4, 0.24);
    door.add(doorGlyph);
    this.group.add(door);
    this.gate = { door, glyph: doorGlyph, z: gz, open: 0, col: this.collider(rect(-1.6, -0.3, 1.6, 0.3), -0.5, 3.6, {}, { x: 0, z: gz, name: 'portao' }) };
    this.cameraBlockers.push(door);

    // torre de pedra + degraus -> planar até a ilhota do eco
    this.slab(rect(...L(-10.55, -6.75), ...L(-9.05, -5.25)), 0.8, -0.5, { top: mat('rocha'), side: mat('rochaEscura'), name: 'pedra1' });
    this.slab(rect(...L(-11.7, -5.9), ...L(-10.3, -4.5)), 1.5, -0.5, { top: mat('rocha'), side: mat('rochaEscura'), name: 'pedra2' });
    this.slab(rect(...L(-11.9, -3.9), ...L(-10.1, -2.1)), 2.2, -0.5, { top: mat('rocha'), side: mat('rochaEscura'), name: 'torre' });
    const [tx, tz] = L(-11.4, -2.5);
    this.deco('crystal5', tx, 2.2, tz, { height: 0.35 });
    const islet = buildIsland({ poly: octagon(2.4), top: 1.0, thickness: 0.8, rootDepth: 3.4, seed: 91 });
    const [ix, iz] = L(-20.5, -3.0);
    islet.position.set(ix, 0, iz);
    this.group.add(islet);
    this.cameraBlockers.push(islet.children[0]);
    this.collider(octagon(2.4, ix, iz), 0.2, 1.0, { safe: true }, { name: 'ilhota' });
    this.deco('plant2', ix - 1.0, 1.0, iz + 0.8, { height: 0.9 });
    this.deco('columnBroken', ix + 0.9, 1.0, iz - 1.2, { height: 0.8 });
    this.isletEchoPos = V(ix, 2.0, iz);

    // jardim mineral: cristais, corais e ruínas no terraço
    const avoid = (x, z) => {
      const dx = x - C.x, dz = z - C.z;
      if (Math.hypot(dx, dz) < pr + 0.8) return true; // praça
      if (Math.abs(x) < 2.2 && z > C.z + 9) return true; // chegada da ponte
      if (Math.abs(x) < 2.8 && z < C.z - 9) return true; // portão
      if (Math.hypot(x - (C.x - 9), z - (C.z + 6.5)) < 2.8) return true; // nó
      if (x < C.x - 8.5 && z > C.z - 8 && z < C.z - 1) return true; // torre
      if (Math.hypot(x - rx, z - rz) < 1.6) return true;
      return false;
    };
    this.scatter(['crystal1', 'crystal2', 'crystal3', 'crystal5', 'crystal1b', 'crystal2b'], V(C.x, 0, C.z), pr + 1.2, C.r - 1.5, 34, 0, { avoid, hMin: 0.4, hMax: 1.3 });
    this.scatter(['plant2', 'plant3', 'plant5', 'plant1'], V(C.x, 0, C.z), pr + 1.2, C.r - 1.4, 14, 0, { avoid, hMin: 0.5, hMax: 1.1 });
    this.scatter(['rock1', 'rock4', 'rock7', 'stone1', 'stone5'], V(C.x, 0, C.z), pr + 1.5, C.r - 1.2, 8, 0, { avoid, hMin: 0.4, hMax: 0.9, tone: 'rocha' });
    this.deco('columnBroken2', C.x + 9.5, 0, C.z - 4.5, { height: 2.6, collide: 0.75 });
    this.deco('columnBroken', C.x + 8.6, 0, C.z + 6.8, { height: 1.2 });
    this.deco('column', C.x + 6.8, 0, C.z - 9.4, { height: 4.0, collide: 0.65, block: true });
    this.scatter(['crystal3', 'crystal5', 'stone3'], V(C.x, C.floorY, C.z), 2.0, pr - 1.2, 10, C.floorY, {
      hMin: 0.25, hMax: 0.5,
      avoid: (x, z) => this.plates.some((p) => Math.hypot(p.pos.x - x, p.pos.z - z) < 1.6) || Math.abs(x - C.x) < 1.6 || Math.abs(z - C.z) < 1.6,
    });

    // guardião: patrulha em volta do poleiro (só no piso seco)
    const wp = [[-4.2, 1.8], [-4.2, -2.6], [-1.2, -4.6], [2.8, -3.8], [4.3, 0.2], [2.0, 3.9], [-1.4, 4.2]];
    this.guardCfg = {
      waypoints: wp.map(([x, z]) => V(C.x + x, C.floorY, C.z + z)),
      perch: V(C.x, -0.15, C.z),
      floorY: C.floorY,
      covers: this.covers,
    };
    this.plazaSafeExit = V(0, 0, C.z + ap + 1.6);
    this.scannable(V(C.x, 0.8, C.z), 'scan.guardian', 'guardian');
    this.checkpointGarden = { id: 'jardim', pos: V(0, 0, C.z + C.r * Math.cos(Math.PI / 8) - 1.6), yaw: Math.PI, radius: 2.6 };
  }

  // --- D: Santuário das Marés ----------------------------------------------------

  buildSanctuary() {
    const model = this.assets.original('sanctuary');
    const s = D.scale;
    model.scale.setScalar(s);
    model.position.set(0, D.top - 0.15 * s, D.z);
    this.group.add(model);
    model.updateMatrixWorld(true);
    const parts = {};
    model.traverse((o) => { if (o.isMesh) parts[o.name] = o; });
    this.sanctuaryParts = parts;
    const v = new THREE.Vector3();
    const hullOf = (mesh) => {
      const pos = mesh.geometry.attributes.position;
      const pts = [];
      let y0 = Infinity, y1 = -Infinity;
      for (let i = 0; i < pos.count; i++) {
        v.fromBufferAttribute(pos, i).applyMatrix4(mesh.matrixWorld);
        pts.push([v.x, v.z]);
        y0 = Math.min(y0, v.y); y1 = Math.max(y1, v.y);
      }
      return { poly: hull2D(pts), y0, y1 };
    };
    for (const [name, mesh] of Object.entries(parts)) {
      if (/^(island_root|pool_water|energy_ring|heart|portal_inner|cap_)/.test(name)) continue;
      const h = hullOf(mesh);
      const safe = /^(terrace|pool|plinth|island)/.test(name);
      this.collider(h.poly, h.y0, h.y1, { safe, area: AREAS.SANCTUARY }, { name: 'santuario_' + name });
      if (/^(island_000|terrace|portal_outer|pillar)/.test(name)) this.cameraBlockers.push(mesh);
    }
    // borda sul do terraço ao longo de x = 0 (para encaixar a escadaria)
    const terr = hullOf(parts.terrace_002).poly;
    let zSouth = -Infinity;
    for (let i = 0; i < terr.length; i++) {
      const a = terr[i], b = terr[(i + 1) % terr.length];
      if ((a[0] <= 0 && b[0] >= 0) || (a[0] >= 0 && b[0] <= 0)) {
        const t = Math.abs(b[0] - a[0]) < 1e-6 ? 0 : (0 - a[0]) / (b[0] - a[0]);
        zSouth = Math.max(zSouth, a[1] + (b[1] - a[1]) * t);
      }
    }
    const zNorthC = C.z - C.r * Math.cos(Math.PI / 8);
    const n = 8, depth = (zNorthC - zSouth) / n;
    for (let i = 1; i <= n; i++) {
      const top = i === n ? D.top - 0.01 : (D.top / n) * i;
      const z0 = zNorthC - depth * i, z1 = z0 + depth;
      this.slab(rect(-1.3, z0 - (i === n ? 0.6 : 0), 1.3, z1 + (i === 1 ? 0.15 : 0)), top, top - 0.9, { top: mat('areiaClara'), side: mat('ceramica'), name: 'escadaria' });
    }

    // eco principal = coração do anel; fonte = poço central
    repivot(parts.heart_028);
    repivot(parts.energy_ring_027);
    this.mainEcho = { mesh: parts.heart_028, base: parts.heart_028.position.clone(), pos: new THREE.Vector3(), recovered: false };
    parts.heart_028.getWorldPosition(this.mainEcho.pos);
    const box = new THREE.Box3().setFromObject(parts.heart_028);
    box.getCenter(this.mainEcho.pos);
    const fountain = new THREE.Box3().setFromObject(parts.pool_water_004);
    this.fountain = { pos: fountain.getCenter(new THREE.Vector3()), radius: 3.6 };
    this.ringMesh = parts.energy_ring_027;
    this.ringMesh.material = this.ringMesh.material.clone();
    this.poolMesh = parts.pool_water_004;
    this.poolMesh.material = this.poolMesh.material.clone();
    this.sanctuaryCenter = V(0, D.top, D.z);
    this.checkpointSanctuary = { id: 'santuario', pos: V(0, D.top + 0.1, zSouth - 1.4), yaw: Math.PI, radius: 3 };
    this.scannable(this.mainEcho.pos.clone(), 'scan.sanctuary', 'sanctuary');

    // pulso que percorre a borda da ilha ao ativar (GDD 08)
    const pulse = new THREE.Mesh(new THREE.TorusGeometry(1, 0.05, 6, 48), glowMat(2.4));
    pulse.rotation.x = Math.PI / 2;
    pulse.position.set(0, D.top + 0.2, D.z);
    pulse.visible = false;
    this.group.add(pulse);
    this.sanctuaryPulse = { mesh: pulse, t: 1 };
  }

  // --- ecos opcionais -----------------------------------------------------------

  buildEchoes() {
    const mk = (id, pos) => {
      const g = this.assets.prop('gemPink', { height: 0.7 });
      const holder = new THREE.Group();
      holder.position.copy(pos);
      holder.add(g);
      const light = new THREE.PointLight(PALETTE.ressonancia, 4, 6, 2);
      light.position.y = 0.4;
      holder.add(light);
      this.group.add(holder);
      const e = { id, pos: pos.clone(), group: holder, radius: 1.3, collected: false };
      this.echoes.push(e);
      this.scannable(pos.clone().add(V(0, 0.9, 0)), 'scan.echo', 'echo', { echo: e });
      return e;
    };
    mk('float', V(19.0, 3.05, 5.6));
    mk('islet', this.isletEchoPos.clone());
  }

  // --- consultas ------------------------------------------------------------------

  /** Área lógica (PuzzleGraph) em que um ponto está. */
  areaAt(p, prev = null) {
    if (Math.hypot(p.x - A.x, p.z - A.z) < A.r + 1 && p.y > -2) return AREAS.ARRIVAL;
    if (p.z > 3.6 && p.z < 26 && p.x > -11 && p.x < 22) {
      if (insideConvex(this.cisternRect, p.x, p.z) && p.y < -0.6) return AREAS.CISTERN_BOTTOM;
      if (p.z > 4.8 || p.x > 9) return AREAS.CISTERN_TOP;
    }
    if (p.z < -31 && p.y > 1.5) return AREAS.SANCTUARY;
    if (Math.hypot(p.x - C.x, p.z - C.z) < C.r + 10 && p.z < -2.5) {
      if (insideConvex(this.plazaPoly, p.x, p.z) && p.y < -0.6) return AREAS.PLAZA;
      return AREAS.GARDEN;
    }
    return prev;
  }

  /** Nível da água no ponto (ou -Infinity se não há bacia). */
  waterAt(x, z, tideLevel) {
    for (const h of this.hazards) if (insideConvex(h.poly, x, z)) return h.levelAt(tideLevel);
    return -Infinity;
  }

  // --- atualização visual ---------------------------------------------------------

  /**
   * @param {object} ctx {tideLevel, bridgeLevel, world, dt, time, reduceMotion}
   */
  update(ctx) {
    const { tideLevel: lv, dt, world } = ctx;
    this.time += dt;
    const t = this.time;
    for (const f of this.animated) f(t);

    // água das bacias
    for (const h of this.hazards) {
      h.mesh.position.y = h.levelAt(lv);
      h.mesh.material.uniforms.uTime.value = t;
    }
    this.bridgeMat.uniforms.uTime.value = t;

    // escada de cristal: sólida na maré baixa
    const stepsOut = lv < 0.3;
    this.crystalSteps.forEach((s, i) => {
      s.col.enabled = stepsOut;
      const target = stepsOut ? -2.38 : -3.6;
      s.mesh.position.x += (target - s.mesh.position.x) * (1 - Math.exp(-(4 + i * 0.3) * dt));
      s.mesh.visible = s.mesh.position.x > -3.55;
    });

    // plataformas de flutuação
    for (const f of this.floaters) {
      const y = lerp(f.lo, f.hi, Math.pow(lv, 1.4)) + Math.sin(t * 0.9 + f.phase) * 0.06 * lv;
      f.g.position.y = y;
      f.col.moveTo(f.x, y, f.z);
      f.col.enabled = y > f.lo + 1;
    }

    // ponte líquida
    const bl = ctx.bridgeLevel;
    this.bridge.visible = bl > 0.02;
    this.bridge.scale.set(Math.min(1, bl * 1.4), Math.max(0.01, bl), 1);
    this.bridge.position.y = -0.02 - (1 - bl) * 0.6;
    this.bridgeCol.enabled = bl > 0.75;

    // circuito e emissores
    const powered = world.conductorRotated;
    this.circuitMat.emissive.set(powered ? PALETTE.ressonancia : PALETTE.cobre);
    this.circuitMat.emissiveIntensity = powered ? 0.9 + 0.5 * Math.sin(t * 4) : 0.15;
    for (const em of [this.emitter, this.emitterC]) {
      for (const cap of em.userData.caps) cap.material = powered ? glowMat(1.8) : glowMat(0.3);
    }

    // condutor girando
    const c = this.conductor;
    c.angle += (c.target - c.angle) * (1 - Math.exp(-3 * dt));
    c.rotor.rotation.y = c.angle;

    // nós de maré
    for (const n of this.nodes) {
      n.inner.rotation.z = t * (0.6 + (ctx.tideTransition ? 4 : 0));
      n.inner.rotation.x = Math.sin(t * 0.8) * 0.2;
      n.ringMat.emissiveIntensity = 0.7 + n.hold * 2.5 + (ctx.tideTransition ? 1.5 : 0) + Math.sin(t * 2) * 0.15;
      n.circle.material.opacity = 0.2 + n.hold * 0.6;
      n.circle.scale.setScalar(1 - n.hold * 0.15);
    }

    // placas (submersas na maré alta)
    for (const p of this.plates) {
      const lit = p.correct && (world.platesScanned || world.relayActive);
      p.glyphMat.emissiveIntensity = lit ? 1.4 + Math.sin(t * 5) * 0.4 : 0.05;
      if (p.group.userData.crack) p.group.userData.crack.visible = world.platesScanned;
    }

    // portão
    const g = this.gate;
    g.open += ((world.relayActive ? 1 : 0) - g.open) * (1 - Math.exp(-1.5 * dt));
    g.door.position.y = 1.8 - g.open * 3.9;
    g.col.enabled = g.open < 0.6;
    g.glyph.material.emissiveIntensity = world.relayActive ? 1.6 : 0.1;
    this.relay.gem.visible = true;
    this.relay.lever.rotation.z = world.relayActive ? 0.7 : 0;

    // atalho
    if (world.shortcutOpen) {
      this.shortcutT = Math.min(1, this.shortcutT + dt / (ctx.instant ? 0.001 : 3.2));
      this.shortcut.visible = true;
      const e = 1 - Math.pow(1 - this.shortcutT, 3);
      this.shortcut.position.y = lerp(-14, 0, e);
      this.shortcutCol.moveTo(-3.2, this.shortcut.position.y, this.bridgeZ);
      this.shortcutCol.enabled = this.shortcutT >= 1;
    }

    // ecos
    for (const e of this.echoes) {
      if (e.collected) { e.group.visible = false; continue; }
      e.group.rotation.y = t * 1.2;
      e.group.position.y = e.pos.y + Math.sin(t * 2 + e.pos.x) * 0.12;
    }
    const me = this.mainEcho;
    if (!me.recovered) {
      me.mesh.rotation.y = t * 0.8;
      me.mesh.position.y = me.base.y + Math.sin(t * 1.6) * 0.04;
    }
    this.ringMesh.rotation.z = t * 0.15;
    this.ringMesh.material.emissiveIntensity = world.echoRecovered ? 2.2 : 1.2 + Math.sin(t * 1.5) * 0.3;
    this.poolMesh.material.emissiveIntensity = world.rested ? 2 : 1.2 + Math.sin(t * 1.1) * 0.2;

    const sp = this.sanctuaryPulse;
    if (sp.t < 1) {
      sp.t = Math.min(1, sp.t + dt / 2.2);
      sp.mesh.visible = sp.t < 1;
      const r = lerp(1, 7.5, sp.t);
      sp.mesh.scale.set(r, r, 1);
      sp.mesh.material.opacity = 1 - sp.t;
    }
  }

  firePulse() { this.sanctuaryPulse.t = 0; }
}
