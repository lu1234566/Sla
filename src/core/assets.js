// Carregamento dos GLBs: os 4 modelos originais do kit de pré-produção e os
// modelos CC0 baixados (Quaternius), recoloridos com a paleta da bíblia de arte.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { mat, crystalMat, glowMat, PALETTE } from './palette.js';

const BASE = import.meta.env.BASE_URL + 'models/';
// O build "artifact" usa glTF JSON (.gltf.json) porque o host não serve .glb.
const EXT = import.meta.env.VITE_MODEL_EXT || '.glb';
const url = (file) => BASE + file.replace(/\.glb$/, EXT);

export const ORIGINALS = {
  iris: 'originais/01_iris_exploradora.glb',
  lume: 'originais/02_lume_drone.glb',
  guardian: 'originais/03_guardiao_de_sal.glb',
  sanctuary: 'originais/04_santuario_das_mares.glb',
};

// nome -> [arquivo, modo de recoloração]
export const PROPS = {
  crystal1: ['quaternius/rpg_items_pack/Crystal1.glb', 'crystal'],
  crystal1b: ['quaternius/rpg_items_pack/Crystal1_Damaged.glb', 'crystal'],
  crystal2: ['quaternius/rpg_items_pack/Crystal2.glb', 'crystal'],
  crystal2b: ['quaternius/rpg_items_pack/Crystal2_Damaged.glb', 'crystal'],
  crystal3: ['quaternius/rpg_items_pack/Crystal3.glb', 'crystal'],
  crystal5: ['quaternius/rpg_items_pack/Crystal5.glb', 'crystal'],
  gemBlue: ['quaternius/platformer_game_pack/Gem_Blue.glb', 'crystal'],
  gemPink: ['quaternius/platformer_game_pack/Gem_Pink.glb', 'glow'],
  rock1: ['quaternius/nature_pack/Rock_1.glb', 'rock'],
  rock2: ['quaternius/nature_pack/Rock_2.glb', 'rock'],
  rock3: ['quaternius/nature_pack/Rock_3.glb', 'rock'],
  rock4: ['quaternius/nature_pack/Rock_4.glb', 'rock'],
  rock5: ['quaternius/nature_pack/Rock_5.glb', 'rock'],
  rock6: ['quaternius/nature_pack/Rock_6.glb', 'rock'],
  rock7: ['quaternius/nature_pack/Rock_7.glb', 'rock'],
  stone1: ['quaternius/modular_dungeon_pack/Rock1.glb', 'rock'],
  stone2: ['quaternius/modular_dungeon_pack/Rock2.glb', 'rock'],
  stone3: ['quaternius/modular_dungeon_pack/Rock3.glb', 'rock'],
  stone4: ['quaternius/modular_dungeon_pack/Rock4.glb', 'rock'],
  stone5: ['quaternius/modular_dungeon_pack/Rock5.glb', 'rock'],
  rockCluster1: ['quaternius/real_time_strategy_pack/Resource_Rock_1.glb', 'rock'],
  rockCluster2: ['quaternius/real_time_strategy_pack/Resource_Rock_2.glb', 'rock'],
  column: ['quaternius/modular_dungeon_pack/Column.glb', 'ceramic'],
  columnBroken: ['quaternius/modular_dungeon_pack/Column_Broken.glb', 'ceramic'],
  columnBroken2: ['quaternius/modular_dungeon_pack/Column_Broken2.glb', 'ceramic'],
  pipeT: ['quaternius/platformer_game_pack/Pipe_T.glb', 'copper'],
  pipeStraight: ['quaternius/platformer_game_pack/Pipe_Straight.glb', 'copper'],
  pipe90: ['quaternius/platformer_game_pack/Pipe_90.glb', 'copper'],
  lever: ['quaternius/platformer_game_pack/Lever.glb', 'lever'],
  plant1: ['quaternius/nature_pack/Plant_1.glb', 'flora'],
  plant2: ['quaternius/nature_pack/Plant_2.glb', 'coral'],
  plant3: ['quaternius/nature_pack/Plant_3.glb', 'flora'],
  plant5: ['quaternius/nature_pack/Plant_5.glb', 'flora'],
};

const ROCK_TONES = { rocha: 'rocha', escura: 'rochaEscura', areia: 'areia', ceramica: 'ceramica', petroleo: 'petroleo' };

