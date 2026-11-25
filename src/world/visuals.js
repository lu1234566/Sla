// Céu, estrelas, planeta crescente, oceano suspenso, ilhas distantes e
// construtores de geometria low-poly (ilhas facetadas e água luminosa).
import * as THREE from 'three';
import { mat, PALETTE } from '../core/palette.js';

// --- Água luminosa (oceano, cisterna, praça e ponte líquida) -------------------

const waterVert = /* glsl */`
  #include <common>
  #include <fog_pars_vertex>
  varying vec3 vWorld;
  varying vec3 vNormalW;
  uniform float uTime;
  uniform float uWave;
  void main() {
    vec4 wp = modelMatrix * vec4(position, 1.0);
    wp.y += sin(wp.x * 0.35 + uTime * 0.9) * uWave + cos(wp.z * 0.27 + uTime * 0.7) * uWave;
    vWorld = wp.xyz;
    vNormalW = normalize(mat3(modelMatrix) * normal);
    vec4 mvPosition = viewMatrix * wp;
    gl_Position = projectionMatrix * mvPosition;
    #include <fog_vertex>
  }
`;

const waterFrag = /* glsl */`
  #include <common>
  #include <fog_pars_fragment>
  varying vec3 vWorld;
  varying vec3 vNormalW;
  uniform float uTime;
  uniform vec3 uDeep;
  uniform vec3 uShallow;
  uniform vec3 uGlow;
  uniform float uOpacity;
  uniform float uStreaks;
  uniform float uScale;
  uniform vec2 uFlow;
  uniform float uEnergy;
  float h1(float n) { return fract(sin(n * 91.345) * 47453.5453); }
  void main() {
    vec2 p = vWorld.xz * uScale;
    vec2 q = p + uFlow * uTime;
    // faixas de luz horizontais, quebradas (como na concept art)
    float row = floor(q.y * 1.6);
    float r = h1(row);
    float x = q.x * (0.25 + r * 0.25) + uTime * (0.08 + r * 0.25) + r * 37.0;
    float dash = step(0.62 + r * 0.25, fract(x));
    float thin = smoothstep(0.16, 0.0, abs(fract(q.y * 1.6) - 0.5));
    float streak = dash * thin * uStreaks;
    float caust = 0.5 + 0.5 * sin(q.x * 1.7 + uTime * 1.3) * sin(q.y * 1.3 - uTime * 1.1);
    vec3 col = mix(uDeep, uShallow, 0.35 + 0.3 * caust);
    col += uGlow * (streak * 0.9 + uEnergy * (0.25 + 0.35 * caust));
    float edge = 1.0 - abs(vNormalW.y);
    col += uGlow * edge * 0.4 * uEnergy;
    gl_FragColor = vec4(col, uOpacity);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
    #include <fog_fragment>
  }
`;

export function waterMaterial(o = {}) {
  return new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([
      THREE.UniformsLib.fog,
      {
        uTime: { value: 0 },
        uDeep: { value: new THREE.Color(o.deep || '#0E3A47') },
        uShallow: { value: new THREE.Color(o.shallow || '#1E6670') },
        uGlow: { value: new THREE.Color(o.glow || PALETTE.ressonancia) },
        uOpacity: { value: o.opacity ?? 0.85 },
        uStreaks: { value: o.streaks ?? 1 },
        uScale: { value: o.scale ?? 1 },
        uFlow: { value: new THREE.Vector2(...(o.flow || [0, 0])) },
        uEnergy: { value: o.energy ?? 0.15 },
        uWave: { value: o.wave ?? 0.03 },
      },
    ]),
    vertexShader: waterVert,
    fragmentShader: waterFrag,
    transparent: (o.opacity ?? 0.85) < 1,
    depthWrite: o.depthWrite ?? false,
    fog: true,
    side: o.side ?? THREE.FrontSide,
  });
}

// --- Ilhas facetadas -----------------------------------------------------------

/** Converte polígono [x,z] em THREE.Shape (coordenada y da forma = -z). */
function toShape(poly, ShapeClass = THREE.Shape) {
  const s = new ShapeClass();
  poly.forEach(([x, z], i) => (i ? s.lineTo(x, -z) : s.moveTo(x, -z)));
  s.closePath();
  return s;
}

