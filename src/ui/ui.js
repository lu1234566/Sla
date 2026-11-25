// Interface (DOM): HUD mínima (GDD 10) e menus de início, pausa, opções,
// controles, diário, créditos e tela final. Navegável por teclado e gamepad.
import { t, LANGUAGES } from '../i18n.js';

function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (v === true) el.setAttribute(k, '');
    else if (v !== false && v != null) el.setAttribute(k, v);
  }
  for (const c of children.flat(Infinity)) if (c != null) el.append(c.nodeType ? c : document.createTextNode(c));
  return el;
}

const TIDE_ICON = {
  high: '<svg viewBox="0 0 32 32" aria-hidden="true"><path d="M3 12c3-3 6-3 9 0s6 3 9 0 6-3 8 0" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/><path d="M3 19c3-3 6-3 9 0s6 3 9 0 6-3 8 0" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/><path d="M16 9V3m0 0-3 3m3-3 3 3" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><rect x="3" y="24" width="26" height="4" rx="1" fill="currentColor" opacity=".55"/></svg>',
  low: '<svg viewBox="0 0 32 32" aria-hidden="true"><path d="M3 24c3-3 6-3 9 0s6 3 9 0 6-3 8 0" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/><path d="M16 5v8m0 0-3-3m3 3 3-3" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><rect x="3" y="16" width="7" height="3" rx="1" fill="currentColor" opacity=".55"/><rect x="22" y="16" width="7" height="3" rx="1" fill="currentColor" opacity=".55"/></svg>',
};

export class UI {
  constructor(root) {
    this.root = root;
    this.screen = null;
    this.buildHud();
    this.fadeEl = h('div', { id: 'fade' });
    this.loadingEl = h('div', { id: 'loading', class: 'screen' },
      h('div', { class: 'brand' }, h('h1', {}, 'MARÉ DE VIDRO'), h('p', { class: 'tagline' }, '')),
      h('div', { class: 'bar' }, h('b')),
      h('p', { class: 'loading-text' }, ''));
    this.menuEl = h('div', { id: 'menu', class: 'screen', hidden: true });
    root.append(this.hudEl, this.fadeEl, this.loadingEl, this.menuEl);
    this.subtitleTimer = 0;
    this.toastTimer = 0;
    addEventListener('keydown', (e) => {
      if (this.menuEl.hidden) return;
      if (e.code === 'ArrowDown' || e.code === 'KeyS') { this.navigate(1); e.preventDefault(); }
      if (e.code === 'ArrowUp' || e.code === 'KeyW') { this.navigate(-1); e.preventDefault(); }
    });
  }

  // --- carregamento -------------------------------------------------------------

  setLoading(p) {
    this.loadingEl.querySelector('.bar b').style.width = `${Math.round(p * 100)}%`;
    this.loadingEl.querySelector('.loading-text').textContent = `${t('loading')} ${Math.round(p * 100)}%`;
    this.loadingEl.querySelector('.tagline').textContent = t('tagline');
  }
  hideLoading() { this.loadingEl.hidden = true; }

  // --- HUD ------------------------------------------------------------------------

  buildHud() {
    this.hudEl = h('div', { id: 'hud', hidden: true });
    this.integrityEl = h('div', { class: 'panel integrity', role: 'status' },
      h('span', { class: 'label' }, ''), h('span', { class: 'pips' }, h('i'), h('i'), h('i')));
    this.tideEl = h('div', { class: 'panel tide', role: 'status' },
      h('span', { class: 'icon' }), h('span', { class: 'tide-text' }, ''), h('span', { class: 'tide-bar' }, h('b')));
    this.echoEl = h('div', { class: 'echo-count' }, '');
    this.objectiveEl = h('div', { class: 'panel objective' },
      h('span', { class: 'label' }, ''), h('span', { class: 'goal' }, ''), h('span', { class: 'obj-text' }, ''));
    this.promptEl = h('div', { class: 'prompt', hidden: true }, h('kbd'), h('span', { class: 'ptext' }), h('span', { class: 'hold' }, h('b')));
    this.subtitleEl = h('div', { class: 'subtitle', hidden: true, 'aria-live': 'polite' }, h('b', {}, 'Lume'), h('span'));
    this.labelsEl = h('div', { class: 'labels' });
    this.toastEl = h('div', { class: 'toast', hidden: true }, h('h3'), h('p'));
    this.skipEl = h('div', { class: 'skip', hidden: true }, '');
    this.titleCard = h('div', { class: 'title-card', hidden: true }, h('h1'), h('p'));
    this.hudEl.append(this.integrityEl, this.tideEl, this.echoEl, this.objectiveEl, this.labelsEl, this.subtitleEl, this.promptEl, this.toastEl, this.skipEl, this.titleCard);
  }

