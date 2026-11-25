// Paleta da bíblia de arte (GDD 09) e materiais compartilhados.
import * as THREE from 'three';

export const PALETTE = Object.freeze({
  abismo: '#102331', // sombra / UI
  petroleo: '#297D83', // estrutura
  ceramica: '#E9D8AC', // superfície
  cobre: '#F3AB63', // interação
  ressonancia: '#7CF4DC', // energia
  salVivo: '#D36C55', // ameaça
  // apoio (derivados dos GLBs originais)
  areia: '#C79C76',
  areiaClara: '#D9B892',
  rocha: '#3E6672',
  rochaEscura: '#1C3A46',
  noite: '#0B1A24',
});

const cache = new Map();

/** Material fosco "cerâmico" low-poly. */
export function mat(key, opts = {}) {
  const id = key + JSON.stringify(opts);
  if (cache.has(id)) return cache.get(id);
  const color = PALETTE[key] || key;
  const m = new THREE.MeshStandardMaterial({
    color,
    roughness: opts.roughness ?? 0.88,
    metalness: opts.metalness ?? 0.0,
    flatShading: opts.flat ?? true,
    emissive: opts.emissive ? new THREE.Color(opts.emissive) : new THREE.Color(0x000000),
    emissiveIntensity: opts.emissiveIntensity ?? 1,
    transparent: !!opts.transparent,
    opacity: opts.opacity ?? 1,
    side: opts.side ?? THREE.FrontSide,
  });
  m.name = key;
  cache.set(id, m);
  return m;
}

/** Material de energia (turquesa luminosa, alimenta o bloom). */
export function glowMat(intensity = 1.6, color = PALETTE.ressonancia) {
  return mat(color, { emissive: color, emissiveIntensity: intensity, roughness: 0.4 });
}

/** Cristal: petróleo translúcido com brilho interno. */
export function crystalMat(variant = 0) {
  const tones = [
    { color: '#2FA3A0', emissive: PALETTE.ressonancia, ei: 0.35 },
    { color: '#58D6C4', emissive: PALETTE.ressonancia, ei: 0.55 },
    { color: '#1F6E78', emissive: '#2FA3A0', ei: 0.3 },
  ];
  const t = tones[variant % tones.length];
  return mat(t.color, { emissive: t.emissive, emissiveIntensity: t.ei, roughness: 0.35, metalness: 0.05 });
}
