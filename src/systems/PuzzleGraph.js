// PuzzleGraph — regras puras (sem three.js) do puzzle composto do Jardim Mineral.
//
// O mesmo conjunto de predicados é usado pelo jogo (para ligar ponte, portão,
// cisterna e praça) e pelos testes automáticos de solvabilidade, que exploram
// todos os estados alcançáveis a partir de qualquer estado inicial da maré
// (GDD, "Validação de conteúdo": todo caminho crítico resolvível; sem bloqueio).

export const TIDE = Object.freeze({ HIGH: 'high', LOW: 'low' });

/** Estado inicial do mundo da fatia vertical. */
export function createWorldState(initialTide = TIDE.HIGH) {
  return {
    tide: initialTide,
    nodeScanned: false, // Íris escaneou um nó de ressonância
    conductorRotated: false, // condutor no fundo da cisterna girado
    platesScanned: false, // placas da praça escaneadas (a conectada foi revelada)
    relayActive: false, // relé remoto ativado por Lume
    echoRecovered: false, // eco principal recuperado no santuário
    shortcutOpen: false, // ponte de cerâmica permanente Cisterna <-> Jardim
    rested: false, // descansou/salvou no santuário (fim da fatia)
    reachedCistern: false,
    reachedGarden: false,
    reachedSanctuary: false,
    optionalEchoes: [], // ids dos ecos opcionais coletados
  };
}

// --- Predicados do mundo -------------------------------------------------------

/** Cisterna drenada (maré baixa) — escadas de cristal e condutor acessíveis. */
export const cisternDry = (s) => s.tide === TIDE.LOW;
/** Praça do jardim seca — placas expostas, guardião patrulha. */
export const plazaDry = (s) => s.tide === TIDE.LOW;
/** Ponte líquida atravessável: maré alta + condutor alimentando o emissor. */
export const liquidBridgeActive = (s) => s.tide === TIDE.HIGH && s.conductorRotated;
/** Portão do santuário aberto pelo relé. */
export const gateOpen = (s) => s.relayActive;
/** Guardião ativo: patrulha apenas o piso seco e só até ser pacificado. */
export const guardianActive = (s) => plazaDry(s) && !s.relayActive;
/** Plataformas de flutuação erguidas. */
export const floatersRaised = (s) => s.tide === TIDE.HIGH;

// --- Grafo abstrato de áreas (usado pelo validador) ----------------------------

export const AREAS = Object.freeze({
  ARRIVAL: 'chegada',
  CISTERN_TOP: 'cisterna',
  CISTERN_BOTTOM: 'fundo_cisterna',
  GARDEN: 'jardim',
  PLAZA: 'praca',
  SANCTUARY: 'santuario',
});

/** Áreas em que subir a maré afogaria Íris: o nó recusa ativar ali. */
export const UNSAFE_FOR_HIGH_TIDE = new Set([AREAS.CISTERN_BOTTOM, AREAS.PLAZA]);

/** Ligações entre áreas. `cond(s)` diz se a passagem existe no estado `s`. */
export const LINKS = [
  { from: AREAS.ARRIVAL, to: AREAS.CISTERN_TOP, cond: () => true, how: 'planar' },
  { from: AREAS.CISTERN_TOP, to: AREAS.CISTERN_BOTTOM, cond: cisternDry, how: 'escada de cristal' },
  { from: AREAS.CISTERN_BOTTOM, to: AREAS.CISTERN_TOP, cond: cisternDry, how: 'escada de cristal' },
  { from: AREAS.CISTERN_TOP, to: AREAS.GARDEN, cond: (s) => liquidBridgeActive(s) || s.shortcutOpen, how: 'ponte' },
  { from: AREAS.GARDEN, to: AREAS.CISTERN_TOP, cond: (s) => liquidBridgeActive(s) || s.shortcutOpen, how: 'ponte' },
  { from: AREAS.GARDEN, to: AREAS.PLAZA, cond: plazaDry, how: 'degraus' },
  { from: AREAS.PLAZA, to: AREAS.GARDEN, cond: () => true, how: 'degraus' },
  { from: AREAS.GARDEN, to: AREAS.SANCTUARY, cond: gateOpen, how: 'portão' },
  { from: AREAS.SANCTUARY, to: AREAS.GARDEN, cond: () => true, how: 'escadaria' },
];

/** Onde há nós de maré. */
export const TIDE_NODE_AREAS = new Set([AREAS.CISTERN_TOP, AREAS.GARDEN]);

/**
 * Ações possíveis numa área para um estado. Cada ação devolve um novo estado.
 * Espelha exatamente o que o jogo permite fazer.
 */
