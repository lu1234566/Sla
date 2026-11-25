// Validação de conteúdo (GDD 13): estados e pré-condições do puzzle composto.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  AREAS, TIDE, createWorldState, explore, solve, isGoal, successors, stateKey,
  liquidBridgeActive, guardianActive, currentObjective, OBJECTIVE_ORDER, UNSAFE_FOR_HIGH_TIDE,
} from '../../src/systems/PuzzleGraph.js';

for (const tide of [TIDE.HIGH, TIDE.LOW]) {
  test(`fatia é concluível com maré inicial ${tide}`, () => {
    const steps = solve(AREAS.ARRIVAL, createWorldState(tide));
    assert.ok(steps, 'sem solução');
    for (const must of ['rotate_conductor', 'scan_plates', 'activate_relay', 'recover_echo', 'rest']) {
      assert.ok(steps.includes(must), `solução não passa por ${must}: ${steps.join(' > ')}`);
    }
  });

  test(`nenhum estado alcançável é beco sem saída (maré inicial ${tide})`, () => {
    const all = explore(AREAS.ARRIVAL, createWorldState(tide));
    // Estados a partir dos quais o objetivo é alcançável: busca reversa por ponto fixo.
    const canWin = new Set();
    let changed = true;
    for (const [k, n] of all) if (isGoal(n.s)) canWin.add(k);
    while (changed) {
      changed = false;
      for (const [k, n] of all) {
        if (canWin.has(k)) continue;
        if (successors(n.area, n.s).some((x) => canWin.has(stateKey(x.area, x.s)))) { canWin.add(k); changed = true; }
      }
    }
    const stuck = [...all.keys()].filter((k) => !canWin.has(k));
    assert.deepEqual(stuck, [], `estados sem saída: ${stuck.slice(0, 5).join(', ')}`);
  });
}

test('cada nó de maré opera nos dois estados', () => {
  for (const area of [AREAS.CISTERN_TOP, AREAS.GARDEN]) {
    for (const tide of [TIDE.HIGH, TIDE.LOW]) {
      const s = createWorldState(tide);
      const next = successors(area, s).find((x) => x.via === 'toggle_tide');
      assert.ok(next, `nó em ${area} não alterna a partir de ${tide}`);
      assert.notEqual(next.s.tide, tide);
    }
  }
});

test('nós não ficam em volumes inseguros', () => {
  for (const area of UNSAFE_FOR_HIGH_TIDE) {
    const acts = successors(area, createWorldState(TIDE.LOW)).map((x) => x.via);
    assert.ok(!acts.includes('toggle_tide'), `há nó de maré em área insegura ${area}`);
  }
});

test('ponte líquida exige maré alta e condutor', () => {
  const s = createWorldState(TIDE.HIGH);
  assert.equal(liquidBridgeActive(s), false);
  assert.equal(liquidBridgeActive({ ...s, conductorRotated: true }), true);
  assert.equal(liquidBridgeActive({ ...s, conductorRotated: true, tide: TIDE.LOW }), false);
});

test('guardião só patrulha piso seco e é pacificado pelo relé', () => {
  const s = createWorldState(TIDE.LOW);
  assert.equal(guardianActive(s), true);
  assert.equal(guardianActive({ ...s, tide: TIDE.HIGH }), false);
  assert.equal(guardianActive({ ...s, relayActive: true }), false);
});

test('objetivo avança na ordem do roteiro ao seguir a solução', () => {
  let s = createWorldState(TIDE.HIGH);
  const seen = [currentObjective(s, AREAS.ARRIVAL)];
  assert.equal(seen[0], 'reach_cistern');
  s = { ...s, reachedCistern: true };
  const flow = [
    [{ nodeScanned: true }, AREAS.CISTERN_TOP, 'lower_tide'],
    [{ tide: TIDE.LOW }, AREAS.CISTERN_TOP, 'rotate_conductor'],
    [{ conductorRotated: true }, AREAS.CISTERN_BOTTOM, 'climb_out'],
    [{}, AREAS.CISTERN_TOP, 'raise_tide'],
    [{ tide: TIDE.HIGH }, AREAS.CISTERN_TOP, 'cross_bridge'],
    [{ reachedGarden: true }, AREAS.GARDEN, 'expose_plates'],
    [{ tide: TIDE.LOW }, AREAS.PLAZA, 'scan_plates'],
    [{ platesScanned: true }, AREAS.PLAZA, 'activate_relay'],
    [{ relayActive: true }, AREAS.GARDEN, 'reach_sanctuary'],
    [{ reachedSanctuary: true }, AREAS.SANCTUARY, 'recover_echo'],
    [{ echoRecovered: true }, AREAS.SANCTUARY, 'rest'],
    [{ rested: true }, AREAS.SANCTUARY, 'done'],
  ];
  let last = OBJECTIVE_ORDER.indexOf('scan_node');
  for (const [patch, area, expected] of flow) {
    s = { ...s, ...patch };
    const obj = currentObjective(s, area);
    assert.equal(obj, expected);
    const idx = OBJECTIVE_ORDER.indexOf(obj);
    assert.ok(idx > last, `objetivo regrediu: ${obj}`);
    last = idx;
  }
});
