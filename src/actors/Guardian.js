// Guardião de Sal — autômato territorial de seis pernas (03_guardiao_de_sal.glb).
// GuardAI: máquina de estados sem combate letal (GDD 07 e 11): dormente (maré
// alta), patrulha (piso seco), alerta audiovisual, perseguição limitada,
// repouso e pacificado (núcleo reativado pelo relé).
import * as THREE from 'three';
import { buildRig, idx, damp, dampAngle } from './rig.js';

const legRange = (a, b) => (n) => /^(upper_leg|joint|lower_leg|foot)/.test(n) && idx(n) >= a && idx(n) <= b;
const SPEC = {
  body: { at: [0, 1.0, 0], parent: null },
  L1: { at: [-0.6, 1.04, 0.49], parent: 'body', match: legRange(5, 8) },
  L2: { at: [-0.6, 1.04, -0.02], parent: 'body', match: legRange(9, 12) },
  L3: { at: [-0.6, 1.04, -0.49], parent: 'body', match: legRange(13, 16) },
  R1: { at: [0.6, 1.04, 0.49], parent: 'body', match: legRange(20, 23) },
  R2: { at: [0.6, 1.04, -0.02], parent: 'body', match: legRange(24, 27) },
  R3: { at: [0.6, 1.04, -0.49], parent: 'body', match: legRange(28, 31) },
};
const TRIPOD_A = ['L1', 'L3', 'R2'];
const SCALE = 0.8;

export const GUARD_STATES = ['dormant', 'waking', 'patrol', 'alert', 'chase', 'rest', 'returning', 'pacified'];

export class Guardian {
  /**
   * @param {object} cfg {waypoints: Vector3[], perch: Vector3, floorY, perchY, covers: [{x,z,r}], inZone(pos)}
   */
  constructor(assets, cfg) {
    const { root, pivots, meshes } = buildRig(assets.original('guardian'), SPEC, 'body');
    this.pivots = pivots;
    this.object = new THREE.Group();
    this.object.name = 'GuardiaoDeSal';
    root.scale.setScalar(SCALE);
    this.object.add(root);
    this.eyeMat = meshes.eye_003.material.clone();
    meshes.eye_003.material = this.eyeMat;
    this.eyeMat.emissive = new THREE.Color('#D36C55');
    this.crystalMat = meshes.central_crystal_035.material.clone();
    meshes.central_crystal_035.material = this.crystalMat;
    this.threat = new THREE.Color('#D36C55');
    this.calm = new THREE.Color('#7CF4DC');
    this.light = new THREE.PointLight('#D36C55', 0, 6, 2);
    this.light.position.set(0, 1.0, 0.9);
    this.object.add(this.light);

    // cone de visão no chão (legibilidade: forma + cor, GDD 09/11)
    const half = THREE.MathUtils.degToRad(55);
    const coneGeo = new THREE.CircleGeometry(1, 24, -half, half * 2);
    coneGeo.rotateX(-Math.PI / 2); // setor no plano XZ, centrado em +X
    coneGeo.rotateY(-Math.PI / 2); // centraliza em +Z (frente do modelo)
    this.coneMat = new THREE.MeshBasicMaterial({ color: '#D36C55', transparent: true, opacity: 0.14, depthWrite: false });
    this.cone = new THREE.Mesh(coneGeo, this.coneMat);
    this.cone.renderOrder = 2;

    this.cfg = cfg;
    this.pos = cfg.perch.clone();
    this.yaw = Math.PI;
    this.state = 'dormant';
    this.timer = 0;
    this.wp = 0;
    this.gait = 0;
    this.speed = 0;
    this.t = 0;
    this.alertLevel = 0;
    this.params = { visionRange: 8.5, visionAngle: THREE.MathUtils.degToRad(55), alertTime: 0.75, chaseTime: 4, chaseSpeed: 4.3, patrolSpeed: 1.9, hearRadius: 2.0 };
    this.listeners = new Set();
  }

  on(fn) { this.listeners.add(fn); }
  emit(type, data) { for (const f of this.listeners) f(type, data); }

  setAssisted(on) {
    Object.assign(this.params, on
      ? { visionRange: 6.5, alertTime: 1.25, chaseTime: 2.8, chaseSpeed: 3.4 }
      : { visionRange: 8.5, alertTime: 0.75, chaseTime: 4, chaseSpeed: 4.3 });
  }