function recolor(root, mode, tone, variant) {
  let i = 0;
  root.traverse((o) => {
    if (!o.isMesh) return;
    const name = (o.material?.name || '').toLowerCase();
    let m;
    switch (mode) {
      case 'crystal': m = crystalMat(variant ?? i); break;
      case 'glow': m = glowMat(1.8); break;
      case 'rock': m = mat(ROCK_TONES[tone] || 'rocha'); break;
      case 'ceramic': m = mat(tone === 'areia' ? 'areiaClara' : 'ceramica'); break;
      case 'copper': m = mat('cobre', { metalness: 0.35, roughness: 0.45 }); break;
      case 'lever':
        m = name.includes('dark') ? mat('rochaEscura') : name.includes('lever') ? mat('cobre', { metalness: 0.35, roughness: 0.45 }) : mat('petroleo');
        break;
      case 'coral': m = mat(name.includes('wood') ? 'salVivo' : 'cobre'); break;
      case 'flora':
        if (name.includes('yellow')) m = mat('cobre');
        else if (name.includes('pink')) m = mat('salVivo');
        else if (name.includes('dark')) m = mat('#1F5D66');
        else m = mat(i % 2 ? '#2F8C8A' : PALETTE.petroleo);
        break;
      default: m = o.material;
    }
    o.material = m;
    o.castShadow = true;
    o.receiveShadow = true;
    i++;
  });
}

export class Assets {
  constructor() {
    this.loader = new GLTFLoader();
    this.originals = {};
    this.props = {};
    this.propOffsets = {};
  }

  async load(onProgress = () => {}) {
    const jobs = [
      ...Object.entries(ORIGINALS).map(([k, f]) => ['o', k, f]),
      ...Object.entries(PROPS).map(([k, [f]]) => ['p', k, f]),
    ];
    let done = 0;
    await Promise.all(jobs.map(async ([kind, key, file]) => {
      const gltf = await this.loader.loadAsync(url(file));
      if (kind === 'o') this.originals[key] = gltf.scene;
      else {
        this.props[key] = gltf.scene;
        const box = new THREE.Box3().setFromObject(gltf.scene);
        this.propOffsets[key] = { minY: box.min.y, size: box.getSize(new THREE.Vector3()), center: box.getCenter(new THREE.Vector3()) };
      }
      done++;
      onProgress(done / jobs.length);
    }));
    this.prepareOriginalMaterials();
  }

  /** Ajusta os materiais PBR de cor sólida dos GLBs originais para o visual cerâmico. */
  prepareOriginalMaterials() {
    const seen = new Set();
    for (const scene of Object.values(this.originals)) {
      scene.traverse((o) => {
        if (!o.isMesh) return;
        o.castShadow = true;
        o.receiveShadow = true;
        const m = o.material;
        if (seen.has(m)) return;
        seen.add(m);
        m.flatShading = true;
        m.metalness = 0;
        m.roughness = 0.85;
        if (m.name === 'gold') { m.metalness = 0.3; m.roughness = 0.5; }
        if (m.name === 'glow') { m.emissive = m.color.clone(); m.emissiveIntensity = 1.6; m.roughness = 0.4; }
        m.needsUpdate = true;
      });
    }
  }

  /**
   * Instância de um modelo baixado, com a base apoiada em y = 0.
   * @param {string} name chave de PROPS
   * @param {object} o {scale, tone, variant, height (altura-alvo em metros)}
   */
  prop(name, o = {}) {
    const src = this.props[name];
    if (!src) throw new Error(`prop desconhecido: ${name}`);
    const inner = src.clone(true);
    recolor(inner, PROPS[name][1], o.tone, o.variant);
    const off = this.propOffsets[name];
    let s = o.scale ?? 1;
    if (o.height) s = o.height / off.size.y;
    inner.position.set(-off.center.x * s, -off.minY * s, -off.center.z * s);
    inner.scale.setScalar(s);
    const g = new THREE.Group();
    g.name = name;
    g.add(inner);
    g.userData.size = off.size.clone().multiplyScalar(s);
    return g;
  }

  /** Clona um modelo original (materiais compartilhados entre instâncias). */
  original(key) {
    return this.originals[key].clone(true);
  }

  /** Material de um GLB original pelo nome (para dar coerência à geometria procedural). */
  originalMaterial(key, name) {
    let found = null;
    this.originals[key].traverse((o) => { if (!found && o.isMesh && o.material.name === name) found = o.material; });
    return found;
  }
}
