import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PhysicsWorld, PrismCollider, CharacterBody, boxPoly, ngonPoly } from '../../src/world/physics.js';

const G = -14;
const sim = (world, body, seconds, vx = 0, vz = 0) => {
  const dt = 1 / 120;
  for (let t = 0; t < seconds; t += dt) {
    body.vel.x = vx; body.vel.z = vz;
    body.step(world, dt, G);
    world.endFrame();
  }
};

function floorWorld() {
  const w = new PhysicsWorld();
  w.add(new PrismCollider(ngonPoly(10, 8), -2, 0, { tags: { safe: true } }));
  return w;
}

test('personagem pousa no chão e fica parado', () => {
  const w = floorWorld();
  const b = new CharacterBody();
  b.pos = { x: 0, y: 2, z: 0 };
  sim(w, b, 1.5);
  assert.equal(b.grounded, true);
  assert.ok(Math.abs(b.pos.y) < 1e-6);
});

test('sobe degrau baixo, é bloqueado por parede alta', () => {
  const w = floorWorld();
  w.add(new PrismCollider(boxPoly(4, 4), 0, 0.4, { x: 3.5 })); // degrau 0,4 m (x 1,5..5,5)
  w.add(new PrismCollider(boxPoly(2, 4), 0, 1.2, { x: -2 })); // muro 1,2 m
  const b = new CharacterBody();
  b.pos = { x: 0, y: 0, z: 0 };
  sim(w, b, 0.6, 4.5, 0);
  assert.ok(Math.abs(b.pos.y - 0.4) < 1e-6, `deveria subir no degrau: y=${b.pos.y}`);
  b.pos = { x: 0, y: 0, z: 0 };
  sim(w, b, 1, -4.5, 0);
  assert.ok(b.pos.x > -1 - b.radius - 1e-3, `atravessou o muro: x=${b.pos.x}`);
  assert.ok(Math.abs(b.pos.y) < 1e-6);
});

test('cai pela borda da ilha', () => {
  const w = floorWorld();
  const b = new CharacterBody();
  b.pos = { x: 9, y: 0, z: 0 };
  sim(w, b, 1, 4.5, 0);
  assert.equal(b.grounded, false);
  assert.ok(b.pos.y < -1);
});

test('plataforma móvel carrega o personagem', () => {
  const w = new PhysicsWorld();
  const plat = w.add(new PrismCollider(boxPoly(3, 3), -0.5, 0, {}));
  const b = new CharacterBody();
  b.pos = { x: 0, y: 0.01, z: 0 };
  sim(w, b, 0.3);
  assert.equal(b.grounded, true);
  const dt = 1 / 120;
  for (let i = 0; i < 120; i++) {
    plat.moveTo(0, plat.yMax + 1.5 * dt, 0);
    b.vel.x = 0; b.vel.z = 0;
    b.step(w, dt, G);
    w.endFrame();
  }
  assert.ok(Math.abs(b.pos.y - plat.yMax) < 0.02, `y=${b.pos.y} plat=${plat.yMax}`);
  assert.equal(b.grounded, true);
});

test('pulo cobre ~4 m e planar é necessário para vãos maiores', () => {
  const w = new PhysicsWorld();
  w.add(new PrismCollider(boxPoly(4, 4), -1, 1, { x: 0 }));
  const b = new CharacterBody();
  b.pos = { x: 1.6, y: 1, z: 0 };
  sim(w, b, 0.1);
  b.vel.y = 5.6;
  sim(w, b, 0.9, 4.5, 0);
  assert.ok(b.pos.x > 4.5 && b.pos.x < 7.5, `alcance ${b.pos.x}`);
});