  setState(s) {
    if (this.state === s) return;
    const prev = this.state;
    this.state = s;
    this.timer = 0;
    this.emit('state', { state: s, prev });
  }

  /** Reinicia o encontro (falha do jogador ou recarregar). */
  reset(active) {
    this.timer = 0;
    if (this.state === 'pacified') return;
    if (active) {
      this.pos.copy(this.cfg.waypoints[0]);
      this.wp = 1;
      this.setState('patrol');
    } else {
      this.pos.copy(this.cfg.perch);
      this.setState('dormant');
    }
  }

  pacify() { this.setState('pacified'); }

  canSee(p) {
    const dx = p.x - this.pos.x, dz = p.z - this.pos.z;
    const dist = Math.hypot(dx, dz);
    if (dist < this.params.hearRadius) return true; // escuta quem encosta
    if (dist > this.params.visionRange) return false;
    const fwdX = Math.sin(this.yaw), fwdZ = Math.cos(this.yaw);
    const ang = Math.acos(Math.max(-1, Math.min(1, (dx * fwdX + dz * fwdZ) / (dist || 1))));
    if (ang > this.params.visionAngle) return false;
    // linha de visão bloqueada pelos cristais de cobertura
    for (const c of this.cfg.covers) {
      const t = Math.max(0, Math.min(1, ((c.x - this.pos.x) * dx + (c.z - this.pos.z) * dz) / (dist * dist)));
      const qx = this.pos.x + dx * t, qz = this.pos.z + dz * t;
      if (Math.hypot(c.x - qx, c.z - qz) < c.r) return false;
    }
    return true;
  }

  moveToward(target, speed, dt) {
    const dx = target.x - this.pos.x, dz = target.z - this.pos.z;
    const d = Math.hypot(dx, dz);
    if (d < 1e-3) return 0;
    const want = Math.atan2(dx, dz);
    this.yaw = dampAngle(this.yaw, want, 6, dt);
    const step = Math.min(d, speed * dt);
    // avança mais devagar enquanto ainda está virando
    let diff = Math.abs(((want - this.yaw + Math.PI * 3) % (Math.PI * 2)) - Math.PI);
    const k = Math.max(0.2, 1 - diff / 1.5);
    this.pos.x += (dx / d) * step * k;
    this.pos.z += (dz / d) * step * k;
    this.speed = speed * k;
    // mantém fora das coberturas
    for (const c of this.cfg.covers) {
      const ox = this.pos.x - c.x, oz = this.pos.z - c.z, od = Math.hypot(ox, oz), min = c.r + 0.9;
      if (od < min && od > 1e-4) { this.pos.x = c.x + (ox / od) * min; this.pos.z = c.z + (oz / od) * min; }
    }
    return d;
  }

  /**
   * @param {object} ctx {active (piso seco e não pacificado), player:{pos, dodging, inZone}}
   */
  update(dt, ctx) {
    this.t += dt;
    this.timer += dt;
    this.speed = 0;
    const P = this.params;
    const player = ctx.player;
    const playerTarget = player.inZone && !player.hidden;

    if (this.state !== 'pacified') {
      if (!ctx.active && !['dormant', 'waking'].includes(this.state)) this.setState('returning');
      if (ctx.active && (this.state === 'dormant' || this.state === 'returning')) this.setState('waking');
    }

    switch (this.state) {
      case 'dormant':
        this.pos.lerp(this.cfg.perch, 1 - Math.exp(-3 * dt));
        break;
      case 'waking': {
        const d = this.moveToward(this.cfg.waypoints[0], P.patrolSpeed, dt);
        if (d < 0.3) { this.wp = 1; this.setState('patrol'); }
        break;
      }
      case 'returning': {
        const d = this.moveToward(this.cfg.perch, P.patrolSpeed * 1.3, dt);
        if (d < 0.3) this.setState('dormant');
        break;
      }
      case 'patrol': {
        const wp = this.cfg.waypoints[this.wp];
        if (this.moveToward(wp, P.patrolSpeed, dt) < 0.25) this.wp = (this.wp + 1) % this.cfg.waypoints.length;
        if (playerTarget && this.canSee(player.pos)) { this.setState('alert'); this.emit('alert', {}); }
        break;
      }
      case 'alert': {
        const want = Math.atan2(player.pos.x - this.pos.x, player.pos.z - this.pos.z);
        this.yaw = dampAngle(this.yaw, want, 10, dt);
        if (!player.inZone) this.setState('rest');
        else if (this.timer > P.alertTime) { this.setState('chase'); this.emit('chase', {}); }
        break;
      }
      case 'chase': {
        this.moveToward(player.pos, P.chaseSpeed, dt);
        const dist = Math.hypot(player.pos.x - this.pos.x, player.pos.z - this.pos.z);
        if (dist < 1.25 && !player.dodging && player.inZone) {
          this.emit('hit', {});
          this.setState('rest');
        } else if (!player.inZone || this.timer > P.chaseTime) {
          this.emit('lost', {});
          this.setState('rest');
        }
        break;
      }
      case 'rest':
        if (this.timer > 2.2) {
          // retoma a patrulha pelo ponto mais próximo
          let best = 0, bd = Infinity;
          this.cfg.waypoints.forEach((w, i) => { const d = w.distanceTo(this.pos); if (d < bd) { bd = d; best = i; } });
          this.wp = best;
          this.setState('patrol');
        }
        break;
      case 'pacified':
        if (this.moveToward(this.cfg.perch, P.patrolSpeed, dt) < 0.3) this.yaw = dampAngle(this.yaw, Math.PI, 2, dt);
        break;
      default:
    }

    // altura: sobre o poleiro quando dormente/pacificado, no piso seco quando ativo
    const onPerch = Math.hypot(this.pos.x - this.cfg.perch.x, this.pos.z - this.cfg.perch.z) < 1.6;
    const targetY = onPerch ? this.cfg.perch.y : this.cfg.floorY;
    this.pos.y = damp(this.pos.y, targetY, 6, dt);
    this.animate(dt);
  }

