// Íris — rig procedural sobre o GLB original (01_iris_exploradora.glb).
// Altura-alvo no jogo: 1,35 m (GDD 06). Animações: idle, caminhada, corrida,
// salto, queda, planar, escaneamento, interação, esquiva e dano.
import * as THREE from 'three';
import { buildRig, idx, damp } from './rig.js';

export const IRIS_HEIGHT = 1.35;
const MODEL_HEIGHT = 3.23;

const left = (n) => idx(n) >= 0 && idx(n) < 7; // perna esquerda: 000..006
const right = (n) => idx(n) >= 7 && idx(n) <= 13;
const armLeft = (n) => idx(n) >= 20 && idx(n) <= 24;
const armRight = (n) => idx(n) >= 25 && idx(n) <= 29;

const SPEC = {
  hips: { at: [0, 1.5, 0], parent: null },
  torso: { at: [0, 1.62, 0], parent: 'hips', match: (n) => /^(torso|chest|core|neck|backpack|battery|shoulder)/.test(n) },
  head: { at: [0, 2.32, 0], parent: 'torso', match: (n) => /^(helmet|visor|eye_strip)/.test(n) },
  antenna: { at: [0.34, 2.86, -0.06], parent: 'head', match: (n) => /^antenna/.test(n) },
  armL: { at: [-0.6, 2.02, 0.02], parent: 'torso', match: (n) => /^arm_/.test(n) && armLeft(n) },
  foreL: { at: [-0.72, 1.64, 0.04], parent: 'armL', match: (n) => /^(elbow|gauntlet|hand)_/.test(n) && armLeft(n) },
  armR: { at: [0.6, 2.02, 0.02], parent: 'torso', match: (n) => /^arm_/.test(n) && armRight(n) },
  foreR: { at: [0.72, 1.64, 0.04], parent: 'armR', match: (n) => /^(elbow|gauntlet|hand)_/.test(n) && armRight(n) },
  legL: { at: [-0.22, 1.5, 0], parent: 'hips', match: (n) => /^thigh/.test(n) && left(n) },
  shinL: { at: [-0.25, 1.03, 0], parent: 'legL', match: (n) => /^(boot|sole|shin|knee)/.test(n) && left(n) },
  legR: { at: [0.22, 1.5, 0], parent: 'hips', match: (n) => /^thigh/.test(n) && right(n) },
  shinR: { at: [0.25, 1.03, 0], parent: 'legR', match: (n) => /^(boot|sole|shin|knee)/.test(n) && right(n) },
};

export class Iris {
  constructor(assets) {
    const { root, pivots, meshes } = buildRig(assets.original('iris'), SPEC, 'hips');
    this.pivots = pivots;
    this.object = new THREE.Group();
    this.object.name = 'Iris';
    root.scale.setScalar(IRIS_HEIGHT / MODEL_HEIGHT);
    this.object.add(root);
    this.model = root;
    this.base = {};
    for (const [k, p] of Object.entries(pivots)) this.base[k] = p.position.clone();

    // materiais próprios para o núcleo e o visor (brilho = integridade)
    this.coreMat = meshes.core_018.material.clone();
    meshes.core_018.material = this.coreMat;
    this.eyeMat = meshes.eye_strip_034.material.clone();
    meshes.eye_strip_034.material = this.eyeMat;
    this.hurtColor = new THREE.Color('#D36C55');
    this.okColor = new THREE.Color('#7CF4DC');

    this.phase = 0;
    this.t = 0;
    this.w = { move: 0, air: 0, glide: 0, scan: 0, interact: 0, dodge: 0, hurt: 0 };
    this.lean = 0;
  }