export function availableActions(area, s) {
  const acts = [];
  if (TIDE_NODE_AREAS.has(area)) {
    acts.push({ id: 'scan_node', apply: (x) => ({ ...x, nodeScanned: true }) });
    acts.push({
      id: 'toggle_tide',
      apply: (x) => ({ ...x, tide: x.tide === TIDE.HIGH ? TIDE.LOW : TIDE.HIGH }),
    });
  }
  if (area === AREAS.CISTERN_BOTTOM && cisternDry(s) && !s.conductorRotated) {
    acts.push({ id: 'rotate_conductor', apply: (x) => ({ ...x, conductorRotated: true }) });
  }
  if (area === AREAS.PLAZA && plazaDry(s)) {
    if (!s.platesScanned) acts.push({ id: 'scan_plates', apply: (x) => ({ ...x, platesScanned: true }) });
    if (s.platesScanned && !s.relayActive) acts.push({ id: 'activate_relay', apply: (x) => ({ ...x, relayActive: true }) });
  }
  if (area === AREAS.SANCTUARY) {
    if (!s.echoRecovered) acts.push({ id: 'recover_echo', apply: (x) => ({ ...x, echoRecovered: true, shortcutOpen: true }) });
    if (s.echoRecovered && !s.rested) acts.push({ id: 'rest', apply: (x) => ({ ...x, rested: true }) });
  }
  return acts;
}

export const isGoal = (s) => s.rested;

/** Chave canônica de um estado abstrato (área + flags relevantes). */
export function stateKey(area, s) {
  return [area, s.tide, +s.nodeScanned, +s.conductorRotated, +s.platesScanned, +s.relayActive, +s.echoRecovered, +s.shortcutOpen, +s.rested].join('|');
}

/** Sucessores de (área, estado): movimentos + ações. */
export function successors(area, s) {
  const out = [];
  for (const l of LINKS) if (l.from === area && l.cond(s)) out.push({ area: l.to, s, via: `ir:${l.to}` });
  for (const a of availableActions(area, s)) out.push({ area, s: a.apply(s), via: a.id });
  return out;
}

/** BFS por todo o espaço alcançável. Devolve mapa key -> {area, s, parent, via}. */
export function explore(startArea, startState) {
  const seen = new Map();
  const q = [{ area: startArea, s: startState, parent: null, via: 'início' }];
  seen.set(stateKey(startArea, startState), q[0]);
  while (q.length) {
    const cur = q.shift();
    for (const n of successors(cur.area, cur.s)) {
      const k = stateKey(n.area, n.s);
      if (!seen.has(k)) {
        const node = { area: n.area, s: n.s, parent: cur, via: n.via };
        seen.set(k, node);
        q.push(node);
      }
    }
  }
  return seen;
}

/** Caminho mais curto até o objetivo final (lista de passos) ou null. */
export function solve(startArea = AREAS.ARRIVAL, startState = createWorldState()) {
  const all = explore(startArea, startState);
  let best = null;
  for (const n of all.values()) if (isGoal(n.s)) { best = n; break; }
  if (!best) return null;
  const steps = [];
  for (let n = best; n; n = n.parent) steps.unshift(n.via);
  return steps;
}

// --- Objetivo atual (HUD + dicas) ----------------------------------------------

/**
 * Objetivo a mostrar. `area` é a área em que Íris está (pode ser null).
 * A ordem segue o roteiro da fatia: chegada, descoberta, travessia, guardião,
 * recompensa.
 */
export function currentObjective(s, area) {
  if (s.rested) return 'done';
  if (s.echoRecovered) return 'rest';
  if (s.relayActive) return s.reachedSanctuary ? 'recover_echo' : 'reach_sanctuary';
  if (s.reachedGarden || area === AREAS.GARDEN || area === AREAS.PLAZA) {
    if (!plazaDry(s)) return 'expose_plates';
    if (!s.platesScanned) return 'scan_plates';
    return 'activate_relay';
  }
  if (!s.reachedCistern && area !== AREAS.CISTERN_TOP && area !== AREAS.CISTERN_BOTTOM) return 'reach_cistern';
  if (!s.nodeScanned) return 'scan_node';
  if (!s.conductorRotated) return cisternDry(s) ? 'rotate_conductor' : 'lower_tide';
  if (area === AREAS.CISTERN_BOTTOM) return 'climb_out';
  if (!liquidBridgeActive(s)) return 'raise_tide';
  return 'cross_bridge';
}

/** Ordem do roteiro — usada para medir progresso e reiniciar o relógio das dicas. */
export const OBJECTIVE_ORDER = [
  'reach_cistern', 'scan_node', 'lower_tide', 'rotate_conductor', 'climb_out', 'raise_tide',
  'cross_bridge', 'expose_plates', 'scan_plates', 'activate_relay', 'reach_sanctuary',
  'recover_echo', 'rest', 'done',
];