  animate(dt) {
    const P = this.pivots;
    const moving = Math.min(1, this.speed / 2);
    this.gait += dt * (2 + this.speed * 2.6);
    const resting = this.state === 'dormant' || this.state === 'rest' || this.state === 'pacified';
    for (const leg of ['L1', 'L2', 'L3', 'R1', 'R2', 'R3']) {
      const phase = this.gait + (TRIPOD_A.includes(leg) ? 0 : Math.PI);
      const s = leg[0] === 'L' ? -1 : 1;
      const lift = Math.max(0, Math.sin(phase)) * 0.35 * moving;
      P[leg].rotation.y = Math.cos(phase) * 0.35 * moving * s;
      P[leg].rotation.z = s * lift + (resting ? s * -0.18 : 0);
    }
    const alertShake = this.state === 'alert' ? Math.sin(this.t * 40) * 0.03 : 0;
    P.body.position.y = 1.0 + (resting ? -0.22 : 0) + Math.abs(Math.sin(this.gait)) * 0.05 * moving;
    P.body.rotation.z = alertShake;
    P.body.rotation.x = this.state === 'chase' ? 0.12 : 0;
    this.object.position.copy(this.pos);
    this.object.rotation.y = this.yaw;

    // núcleo: coral = ameaça (pulsos lentos), turquesa = pacificado
    const hostile = this.state !== 'pacified';
    const awake = !['dormant', 'pacified'].includes(this.state);
    let intensity = hostile ? (awake ? 0.8 + 0.4 * Math.sin(this.t * 2.2) : 0.25) : 1.4;
    if (this.state === 'alert') intensity = 2.5 + Math.sin(this.t * 30);
    if (this.state === 'chase') intensity = 2.0;
    this.alertLevel = damp(this.alertLevel, this.state === 'alert' || this.state === 'chase' ? 1 : 0, 6, dt);
    const col = hostile ? this.threat : this.calm;
    this.eyeMat.emissive.copy(col);
    this.eyeMat.color.copy(col);
    this.eyeMat.emissiveIntensity = intensity;
    this.crystalMat.emissive.copy(col);
    this.crystalMat.emissiveIntensity = intensity * 0.8;
    this.light.color.copy(col);
    this.light.intensity = awake || !hostile ? intensity * 3 : 0.5;

    // cone de visão
    const showCone = ['patrol', 'alert', 'chase'].includes(this.state);
    this.cone.visible = showCone;
    if (showCone) {
      const r = this.params.visionRange;
      this.cone.position.set(this.pos.x, this.cfg.floorY + 0.03, this.pos.z);
      this.cone.scale.set(r, 1, r);
      this.cone.rotation.y = this.yaw;
      this.coneMat.opacity = 0.12 + this.alertLevel * 0.18;
    }
  }
}