function jitter(geo, amount, seed = 1, keepTop = true) {
  const pos = geo.attributes.position;
  const rnd = mulberry(seed);
  const map = new Map();
  for (let i = 0; i < pos.count; i++) {
    const key = `${pos.getX(i).toFixed(3)},${pos.getY(i).toFixed(3)},${pos.getZ(i).toFixed(3)}`;
    if (!map.has(key)) map.set(key, [(rnd() - 0.5) * amount, (rnd() - 0.5) * amount, (rnd() - 0.5) * amount]);
    const j = map.get(key);
    if (keepTop && pos.getY(i) > -0.01) continue;
    pos.setXYZ(i, pos.getX(i) + j[0], pos.getY(i) + j[1] * 0.6, pos.getZ(i) + j[2]);
  }
  geo.computeVertexNormals();
  return geo;
}

export function mulberry(a) {
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Ilha flutuante: laje com topo de areia (com furos opcionais) e raiz rochosa
 * invertida e facetada, como na concept art.
 * @param {object} o {poly:[[x,z]] (relativo ao centro), holes:[poly], top, thickness, rootDepth, seed, topMat, sideMat, rootMat}
 */
export function buildIsland(o) {
  const g = new THREE.Group();
  const shape = toShape(o.poly);
  for (const h of o.holes || []) shape.holes.push(toShape([...h].reverse(), THREE.Path));
  const thick = o.thickness ?? 1.2;
  const geo = new THREE.ExtrudeGeometry(shape, { depth: thick, bevelEnabled: false });
  geo.rotateX(-Math.PI / 2);
  geo.translate(0, (o.top ?? 0) - thick, 0);
  const slab = new THREE.Mesh(geo, [o.topMat || mat('areia'), o.sideMat || mat('rocha')]);
  slab.receiveShadow = true;
  slab.castShadow = true;
  g.add(slab);

  // raiz: cone invertido facetado
  let r = 0;
  for (const [x, z] of o.poly) r = Math.max(r, Math.hypot(x, z));
  const depth = o.rootDepth ?? r * 0.9;
  const seg = o.poly.length >= 6 ? o.poly.length : 7;
  const root = new THREE.ConeGeometry(r * 0.96, depth, seg, 3, false);
  root.rotateX(Math.PI);
  root.rotateY(Math.PI / seg);
  root.translate(0, (o.top ?? 0) - thick - depth / 2 + 0.01, 0);
  jitter(root.toNonIndexed ? root : root, r * 0.12, o.seed || 7, false);
  const rootMesh = new THREE.Mesh(root, o.rootMat || mat('rochaEscura'));
  rootMesh.castShadow = true;
  g.add(rootMesh);
  g.userData.radius = r;
  return g;
}

// --- Céu -----------------------------------------------------------------------

export function buildSky(scene) {
  const sky = new THREE.Mesh(
    new THREE.SphereGeometry(600, 32, 16),
    new THREE.ShaderMaterial({
      side: THREE.BackSide,
      depthWrite: false,
      fog: false,
      uniforms: { uTop: { value: new THREE.Color('#081620') }, uMid: { value: new THREE.Color('#143645') }, uHorizon: { value: new THREE.Color('#1B4250') } },
      vertexShader: 'varying vec3 vDir; void main(){ vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: `varying vec3 vDir; uniform vec3 uTop; uniform vec3 uMid; uniform vec3 uHorizon;
        void main(){ float h = vDir.y; vec3 c = mix(uHorizon, uMid, smoothstep(-0.05, 0.18, h)); c = mix(c, uTop, smoothstep(0.18, 0.75, h));
        gl_FragColor = vec4(c, 1.0);
        #include <colorspace_fragment>
        }`,
    }),
  );
  sky.renderOrder = -10;
  scene.add(sky);

  // estrelas
  const rnd = mulberry(42);
  const n = 1400;
  const pos = new Float32Array(n * 3);
  const col = new Float32Array(n * 3);
  const c1 = new THREE.Color(PALETTE.ceramica), c2 = new THREE.Color(PALETTE.ressonancia);
  for (let i = 0; i < n; i++) {
    const u = rnd() * Math.PI * 2, v = 0.04 + rnd() * 0.96;
    const y = Math.pow(v, 0.8);
    const rr = Math.sqrt(1 - y * y);
    pos.set([Math.cos(u) * rr * 560, y * 560, Math.sin(u) * rr * 560], i * 3);
    const c = rnd() < 0.15 ? c2 : c1;
    const b = 0.4 + rnd() * 0.6;
    col.set([c.r * b, c.g * b, c.b * b], i * 3);
  }
  const sg = new THREE.BufferGeometry();
  sg.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  sg.setAttribute('color', new THREE.BufferAttribute(col, 3));
  const stars = new THREE.Points(sg, new THREE.PointsMaterial({ size: 1.6, sizeAttenuation: false, vertexColors: true, fog: false, depthWrite: false }));
  stars.renderOrder = -9;
  scene.add(stars);

  // planeta crescente (lado escuro visível, como na concept art)
  const moonMat = new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    fog: false,
    uniforms: { uLit: { value: new THREE.Color('#E8B878') }, uDark: { value: new THREE.Color('#183B4C') } },
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
    fragmentShader: `varying vec2 vUv; uniform vec3 uLit; uniform vec3 uDark;
      void main(){ vec2 p = vUv * 2.0 - 1.0; float d = length(p); if (d > 1.0) discard;
      float shadow = length(p - vec2(0.32, 0.2)) - 0.93;
      vec3 c = shadow < 0.0 ? uDark : uLit;
      float rim = smoothstep(1.0, 0.97, d);
      gl_FragColor = vec4(c, rim);
      #include <colorspace_fragment>
      }`,
  });
  const moon = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), moonMat);
  moon.scale.setScalar(150);
  moon.position.set(-240, 150, -420);
  moon.lookAt(0, 0, 0);
  moon.renderOrder = -8;
  scene.add(moon);
  return { sky, stars, moon };
}

/** Oceano suspenso abaixo do arquipélago. */
export function buildOcean(scene) {
  const m = waterMaterial({ deep: '#0B2E39', shallow: '#154A55', opacity: 1, streaks: 0.45, scale: 0.09, energy: 0.04, wave: 0.25, depthWrite: true });
  const ocean = new THREE.Mesh(new THREE.PlaneGeometry(2400, 2400, 64, 64), m);
  ocean.rotation.x = -Math.PI / 2;
  ocean.position.y = -34;
  scene.add(ocean);
  return ocean;
}

/** Ilhas distantes com pilares: marcos no horizonte. */
export function buildDistantIslands(scene) {
  const group = new THREE.Group();
  const rnd = mulberry(1234);
  const spots = [
    [-95, -6, -140, 16], [70, -2, -170, 20], [150, -10, -60, 18], [-160, -12, -30, 22],
    [-120, -4, 90, 15], [120, -8, 110, 17], [10, 4, -230, 24], [-40, -14, 190, 18], [210, -6, -150, 20],
  ];
  const topM = mat('#3B6B72');
  const sideM = mat('#244955');
  const pillarM = mat('#2C5862');
  for (const [x, y, z, r] of spots) {
    const n = 6 + Math.floor(rnd() * 3);
    const poly = [];
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + rnd() * 0.3;
      const rr = r * (0.8 + rnd() * 0.3);
      poly.push([Math.cos(a) * rr, Math.sin(a) * rr]);
    }
    const isl = buildIsland({ poly, top: 0, thickness: 1.5, rootDepth: r * 1.1, seed: Math.floor(rnd() * 1000), topMat: topM, sideMat: sideM, rootMat: sideM });
    const pillars = 2 + Math.floor(rnd() * 3);
    for (let i = 0; i < pillars; i++) {
      const h = r * (0.6 + rnd() * 0.9);
      const w = r * 0.12;
      const pm = new THREE.Mesh(new THREE.BoxGeometry(w, h, w), pillarM);
      pm.position.set((rnd() - 0.5) * r, h / 2, (rnd() - 0.5) * r * 0.8);
      isl.add(pm);
    }
    isl.position.set(x, y, z);
    isl.userData.bob = rnd() * 10;
    isl.traverse((o) => { o.castShadow = false; o.receiveShadow = false; });
    group.add(isl);
  }
  scene.add(group);
  return group;
}