  showHud(on) { this.hudEl.hidden = !on; }
  setHudMinimal(on) { this.hudEl.classList.toggle('cinematic', on); }

  refreshStatic() {
    this.integrityEl.querySelector('.label').textContent = t('hud.iris');
    this.objectiveEl.querySelector('.label').textContent = t('hud.objective');
    this.objectiveEl.querySelector('.goal').textContent = t('hud.goal');
    this.skipEl.textContent = t('skip');
    this._tideKey = null;
  }

  setIntegrity(n) {
    if (this._integ === n) return;
    const hurt = this._integ !== undefined && n < this._integ;
    this._integ = n;
    [...this.integrityEl.querySelectorAll('i')].forEach((el, i) => el.classList.toggle('off', i >= n));
    if (hurt) { this.integrityEl.classList.remove('flash'); void this.integrityEl.offsetWidth; this.integrityEl.classList.add('flash'); }
  }

  /** state: 'high'|'low' (alvo), transitioning, progress 0..1, cooldown 0..1 */
  setTide(state, transitioning, progress, cooldown) {
    const key = transitioning ? (state === 'high' ? 'hud.tideRising' : 'hud.tideFalling') : state === 'high' ? 'hud.tideHigh' : 'hud.tideLow';
    if (key !== this._tideKey) {
      this._tideKey = key;
      this.tideEl.querySelector('.tide-text').textContent = t(key);
      this.tideEl.querySelector('.icon').innerHTML = TIDE_ICON[state];
      this.tideEl.classList.toggle('low', state === 'low');
      this.tideEl.classList.remove('pulse'); void this.tideEl.offsetWidth; this.tideEl.classList.add('pulse');
    }
    const bar = this.tideEl.querySelector('.tide-bar');
    bar.hidden = !(transitioning || cooldown > 0);
    bar.querySelector('b').style.width = `${Math.round((transitioning ? progress : 1 - cooldown) * 100)}%`;
    bar.classList.toggle('cooldown', !transitioning);
  }

  setEchoes(n, total) {
    const s = t('hud.echoes', { n, total });
    if (this.echoEl.textContent !== s) this.echoEl.textContent = s;
  }

  setObjective(key) {
    if (this._obj === key) return;
    this._obj = key;
    const el = this.objectiveEl.querySelector('.obj-text');
    el.textContent = t('obj.' + key);
    this.objectiveEl.classList.remove('new'); void this.objectiveEl.offsetWidth; this.objectiveEl.classList.add('new');
  }

  /** text: chave já traduzida; key: tecla; hold 0..1 (barra de segurar). */
  setPrompt(text, key = '', hold = 0, disabled = false) {
    if (!text) { this.promptEl.hidden = true; this._prompt = null; return; }
    this.promptEl.hidden = false;
    if (this._prompt !== text + key) {
      this._prompt = text + key;
      this.promptEl.querySelector('kbd').textContent = key;
      this.promptEl.querySelector('.ptext').textContent = text;
    }
    this.promptEl.classList.toggle('disabled', disabled);
    const holdEl = this.promptEl.querySelector('.hold');
    holdEl.hidden = hold <= 0;
    holdEl.querySelector('b').style.width = `${Math.round(hold * 100)}%`;
  }

  say(text, seconds = 4.5, speaker = 'Lume', force = false) {
    if (!this.subtitlesOn && !force) return;
    this.subtitleEl.hidden = false;
    this.subtitleEl.querySelector('b').textContent = speaker;
    this.subtitleEl.querySelector('span').textContent = text;
    this.subtitleTimer = seconds;
  }

  toast(title, text, seconds = 7) {
    this.toastEl.hidden = false;
    this.toastEl.querySelector('h3').textContent = title;
    this.toastEl.querySelector('p').textContent = text;
    this.toastTimer = seconds;
  }

  titleCardShow(title, sub, on = true) {
    this.titleCard.hidden = !on;
    if (on) { this.titleCard.querySelector('h1').textContent = title; this.titleCard.querySelector('p').textContent = sub; }
  }

  showSkip(on) { this.skipEl.hidden = !on; }

