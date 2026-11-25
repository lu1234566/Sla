// SaveManager — save local versionado, com gravação atômica e backup
// (GDD 13 / Dados e persistência). Funciona com localStorage ou com qualquer
// objeto {getItem,setItem,removeItem} (os testes usam um armazenamento em memória).

export const SAVE_VERSION = 2;
const PREFIX = 'mare-de-vidro';

/** Hash FNV-1a de 32 bits, suficiente para detectar saves truncados/corrompidos. */
export function checksum(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, '0');
}

/** Armazenamento em memória (fallback quando localStorage não existe ou falha). */
export class MemoryStorage {
  constructor() { this.map = new Map(); }
  getItem(k) { return this.map.has(k) ? this.map.get(k) : null; }
  setItem(k, v) { this.map.set(k, String(v)); }
  removeItem(k) { this.map.delete(k); }
}

function safeStorage() {
  try {
    const s = globalThis.localStorage;
    const probe = `${PREFIX}.probe`;
    s.setItem(probe, '1');
    s.removeItem(probe);
    return s;
  } catch {
    return new MemoryStorage();
  }
}

/** Migrações de versões antigas do save. */
const MIGRATIONS = {
  1: (d) => ({ ...d, stats: d.stats || { time: 0, falls: 0, hits: 0, hints: 0, tideToggles: 0 } }),
};

export class SaveManager {
  constructor(storage = safeStorage(), slot = 1) {
    this.storage = storage;
    this.slot = slot;
  }

  key(kind) { return `${PREFIX}.slot${this.slot}.${kind}`; }

  wrap(data) {
    const payload = JSON.stringify({ ...data, version: SAVE_VERSION, savedAt: Date.now() });
    return JSON.stringify({ sum: checksum(payload), payload });
  }

  unwrap(raw) {
    if (!raw) return null;
    try {
      const { sum, payload } = JSON.parse(raw);
      if (typeof payload !== 'string' || checksum(payload) !== sum) return null;
      let data = JSON.parse(payload);
      while (data.version < SAVE_VERSION && MIGRATIONS[data.version]) {
        data = { ...MIGRATIONS[data.version](data), version: data.version + 1 };
      }
      if (data.version !== SAVE_VERSION) return null;
      return data;
    } catch {
      return null;
    }
  }

  /**
   * Grava de forma atômica: escreve em `tmp`, valida a leitura, move o save
   * atual para `bak` e só então promove o novo para `main`.
   */
  save(data) {
    try {
      const wrapped = this.wrap(data);
      this.storage.setItem(this.key('tmp'), wrapped);
      if (!this.unwrap(this.storage.getItem(this.key('tmp')))) throw new Error('falha ao validar save temporário');
      const current = this.storage.getItem(this.key('main'));
      if (current && this.unwrap(current)) this.storage.setItem(this.key('bak'), current);
      this.storage.setItem(this.key('main'), wrapped);
      this.storage.removeItem(this.key('tmp'));
      return true;
    } catch (err) {
      console.warn('[SaveManager] não foi possível salvar:', err);
      return false;
    }
  }

  /** Carrega o save principal; se estiver corrompido, recorre ao backup. */
  load() {
    const main = this.unwrap(this.storage.getItem(this.key('main')));
    if (main) return { data: main, source: 'main' };
    const bak = this.unwrap(this.storage.getItem(this.key('bak')));
    if (bak) return { data: bak, source: 'backup' };
    return null;
  }

  has() { return !!this.load(); }

  clear() {
    for (const k of ['main', 'bak', 'tmp']) this.storage.removeItem(this.key(k));
  }
}

/** Opções do jogador (separadas dos slots). */
export class OptionsStore {
  constructor(storage = safeStorage()) { this.storage = storage; this.k = `${PREFIX}.options`; }
  load(defaults) {
    try { return { ...defaults, ...(JSON.parse(this.storage.getItem(this.k)) || {}) }; } catch { return { ...defaults }; }
  }
  save(opts) { try { this.storage.setItem(this.k, JSON.stringify(opts)); } catch { /* sem persistência */ } }
}
