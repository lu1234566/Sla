// PlayerController — movimento da Íris (GDD 03): velocidade inicial 4,5 m/s,
// salto com tolerância de borda (coyote + buffer + ledge assist), planar por
// até 3 s segurando o salto, esquiva curta com invulnerabilidade.
import { CharacterBody } from '../world/physics.js';

export const MOVE = {
  speed: 4.5,
  accelGround: 32,
  accelAir: 9,
  gravity: -14,
  jumpVel: 5.6,
  coyote: 0.14,
  buffer: 0.14,
  glideFall: 1.6,
  glideSpeed: 5.2,
  glideTime: 3.0,
  dodgeSpeed: 10,
  dodgeTime: 0.24,
  dodgeCooldown: 0.9,
};

export class PlayerController {
  constructor() {
    this.body = new CharacterBody({ radius: 0.32, height: 1.35, stepHeight: 0.45 });
    this.yaw = Math.PI;
    this.params = { ...MOVE };
    this.coyote = 0;
    this.buffer = 0;
    this.glideLeft = MOVE.glideTime;
    this.gliding = false;
    this.dodgeT = 0;
    this.dodgeCd = 0;
    this.dodgeDir = { x: 0, z: 1 };
    this.locked = 0; // segundos com controle travado (interação, cutscene)
    this.turnRate = 0;
    this.stepDist = 0;
    this.events = [];
  }

  setAssisted(on) {
    this.params.glideFall = on ? 1.1 : MOVE.glideFall;
    this.params.glideTime = on ? 4.0 : MOVE.glideTime;
    this.params.coyote = on ? 0.22 : MOVE.coyote;
    this.body.ledgeAssist = on ? 0.35 : 0.22;
  }

  get pos() { return this.body.pos; }
  get dodging() { return this.dodgeT > 0; }

  teleport(p, yaw = this.yaw) {
    Object.assign(this.body.pos, { x: p.x, y: p.y, z: p.z });
    Object.assign(this.body.vel, { x: 0, y: 0, z: 0 });
    this.body.grounded = false;
    this.body.ground = null;
    this.yaw = yaw;
    this.gliding = false;
    this.dodgeT = 0;
  }

  /**
   * @param {number} dt
   * @param {object} inp {move:{x,y}, camYaw, jumpPressed, jumpHeld, dodgePressed}
   * @param {PhysicsWorld} world
   */
  update(dt, inp, world) {
    const P = this.params, b = this.body, v = b.vel;
    this.events.length = 0;
    if (this.locked > 0) this.locked -= dt;
    const control = this.locked <= 0;

    // direção relativa à câmera
    const s = Math.sin(inp.camYaw), c = Math.cos(inp.camYaw);
    const mx = control ? inp.move.x : 0, my = control ? inp.move.y : 0;
    let dx = -s * my + c * mx;
    let dz = -c * my - s * mx;
    const mag = Math.min(1, Math.hypot(dx, dz));
    if (mag > 1e-3) { const l = Math.hypot(dx, dz); dx /= l; dz /= l; }

    // buffer de salto e coyote time
    if (control && inp.jumpPressed) this.buffer = P.buffer;
    else this.buffer = Math.max(0, this.buffer - dt);
    this.coyote = b.grounded ? P.coyote : Math.max(0, this.coyote - dt);

    // esquiva
    this.dodgeCd = Math.max(0, this.dodgeCd - dt);
    if (control && inp.dodgePressed && this.dodgeCd <= 0) {
      const fx = mag > 0.1 ? dx : Math.sin(this.yaw), fz = mag > 0.1 ? dz : Math.cos(this.yaw);
      this.dodgeDir = { x: fx, z: fz };
      this.dodgeT = P.dodgeTime;
      this.dodgeCd = P.dodgeCooldown;
      this.events.push('dodge');
    }

    // velocidade horizontal desejada
    let speed = P.speed * mag;
    let ax = dx * speed, az = dz * speed;
    if (this.dodgeT > 0) {
      this.dodgeT -= dt;
      ax = this.dodgeDir.x * P.dodgeSpeed;
      az = this.dodgeDir.z * P.dodgeSpeed;
    } else if (this.gliding) {
      // planar: avança na direção do olhar, guiado pela entrada
      const gx = mag > 0.1 ? dx : Math.sin(this.yaw), gz = mag > 0.1 ? dz : Math.cos(this.yaw);
      ax = gx * P.glideSpeed; az = gz * P.glideSpeed;
    }
    const accel = this.dodgeT > 0 ? 80 : b.grounded ? P.accelGround : this.gliding ? 6 : P.accelAir;
    const k = 1 - Math.exp(-accel * dt / P.speed);
    v.x += (ax - v.x) * k;
    v.z += (az - v.z) * k;

    // salto
    if (this.buffer > 0 && this.coyote > 0) {
      v.y = P.jumpVel;
      this.buffer = 0;
      this.coyote = 0;
      b.grounded = false;
      b.ground = null;
      this.events.push('jump');
    }
    // altura variável: soltar cedo corta o salto
    if (!inp.jumpHeld && v.y > 2.2 && !b.grounded) v.y = 2.2;

    // planar
    const wantGlide = control && inp.jumpHeld && !b.grounded && v.y < 0.5 && this.glideLeft > 0 && this.dodgeT <= 0;
    if (wantGlide && !this.gliding) this.events.push('glide');
    this.gliding = wantGlide;
    if (this.gliding) this.glideLeft -= dt;

    // integra com subpassos
    const steps = Math.ceil(dt / (1 / 120));
    const h = dt / steps;
    let landed = false;
    for (let i = 0; i < steps; i++) {
      const ev = b.step(world, h, P.gravity);
      if (this.gliding && v.y < -P.glideFall) v.y = -P.glideFall;
      if (ev.landed) landed = true;
      world.endFrame();
    }
    if (landed) { this.events.push('land'); this.glideLeft = P.glideTime; this.gliding = false; }
    if (b.grounded) this.glideLeft = P.glideTime;

    // orientação
    const hv = Math.hypot(v.x, v.z);
    const prevYaw = this.yaw;
    if (hv > 0.4 && (mag > 0.1 || this.dodgeT > 0 || this.gliding)) {
      const want = Math.atan2(v.x, v.z);
      let d = want - this.yaw;
      while (d > Math.PI) d -= Math.PI * 2;
      while (d < -Math.PI) d += Math.PI * 2;
      this.yaw += d * (1 - Math.exp(-14 * dt));
    }
    let dy = this.yaw - prevYaw;
    while (dy > Math.PI) dy -= Math.PI * 2;
    while (dy < -Math.PI) dy += Math.PI * 2;
    this.turnRate = dy / Math.max(dt, 1e-4);

    // passos
    if (b.grounded && hv > 0.5) {
      this.stepDist += hv * dt;
      if (this.stepDist > 0.62) { this.stepDist = 0; this.events.push('step'); }
    }
    this.speed = b.grounded ? hv : 0;
    return this.events;
  }
}