  /** labels: [{x, y, text, kind, visible}] em pixels de tela. */
  setLabels(labels) {
    const el = this.labelsEl;
    while (el.children.length < labels.length) el.append(h('div', { class: 'tag' }));
    [...el.children].forEach((c, i) => {
      const l = labels[i];
      if (!l) { c.hidden = true; return; }
      c.hidden = false;
      c.textContent = l.text;
      c.className = `tag ${l.kind}`;
      c.style.transform = `translate(${l.x}px, ${l.y}px) translate(-50%, -100%)`;
      c.style.opacity = l.alpha;
    });
  }

  update(dt) {
    if (this.subtitleTimer > 0) { this.subtitleTimer -= dt; if (this.subtitleTimer <= 0) this.subtitleEl.hidden = true; }
    if (this.toastTimer > 0) { this.toastTimer -= dt; if (this.toastTimer <= 0) this.toastEl.hidden = true; }
  }

  fade(to, seconds = 0.4) {
    this.fadeEl.style.transition = `opacity ${seconds}s ease`;
    this.fadeEl.style.opacity = to;
    return new Promise((r) => setTimeout(r, seconds * 1000));
  }

  applyOptions(o) {
    document.documentElement.style.setProperty('--ui-scale', o.textSize);
    document.body.classList.toggle('high-contrast', !!o.highContrast);
    this.subtitlesOn = o.subtitles;
    if (!o.subtitles) this.subtitleEl.hidden = true;
  }

  // --- menus ----------------------------------------------------------------------

  get menuOpen() { return !this.menuEl.hidden; }

  open(panel, cls = '') {
    this.menuEl.innerHTML = '';
    this.menuEl.className = `screen ${cls}`;
    this.menuEl.append(panel);
    this.menuEl.hidden = false;
    const first = this.menuEl.querySelector('button:not([disabled]), input, select');
    if (first) first.focus({ preventScroll: true });
  }

  close() { this.menuEl.hidden = true; this.menuEl.innerHTML = ''; }

  navigate(dir) {
    const items = [...this.menuEl.querySelectorAll('button:not([disabled]), input, select')];
    if (!items.length) return;
    const i = items.indexOf(document.activeElement);
    items[(i + dir + items.length) % items.length].focus();
  }

  activate() {
    const el = document.activeElement;
    if (el && this.menuEl.contains(el)) el.click();
  }

  button(label, onclick, o = {}) {
    return h('button', { class: o.primary ? 'primary' : '', onclick, disabled: o.disabled }, label);
  }

  mainMenu({ save, onContinue, onNew, onOptions, onControls, onCredits }) {
    const panel = h('div', { class: 'menu-panel main' },
      h('p', { class: 'eyebrow' }, t('subtitle')),
      h('h1', {}, 'MARÉ DE VIDRO'),
      h('p', { class: 'tagline' }, t('tagline')),
      h('nav', {},
        save ? this.button(t('menu.continue'), onContinue, { primary: true }) : null,
        this.button(t('menu.new'), onNew, { primary: !save }),
        this.button(t('menu.options'), onOptions),
        this.button(t('menu.controls'), onControls),
        this.button(t('menu.credits'), onCredits)),
      save ? h('p', { class: 'save-info' }, save) : null);
    this.open(panel, 'main');
  }

  pauseMenu({ onResume, onJournal, onOptions, onControls, onCheckpoint, onQuit }) {
    this.open(h('div', { class: 'menu-panel' },
      h('h2', {}, t('menu.paused')),
      h('nav', {},
        this.button(t('menu.resume'), onResume, { primary: true }),
        this.button(t('menu.journal'), onJournal),
        this.button(t('menu.options'), onOptions),
        this.button(t('menu.controls'), onControls),
        this.button(t('menu.restartCheckpoint'), onCheckpoint),
        this.button(t('menu.quit'), onQuit))), 'pause');
  }

