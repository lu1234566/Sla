// Utilitários para transformar os GLBs originais (peças separadas, vértices já
// em coordenadas do mundo, sem pivôs) em hierarquias articuladas para animação
// procedural — o kit não tem rig, então criamos pivôs nas juntas.
import * as THREE from 'three';

/**
 * @param {THREE.Object3D} scene cena do GLB
 * @param {object} spec { pivotName: { at:[x,y,z], parent:'pivô'|null, match:(meshName)=>bool } }
 * Malhas não reivindicadas por nenhum pivô vão para o pivô `rootPivot`.
 * @returns {{root: THREE.Group, pivots: Record<string, THREE.Group>, meshes: Record<string, THREE.Mesh>}}
 */
export function buildRig(scene, spec, rootPivot) {
  const root = new THREE.Group();
  const pivots = {};
  const world = {};
  const order = Object.keys(spec);
  // cria pivôs na ordem (pais antes dos filhos)
  for (const name of order) {
    const def = spec[name];
    const g = new THREE.Group();
    g.name = name;
    pivots[name] = g;
    world[name] = new THREE.Vector3(...def.at);
    const parentWorld = def.parent ? world[def.parent] : new THREE.Vector3();
    g.position.copy(world[name]).sub(parentWorld);
    (def.parent ? pivots[def.parent] : root).add(g);
  }
  const meshes = {};
  const all = [];
  scene.traverse((o) => { if (o.isMesh) all.push(o); });
  for (const m of all) {
    const name = m.name || m.parent?.name || '';
    meshes[name] = m;
    let owner = rootPivot;
    // o pivô mais específico (último na ordem) que reivindica a malha vence
    for (const p of order) if (spec[p].match && spec[p].match(name)) owner = p;
    const mesh = m; // GLTFLoader: malha já sem transformação de nó (vértices em mundo)
    mesh.removeFromParent();
    mesh.position.copy(world[owner]).multiplyScalar(-1);
    mesh.rotation.set(0, 0, 0);
    mesh.scale.set(1, 1, 1);
    pivots[owner].add(mesh);
  }
  return { root, pivots, meshes };
}

/** Índice numérico no fim do nome da peça (ex.: "boot_007" -> 7). */
export const idx = (name) => parseInt((name.match(/_(\d+)$/) || [0, -1])[1], 10);

export const damp = (a, b, lambda, dt) => a + (b - a) * (1 - Math.exp(-lambda * dt));

export function dampAngle(a, b, lambda, dt) {
  let d = b - a;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return a + d * (1 - Math.exp(-lambda * dt));
}