  /**
   * @param {number} dt
   * @param {object} s {speed, grounded, vy, gliding, scanning, interacting, dodging, hurt, integrity, turnRate}
   */
  update(dt, s) {
    this.t += dt;
    const P = this.pivots, w = this.w;
    const run = Math.min(1, s.speed / 4.5);
    w.move = damp(w.move, s.grounded ? run : 0, 10, dt);
    w.air = damp(w.air, s.grounded ? 0 : 1, 12, dt);
    w.glide = damp(w.glide, s.gliding ? 1 : 0, 8, dt);
    w.scan = damp(w.scan, s.scanning ? 1 : 0, 8, dt);
    w.interact = damp(w.interact, s.interacting ? 1 : 0, 10, dt);
    w.dodge = damp(w.dodge, s.dodging ? 1 : 0, 18, dt);
    w.hurt = damp(w.hurt, s.hurt ? 1 : 0, 10, dt);

    // passada proporcional à distância percorrida
    this.phase += dt * (s.speed / 1.15) * Math.PI;
    const ph = this.phase;
    const sw = Math.sin(ph), cw = Math.cos(ph);
    const idleB = Math.sin(this.t * 2.1);

    // pernas
    const stride = 0.75 * w.move;
    const airPose = w.air * (1 - w.glide);
    P.legL.rotation.x = -sw * stride + airPose * -0.55 + w.glide * 0.35 + w.dodge * -0.9;
    P.legR.rotation.x = sw * stride + airPose * 0.25 + w.glide * 0.5 + w.dodge * -0.9;
    P.shinL.rotation.x = Math.max(0, -cw) * 1.0 * w.move + airPose * 0.9 + w.glide * 0.3 + w.dodge * 1.4;
    P.shinR.rotation.x = Math.max(0, cw) * 1.0 * w.move + airPose * 0.4 + w.glide * 0.4 + w.dodge * 1.4;

    // braços (contrabalanço) + poses
    const armSwing = 0.6 * w.move;
    P.armL.rotation.x = sw * armSwing - airPose * 0.6 - w.interact * 1.2 - w.dodge * 0.6;
    P.armR.rotation.x = -sw * armSwing - airPose * 0.6 - w.interact * 1.2 - w.scan * 1.5 - w.dodge * 0.6;
    P.armL.rotation.z = -0.08 - w.glide * 1.25 - airPose * 0.35;
    P.armR.rotation.z = 0.08 + w.glide * 1.25 + airPose * 0.35 - w.scan * 0.2;
    P.foreL.rotation.x = -0.25 - 0.3 * w.move - w.interact * 0.3;
    P.foreR.rotation.x = -0.25 - 0.3 * w.move - w.interact * 0.3 - w.scan * 0.4;

    // tronco: respiração, balanço, inclinação no planar/esquiva
    const bob = Math.abs(sw) * 0.09 * w.move + idleB * 0.015 * (1 - w.move);
    P.hips.position.y = this.base.hips.y + bob - w.dodge * 0.35 - w.hurt * 0.1;
    P.hips.rotation.x = w.glide * 0.35 + w.dodge * 0.6 + w.move * 0.06 - w.hurt * 0.2;
    P.torso.rotation.y = sw * 0.12 * w.move;
    this.lean = damp(this.lean, -(s.turnRate || 0) * 0.08, 6, dt);
    P.hips.rotation.z = this.lean * (w.move + w.glide);

    // cabeça: olha em volta no idle, inclina ao escanear
    const look = (1 - w.move) * (1 - w.air);
    P.head.rotation.y = Math.sin(this.t * 0.45) * 0.35 * look;
    P.head.rotation.x = Math.sin(this.t * 0.7) * 0.06 * look - w.scan * 0.15 + w.glide * -0.25;
    P.head.rotation.z = w.scan * 0.18;
    P.antenna.rotation.x = Math.sin(this.t * 3.1) * 0.12 + w.move * 0.25 * Math.sin(ph * 2) - s.vy * 0.03;
    P.antenna.rotation.z = Math.sin(this.t * 2.3) * 0.08;

    // núcleo: indicador de energia (integridade) e pulso de escaneamento
    const integ = s.integrity ?? 3;
    const pulse = w.scan * (0.6 + 0.6 * Math.sin(this.t * 14));
    this.coreMat.emissiveIntensity = 0.4 + integ * 0.45 + pulse;
    const col = this.okColor.clone().lerp(this.hurtColor, Math.max(w.hurt, integ <= 1 ? 0.5 + 0.5 * Math.sin(this.t * 5) : 0));
    this.coreMat.emissive.copy(col);
    this.eyeMat.emissive.copy(col);
  }
}
