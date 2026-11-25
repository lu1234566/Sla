// Lume — drone companheiro (02_lume_drone.glb). Segue Íris sem colisão,
// marca pontos, escaneia e leva o sinal até relés distantes (GDD 07).
import * as THREE from 'three';
import { buildRig, idx, damp } from './rig.js';

const SPEC = {
  body: { at: [0, 0, 0], parent: null },
  wingL: { at: [-0.4, 0.12, 0], parent: 'body', match: (n) => /^wing/.test(n) && idx(n) >= 5 && idx(n) <= 7 },
  wingR: { at: [0.4, 0.12, 0], parent: 'body', match: (n) => /^wing/.test(n) && idx(n) >= 8 && idx(n) <= 10 },
  lens: { at: [0, 0.02, 0.52], parent: 'body', match: (n) => /^lens/.test(n) },
  antenna: { at: [0.03, 0.34, 0], parent: 'body', match: (n) => /^antenna/.test(n) },
};

const SCALE = 0.24;

export class Lume {
  constructor(assets) {
    const { root, pivots, meshes } = buildRig(assets.original('lume'), SPEC, 'body');
    this.pivots = pivots;
    this.object = new THREE.Group();
    this.object.name = 'Lume';
    root.scale.setScalar(SCALE);
    this.object.add(root);
    this.lensMat = meshes.lens_003.material.clone();
    meshes.lens_003.material = this.lensMat;
    this.light = new THREE.PointLight('#7CF4DC', 2.5, 5, 2);
    this.light.position.set(0, 0, 0.15);
    this.object.add(this.light);

    this.pos = new THREE.Vector3();
    this.vel = new THREE.Vector3();
    this.yaw = 0;
    this.t = 0;
    this.mode = 'follow';
    this.target = null; // Vector3 ao marcar/voar até relé
    this.onArrive = null;
    this.pulse = 0;
  }

  place(p) { this.pos.copy(p); this.object.position.copy(p); }

  /** Voa até um ponto e paira; chama onArrive ao chegar. */
  flyTo(point, onArrive = null) {
    this.mode = 'travel';
    this.target = point.clone();
    this.onArrive = onArrive;
  }

  follow() { this.mode = 'follow'; this.target = null; this.onArrive = null; }

  scanPulse() { this.pulse = 1; }

  /**
   * @param {number} dt
   * @param {THREE.Vector3} irisPos pés da Íris
   * @param {number} irisYaw
   * @param {THREE.Vector3} camPos posição da câmera (Lume olha para o jogador quando fala)
   */
  update(dt, irisPos, irisYaw, camPos) {
    this.t += dt;
    let goal;
    if (this.mode === 'follow') {
      const side = new THREE.Vector3(0.75, 1.85 + Math.sin(this.t * 1.7) * 0.08, -0.35);
      side.applyAxisAngle(new THREE.Vector3(0, 1, 0), irisYaw);
      goal = irisPos.clone().add(side);
    } else {
      goal = this.target.clone();
      goal.y += Math.sin(this.t * 2) * 0.1;
    }
    // mola amortecida (sem colisão bloqueante, GDD)
    const k = this.mode === 'follow' ? 18 : 10;
    const toGoal = goal.clone().sub(this.pos);
    this.vel.addScaledVector(toGoal, k * dt);
    this.vel.multiplyScalar(Math.exp(-(this.mode === 'follow' ? 7 : 4.5) * dt));
    const maxV = this.mode === 'travel' ? 9 : 14;
    if (this.vel.length() > maxV) this.vel.setLength(maxV);
    this.pos.addScaledVector(this.vel, dt);
    if (this.mode === 'travel' && toGoal.length() < 0.35) {
      this.mode = 'hover';
      const cb = this.onArrive; this.onArrive = null;
      if (cb) cb();
    }

    // orientação: na direção do movimento, ou olhando para a câmera ao pairar
    const flat = new THREE.Vector2(this.vel.x, this.vel.z);
    let targetYaw = this.yaw;
    if (flat.length() > 0.6) targetYaw = Math.atan2(this.vel.x, this.vel.z);
    else if (camPos) targetYaw = Math.atan2(camPos.x - this.pos.x, camPos.z - this.pos.z);
    let d = targetYaw - this.yaw;
    while (d > Math.PI) d -= Math.PI * 2;
    while (d < -Math.PI) d += Math.PI * 2;
    this.yaw += d * (1 - Math.exp(-5 * dt));

    this.object.position.copy(this.pos);
    this.object.rotation.set(Math.max(-0.4, Math.min(0.4, flat.length() * 0.05)), this.yaw, -d * 0.3);

    // asas, lente e antena
    const flap = Math.sin(this.t * 18) * 0.12;
    this.pivots.wingL.rotation.z = -0.1 + flap;
    this.pivots.wingR.rotation.z = 0.1 - flap;
    this.pivots.lens.rotation.z += dt * (1.5 + this.pulse * 12);
    this.pivots.antenna.rotation.x = Math.sin(this.t * 3) * 0.15;
    this.pulse = damp(this.pulse, 0, 2.5, dt);
    this.lensMat.emissiveIntensity = 1.4 + this.pulse * 3;
    this.light.intensity = 2.5 + this.pulse * 10;
  }
}
