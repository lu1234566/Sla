import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TideManager, HoldToConfirm, TIDE_RULES, REFUSAL } from '../../src/systems/TideManager.js';
import { SaveManager, MemoryStorage, SAVE_VERSION, checksum } from '../../src/systems/SaveManager.js';
import { TIDE, createWorldState } from '../../src/systems/PuzzleGraph.js';

const run = (tm, seconds, step = 1 / 60) => { for (let t = 0; t < seconds; t += step) tm.update(step); };

test('maré: transição de 2,5 s e cooldown de 5 s', () => {
  const tm = new TideManager(TIDE.HIGH);
  assert.equal(tm.level, 1);
  assert.equal(tm.toggle().ok, true);
  assert.equal(tm.state, TIDE.LOW);
  run(tm, TIDE_RULES.TRANSITION_TIME * 0.5);
  assert.ok(tm.level > 0.2 && tm.level < 0.8, `nível no meio: ${tm.level}`);
  assert.equal(tm.toggle().reason, REFUSAL.TRANSITIONING);
  run(tm, TIDE_RULES.TRANSITION_TIME * 0.5 + 0.05);
  assert.equal(tm.level, 0);
  assert.equal(tm.toggle().reason, REFUSAL.COOLDOWN);
  run(tm, TIDE_RULES.COOLDOWN + 0.05);
  assert.equal(tm.toggle().ok, true);
});

test('maré: não sobe com Íris em volume inseguro, mas pode baixar', () => {
  const low = new TideManager(TIDE.LOW);
  assert.equal(low.toggle({ playerUnsafe: true }).reason, REFUSAL.UNSAFE);
  const high = new TideManager(TIDE.HIGH);
  assert.equal(high.toggle({ playerUnsafe: true }).ok, true);
});

test('confirmação exige segurar 1 s e dispara uma vez', () => {
  const h = new HoldToConfirm();
  let fired = 0;
  for (let i = 0; i < 50; i++) fired += h.update(1 / 60, true) ? 1 : 0; // 0,83 s
  assert.equal(fired, 0);
  for (let i = 0; i < 120; i++) fired += h.update(1 / 60, true) ? 1 : 0;
  assert.equal(fired, 1);
  h.update(1 / 60, false);
  assert.equal(h.ratio, 0);
});

test('save: grava, carrega e preserva estado do mundo', () => {
  const sm = new SaveManager(new MemoryStorage());
  const world = { ...createWorldState(TIDE.LOW), conductorRotated: true };
  assert.ok(sm.save({ checkpoint: 'jardim', world, echoes: ['eco_flutuante'] }));
  const { data, source } = sm.load();
  assert.equal(source, 'main');
  assert.equal(data.version, SAVE_VERSION);
  assert.equal(data.checkpoint, 'jardim');
  assert.equal(data.world.tide, TIDE.LOW);
  assert.equal(data.world.conductorRotated, true);
});

test('save: save corrompido recorre ao backup', () => {
  const store = new MemoryStorage();
  const sm = new SaveManager(store);
  sm.save({ checkpoint: 'chegada' });
  sm.save({ checkpoint: 'jardim' });
  store.setItem(sm.key('main'), store.getItem(sm.key('main')).slice(0, 40)); // trunca
  const { data, source } = sm.load();
  assert.equal(source, 'backup');
  assert.equal(data.checkpoint, 'chegada');
});

test('save: rejeita checksum inválido e migra versão 1', () => {
  const store = new MemoryStorage();
  const sm = new SaveManager(store);
  const payload = JSON.stringify({ version: 1, checkpoint: 'chegada' });
  store.setItem(sm.key('main'), JSON.stringify({ sum: 'deadbeef', payload }));
  assert.equal(sm.load(), null, 'checksum inválido deve ser rejeitado');
  store.setItem(sm.key('main'), JSON.stringify({ sum: checksum(payload), payload }));
  const loaded = sm.load();
  assert.equal(loaded.data.version, SAVE_VERSION);
  assert.equal(loaded.data.checkpoint, 'chegada');
  assert.ok(loaded.data.stats, 'migração v1 -> v2 cria estatísticas');
});