  optionsMenu(opts, onChange, onBack) {
    const row = (label, control, help) => h('label', { class: 'opt' }, h('span', {}, label), control, help ? h('small', {}, help) : null);
    const toggle = (key) => h('button', { class: `toggle ${opts[key] ? 'on' : ''}`, 'aria-pressed': String(!!opts[key]), onclick: (e) => { opts[key] = !opts[key]; e.currentTarget.classList.toggle('on', opts[key]); e.currentTarget.setAttribute('aria-pressed', String(opts[key])); e.currentTarget.textContent = opts[key] ? t('opt.on') : t('opt.off'); onChange(opts, key); } }, opts[key] ? t('opt.on') : t('opt.off'));
    const range = (key, min, max, step) => h('input', { type: 'range', min, max, step, value: opts[key], oninput: (e) => { opts[key] = +e.target.value; onChange(opts, key); } });
    const select = (key, choices) => {
      const s = h('select', { onchange: (e) => { opts[key] = e.target.value; onChange(opts, key); } }, choices.map(([v, l]) => h('option', { value: v, selected: String(opts[key]) === String(v) }, l)));
      return s;
    };
    this.open(h('div', { class: 'menu-panel options' },
      h('h2', {}, t('menu.options')),
      h('div', { class: 'opts' },
        row(t('opt.language'), select('language', LANGUAGES)),
        row(t('opt.assisted'), toggle('assisted'), t('opt.assistedHelp')),
        row(t('opt.hints'), toggle('hints')),
        row(t('opt.subtitles'), toggle('subtitles')),
        row(t('opt.textSize'), select('textSize', [['1', '100%'], ['1.2', '120%'], ['1.4', '140%']])),
        row(t('opt.highContrast'), toggle('highContrast')),
        row(t('opt.reduceMotion'), toggle('reduceMotion')),
        row(t('opt.bloom'), toggle('bloom')),
        row(t('opt.quality'), select('quality', [['high', t('opt.qualityHigh')], ['low', t('opt.qualityLow')]])),
        row(t('opt.sensitivity'), range('sensitivity', 0.3, 2.5, 0.1)),
        row(t('opt.invertY'), toggle('invertY')),
        row(t('opt.master'), range('master', 0, 1, 0.05)),
        row(t('opt.music'), range('music', 0, 1, 0.05)),
        row(t('opt.sfx'), range('sfx', 0, 1, 0.05))),
      h('nav', {}, this.button(t('menu.back'), onBack, { primary: true }))), 'sub');
  }

  controlsMenu(onBack) {
    const rows = [
      ['WASD', 'L', 'controls.move'], ['Mouse', 'R', 'controls.camera'], [t('key.jump'), 'A', 'controls.jump'],
      ['E', 'X', 'controls.interact'], ['Q', 'Y', 'controls.tide'], ['R', 'RB', 'controls.scan'],
      ['Shift', 'B', 'controls.dodge'], ['Scroll', '—', 'controls.zoom'], ['Esc', 'Start', 'controls.pause'],
    ];
    this.open(h('div', { class: 'menu-panel' },
      h('h2', {}, t('controls.title')),
      h('table', { class: 'controls' }, rows.map(([k, p, l]) => h('tr', {}, h('td', {}, h('kbd', {}, k)), h('td', {}, h('kbd', { class: 'pad' }, p)), h('td', {}, t(l))))),
      h('nav', {}, this.button(t('menu.back'), onBack, { primary: true }))), 'sub');
  }

  creditsMenu(onBack) {
    this.open(h('div', { class: 'menu-panel' },
      h('h2', {}, t('menu.credits')),
      h('p', { class: 'body' }, t('credits.body')),
      h('nav', {}, this.button(t('menu.back'), onBack, { primary: true }))), 'sub');
  }

  journalMenu(entries, onBack) {
    this.open(h('div', { class: 'menu-panel journal' },
      h('h2', {}, t('journal.title')),
      entries.length ? entries.map((e) => h('article', {}, h('h3', {}, t(`echo.${e}.title`)), h('p', {}, t(`echo.${e}.text`)))) : h('p', { class: 'body' }, t('journal.empty')),
      h('nav', {}, this.button(t('menu.back'), onBack, { primary: true }))), 'sub');
  }

  endScreen(stats, onContinue, onMenu) {
    const fmt = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
    const rows = [['end.time', fmt(stats.time)], ['end.echoes', `${stats.echoes}/${stats.echoTotal}`], ['end.falls', stats.falls], ['end.hits', stats.hits], ['end.hints', stats.hints], ['end.tides', stats.tideToggles]];
    this.open(h('div', { class: 'menu-panel end' },
      h('p', { class: 'eyebrow' }, t('subtitle')),
      h('h2', {}, t('end.title')),
      h('p', { class: 'body' }, t('end.body')),
      h('dl', { class: 'stats' }, rows.map(([k, v]) => [h('dt', {}, t(k)), h('dd', {}, String(v))])),
      h('p', { class: 'note' }, t('end.survey')),
      h('nav', {}, this.button(t('end.continue'), onContinue, { primary: true }), this.button(t('end.menu'), onMenu))), 'end');
  }
}
