// Câmera em terceira pessoa: órbita com distância ajustável e colisão
// (GDD 03), mais trajetos cinematográficos (chegada e revelações).
import * as THREE from 'three';

export class CameraRig {
  constructor(camera) {
    this.camera = camera;
    this.yaw = 0; // 0 = câmera ao sul (+z) do alvo, olhando para o norte
    this.pitch = 0.32;
    this.dist = 6;
    this.targetDist = 6;
    this.actualDist = 6;
    this.focus = new THREE.Vector3();
    this.ray = new THREE.Raycaster();
    this.ray.firstHitOnly = true;
    this.reduceMotion = false;
    this.cine = null;
    this.shake = 0;
  }

  snapBehind(yaw, focus) {
    this.yaw = yaw + Math.PI;
    if (focus) this.focus.copy(focus);
  }

  /** Trajeto cinematográfico: pontos [{pos, look}], duração em s. */
  play(points, duration, onDone) {
    const curve = new THREE.CatmullRomCurve3(points.map((p) => p.pos));
    const looks = new THREE.CatmullRomCurve3(points.map((p) => p.look));
    this.cine = { curve, looks, t: 0, duration, onDone };
  }

  skip() {
    if (!this.cine) return;
    const cb = this.cine.onDone;
    this.cine = null;
    if (cb) cb();
  }

  get inCinematic() { return !!this.cine; }

  update(dt, look, target, blockers) {
    const cam = this.camera;
    if (this.cine) {
      const c = this.cine;
      c.t += dt / c.duration;
      const e = c.t < 1 ? 0.5 - 0.5 * Math.cos(Math.PI * Math.min(1, c.t)) : 1;
      cam.position.copy(c.curve.getPoint(e));
      cam.lookAt(c.looks.getPoint(e));
      if (c.t >= 1) this.skip();
      return;
    }
    this.yaw -= look.dx;
    this.pitch = THREE.MathUtils.clamp(this.pitch + look.dy, -0.35, 1.2);
    if (look.wheel) this.targetDist = THREE.MathUtils.clamp(this.targetDist + look.wheel * 0.6, 2.5, 10);
    this.dist += (this.targetDist - this.dist) * (1 - Math.exp(-10 * dt));

    // foco suavizado acima da cabeça da Íris
    const want = target.clone().add(new THREE.Vector3(0, 1.25, 0));
    const lag = this.reduceMotion ? 30 : 12;
    this.focus.x += (want.x - this.focus.x) * (1 - Math.exp(-lag * dt));
    this.focus.z += (want.z - this.focus.z) * (1 - Math.exp(-lag * dt));
    this.focus.y += (want.y - this.focus.y) * (1 - Math.exp(-(this.reduceMotion ? 30 : 7) * dt));

    const dir = new THREE.Vector3(
      Math.sin(this.yaw) * Math.cos(this.pitch),
      Math.sin(this.pitch),
      Math.cos(this.yaw) * Math.cos(this.pitch),
    );
    // colisão de câmera
    let d = this.dist;
    if (blockers && blockers.length) {
      this.ray.set(this.focus, dir);
      this.ray.far = this.dist + 0.4;
      const hits = this.ray.intersectObjects(blockers, true);
      if (hits.length) d = Math.max(0.9, Math.min(d, hits[0].distance - 0.35));
    }
    // aproxima rápido, afasta devagar
    this.actualDist += (d - this.actualDist) * (1 - Math.exp(-(d < this.actualDist ? 25 : 4) * dt));
    cam.position.copy(this.focus).addScaledVector(dir, this.actualDist);
    if (this.shake > 0 && !this.reduceMotion) {
      cam.position.x += (Math.random() - 0.5) * this.shake;
      cam.position.y += (Math.random() - 0.5) * this.shake;
      this.shake = Math.max(0, this.shake - dt * 1.5);
    }
    cam.lookAt(this.focus);
  }
}
