// Game — orquestra cena, sistemas e fluxo da fatia vertical.
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';

import { Assets } from './core/assets.js';
import { AudioEngine } from './core/audio.js';
import { Input } from './core/input.js';
import { PALETTE } from './core/palette.js';
import { t, setLanguage, setPadPrompts } from './i18n.js';
import { PhysicsWorld } from './world/physics.js';
import { Level } from './world/level.js';
import { buildSky, buildOcean, buildDistantIslands } from './world/visuals.js';
import { Iris } from './actors/Iris.js';
import { Lume } from './actors/Lume.js';
import { Guardian } from './actors/Guardian.js';
import { PlayerController } from './player/PlayerController.js';
import { CameraRig } from './player/CameraRig.js';
import { UI } from './ui/ui.js';
import { TideManager, HoldToConfirm, REFUSAL } from './systems/TideManager.js';
import { SaveManager, OptionsStore } from './systems/SaveManager.js';
import {
  TIDE, AREAS, createWorldState, currentObjective, liquidBridgeActive, guardianActive,
  plazaDry, cisternDry, UNSAFE_FOR_HIGH_TIDE,
} from './systems/PuzzleGraph.js';

export const DEFAULT_OPTIONS = {
  language: 'pt-BR', sensitivity: 1, invertY: false, textSize: '1', hints: true, assisted: false,
  reduceMotion: false, bloom: true, highContrast: false, subtitles: true, master: 0.8, music: 0.6, sfx: 0.8,
  quality: 'high',
};
const CHECKPOINT_ORDER = ['chegada', 'jardim', 'santuario'];
const ECHO_TOTAL = 3;
const HINT_DELAY = 30;
const HINT_STEP = 20;
const V = (x, y, z) => new THREE.Vector3(x, y, z);

export class Game {
  constructor(canvas, uiRoot) {
    this.canvas = canvas;
    this.ui = new UI(uiRoot);
    this.optionsStore = new OptionsStore();
    this.options = this.optionsStore.load(DEFAULT_OPTIONS);
    this.params = new URLSearchParams(location.search);
    if (this.params.get('quality')) this.options.quality = this.params.get('quality');
    setLanguage(this.options.language);
    this.saves = new SaveManager();
    this.audio = new AudioEngine();
    this.input = new Input(canvas);
    this.mode = 'loading';
    this.clock = new THREE.Clock();
  }

  // --- inicialização ---------------------------------------------------------------

  async init() {
    this.ui.setLoading(0);
    const r = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: true, powerPreference: 'high-performance' });
    r.setPixelRatio(Math.min(devicePixelRatio, 1.75));
    r.setSize(innerWidth, innerHeight);
    r.shadowMap.enabled = true;
    r.shadowMap.type = THREE.PCFSoftShadowMap;
    r.toneMapping = THREE.NeutralToneMapping;
    r.toneMappingExposure = 1.05;
    this.renderer = r;

    const scene = new THREE.Scene();
    scene.fog = new THREE.FogExp2('#1B4250', 0.0095);
    scene.background = new THREE.Color(PALETTE.noite);
    this.scene = scene;
    this.camera = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.1, 1500);
    this.camRig = new CameraRig(this.camera);

    // luz: direcional quente, céu frio (GDD 09)
    scene.add(new THREE.HemisphereLight('#A8E2E6', '#2A3F48', 1.6));
    const sun = new THREE.DirectionalLight('#FFD6A0', 2.8);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    const sc = sun.shadow.camera;
    sc.left = -24; sc.right = 24; sc.top = 24; sc.bottom = -24; sc.near = 1; sc.far = 120;
    sun.shadow.bias = -0.0006;
    sun.shadow.normalBias = 0.03;
    scene.add(sun, sun.target);
    this.sun = sun;
    this.sunOffset = V(-26, 40, -34);

    this.sky = buildSky(scene);
    this.ocean = buildOcean(scene);
    this.distant = buildDistantIslands(scene);

    this.assets = new Assets();
    await this.assets.load((p) => this.ui.setLoading(p));

    this.physics = new PhysicsWorld();
    this.level = new Level(this.assets, this.physics);
    scene.add(this.level.group);

    this.iris = new Iris(this.assets);
    scene.add(this.iris.object);
    this.player = new PlayerController();
    this.lume = new Lume(this.assets);
    scene.add(this.lume.object);
    this.guardian = new Guardian(this.assets, this.level.guardCfg);
    scene.add(this.guardian.object, this.guardian.cone);
    this.guardian.on((type, d) => this.onGuardian(type, d));

    // marcador de Lume (feixe vertical no ponto de interesse)
    const beamGeo = new THREE.CylinderGeometry(0.12, 0.45, 14, 8, 1, true);
    beamGeo.translate(0, 7, 0);
    this.beam = new THREE.Mesh(beamGeo, new THREE.MeshBasicMaterial({ color: PALETTE.ressonancia, transparent: true, opacity: 0, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }));
    this.beam.visible = false;
    scene.add(this.beam);
    this.beamT = 0;

    // pulso de escaneamento
    this.scanSphere = new THREE.Mesh(new THREE.SphereGeometry(1, 24, 16), new THREE.MeshBasicMaterial({ color: PALETTE.ressonancia, transparent: true, opacity: 0, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.BackSide }));
    this.scanSphere.visible = false;
    scene.add(this.scanSphere);
    this.scanT = 1;

    // relé -> portão (feixe)
    this.relayBeam = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.06, 1, 6), new THREE.MeshBasicMaterial({ color: PALETTE.ressonancia, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false }));
    this.relayBeam.visible = false;
    scene.add(this.relayBeam);

    // pós-processamento: bloom moderado na energia turquesa
    this.composer = new EffectComposer(r);
    this.composer.addPass(new RenderPass(scene, this.camera));
    this.bloom = new UnrealBloomPass(new THREE.Vector2(innerWidth, innerHeight), 0.55, 0.5, 0.82);
    this.composer.addPass(this.bloom);
    this.composer.addPass(new OutputPass());

    addEventListener('resize', () => this.resize());
    document.addEventListener('pointerlockchange', () => {
      if (!document.pointerLockElement && this.mode === 'play' && this.wantLock) this.pause();
    });
    this.canvas.addEventListener('click', () => {
      this.audio.start();
      if (this.mode === 'intro') this.camRig.skip();
      if (this.mode === 'play') { this.wantLock = true; this.input.requestLock(); }
    });

    this.applyOptions(this.options);
    this.ui.refreshStatic();
    this.ui.hideLoading();
    this.resetSession();
    this.showMainMenu();
    window.__mdv = this;
    this.loop();

    if (this.params.has('autostart')) this.newGame(true);
  }

  resize() {
    const w = innerWidth, h = innerHeight;
    this.renderer.setSize(w, h);
    this.composer.setSize(w, h);
    this.bloom.setSize(w, h);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  // --- sessão / estado ---------------------------------------------------------

  resetSession() {
    this.world = createWorldState(TIDE.HIGH);
    this.tide = new TideManager(TIDE.HIGH);
    this.tide.on((type, d) => this.onTide(type, d));
    this.holds = new Map(this.level.nodes.map((n) => [n.id, new HoldToConfirm()]));
    this.integrity = 3;
    this.checkpoint = 'chegada';
    this.stats = { time: 0, falls: 0, hits: 0, hints: 0, tideToggles: 0 };
    this.collected = [];
    this.area = AREAS.ARRIVAL;
    this.objective = null;
    this.objTimer = 0;
    this.hintLevel = 0;
    this.safePoints = [];
    this.safeTimer = 0;
    this.scanCd = 0;
    this.labelT = 0;
    this.said = new Set();
    this.bridgeLevel = 0;
    this.busy = 0;
    this.ended = false;
    this.respawning = false;
    for (const e of this.level.echoes) { e.collected = false; e.group.visible = true; }
    const me = this.level.mainEcho;
    me.recovered = false;
    me.mesh.visible = true;
    me.mesh.position.copy(me.base);
    this.level.shortcutT = 0;
    this.level.shortcut.visible = false;
    this.level.shortcutCol.enabled = false;
    this.level.conductor.angle = 0;
    this.level.conductor.target = 0;
    this.level.gate.open = 0;
    this.guardian.state = 'dormant';
    this.guardian.reset(false);
    this.lume.follow();
    this.placeAtCheckpoint('chegada');
  }

  checkpointPos(id) {
    const L = this.level;
    return id === 'santuario' ? L.checkpointSanctuary : id === 'jardim' ? L.checkpointGarden : { pos: L.start.pos, yaw: L.start.yaw };
  }

  placeAtCheckpoint(id) {
    const cp = this.checkpointPos(id);
    this.player.teleport(cp.pos.clone().add(V(0, 0.05, 0)), cp.yaw);
    this.camRig.snapBehind(cp.yaw, cp.pos.clone().add(V(0, 1.25, 0)));
    this.camRig.actualDist = this.camRig.dist;
    this.lume.place(cp.pos.clone().add(V(0.8, 1.9, 0.4)));
    this.safePoints = [{ x: cp.pos.x, y: cp.pos.y, z: cp.pos.z, col: null }];
  }

  snapshot() {
    return {
      checkpoint: this.checkpoint,
      world: { ...this.world, tide: this.tide.state },
      collected: [...this.collected],
      integrity: this.integrity,
      stats: { ...this.stats },
    };
  }

  autosave() {
    const ok = this.saves.save(this.snapshot());
    return ok;
  }

  loadFromSave(data) {
    this.resetSession();
    Object.assign(this.world, data.world);
    this.tide.set(data.world.tide);
    this.checkpoint = data.checkpoint;
    this.collected = [...(data.collected || [])];
    this.stats = { ...this.stats, ...(data.stats || {}) };
    this.integrity = Math.max(1, data.integrity || 3);
    for (const e of this.level.echoes) if (this.collected.includes(e.id)) { e.collected = true; e.group.visible = false; }
    if (this.world.echoRecovered) { this.level.mainEcho.recovered = true; this.level.mainEcho.mesh.visible = false; }
    if (this.world.conductorRotated) { this.level.conductor.angle = this.level.conductor.target = Math.PI / 2; }
    if (this.world.relayActive) { this.guardian.pacify(); this.guardian.pos.copy(this.level.guardCfg.perch); this.level.gate.open = 1; }
    else this.guardian.reset(guardianActive(this.world));
    if (this.world.shortcutOpen) this.level.shortcutT = 1;
    this.bridgeLevel = liquidBridgeActive(this.world) ? 1 : 0;
    this.placeAtCheckpoint(this.checkpoint);
    this.level.update({ tideLevel: this.tide.level, bridgeLevel: this.bridgeLevel, world: this.world, dt: 0.016, instant: true });
  }

  // --- menus ---------------------------------------------------------------------

  saveSummary() {
    const s = this.saves.load();
    if (!s) return null;
    const where = t(`checkpoint.${s.data.checkpoint}`);
    return t('menu.saveFound', { where }) + (s.source === 'backup' ? ' ' + t('menu.saveBackup') : '');
  }

  showMainMenu() {
    this.mode = 'menu';
    this.ui.showHud(false);
    this.input.releaseLock();
    this.wantLock = false;
    const save = this.saveSummary();
    this.ui.mainMenu({
      save,
      onContinue: () => { this.audio.start(); this.audio.play('ui'); const s = this.saves.load(); if (s) { this.loadFromSave(s.data); this.startPlay(); } },
      onNew: () => { this.audio.start(); this.audio.play('ui'); this.newGame(); },
      onOptions: () => this.ui.optionsMenu(this.options, (o, k) => this.onOptionChange(o, k), () => this.showMainMenu()),
      onControls: () => this.ui.controlsMenu(() => this.showMainMenu()),
      onCredits: () => this.ui.creditsMenu(() => this.showMainMenu()),
    });
  }

  newGame(skipIntro = false) {
    this.resetSession();
    this.saves.save(this.snapshot());
    this.ui.close();
    if (skipIntro || this.options.reduceMotion || this.params.has('skipintro')) { this.startPlay(); this.introLines(); return; }
    this.mode = 'intro';
    this.ui.showHud(true);
    this.ui.setHudMinimal(true);
    this.ui.titleCardShow('MARÉ DE VIDRO', t('subtitle'));
    this.ui.showSkip(true);
    const D = this.level.sanctuaryCenter;
    this.camRig.play([
      { pos: V(16, 18, D.z - 14), look: V(0, D.y + 3, D.z) },
      { pos: V(14, 11, -18), look: V(0, 0, -16) },
      { pos: V(10, 7, 10), look: V(0, -1, 14) },
      { pos: V(4, 4.5, 42), look: V(0, 1.3, 40.5) },
      { pos: V(0, 3.14, 46.2), look: V(0, 1.25, 40.5) },
    ], 10, () => {
      this.ui.titleCardShow('', '', false);
      this.ui.showSkip(false);
      this.startPlay();
      this.introLines();
    });
  }

  introLines() {
    this.lumeSay('lume.wake', 5);
    setTimeout(() => { if (this.mode === 'play' && !this.world.reachedCistern) this.lumeSay('lume.moveHint', 4); }, 5500);
  }

  startPlay() {
    this.mode = 'play';
    this.ui.close();
    this.ui.showHud(true);
    this.ui.setHudMinimal(false);
    this.ui.titleCardShow('', '', false);
    this.ui.showSkip(false);
    this.objTimer = 0;
    this.wantLock = true;
    this.input.requestLock();
  }

  pause() {
    if (this.mode !== 'play') return;
    this.mode = 'paused';
    this.wantLock = false;
    this.input.releaseLock();
    this.showPauseMenu();
  }

  showPauseMenu() {
    this.ui.pauseMenu({
      onResume: () => this.resume(),
      onJournal: () => this.ui.journalMenu(this.journalEntries(), () => this.showPauseMenu()),
      onOptions: () => this.ui.optionsMenu(this.options, (o, k) => this.onOptionChange(o, k), () => this.showPauseMenu()),
      onControls: () => this.ui.controlsMenu(() => this.showPauseMenu()),
      onCheckpoint: () => { this.resume(); this.reboot(false); },
      onQuit: () => { this.autosave(); this.showMainMenu(); },
    });
  }

  resume() {
    this.ui.close();
    this.mode = 'play';
    this.wantLock = true;
    this.input.requestLock();
  }

  journalEntries() {
    const order = ['main', 'float', 'islet'];
    return order.filter((id) => this.collected.includes(id));
  }

  onOptionChange(o, key) {
    this.options = o;
    this.optionsStore.save(o);
    this.applyOptions(o);
    if (key === 'language') {
      this.ui.refreshStatic();
      this.ui._obj = null;
      this.ui._prompt = null;
      // reabre o menu atual no novo idioma
      if (this.mode === 'menu') this.ui.optionsMenu(this.options, (oo, kk) => this.onOptionChange(oo, kk), () => this.showMainMenu());
      else this.ui.optionsMenu(this.options, (oo, kk) => this.onOptionChange(oo, kk), () => this.showPauseMenu());
    }
  }

  applyOptions(o) {
    setLanguage(o.language);
    this.input.sensitivity = o.sensitivity;
    this.input.invertY = o.invertY;
    this.camRig.reduceMotion = o.reduceMotion;
    const low = o.quality === 'low';
    if (this.bloom) this.bloom.enabled = o.bloom && !low;
    if (this.renderer) {
      this.renderer.setPixelRatio(low ? Math.min(devicePixelRatio, 1) * 0.75 : Math.min(devicePixelRatio, 1.75));
      this.resize();
    }
    if (this.sun) this.sun.castShadow = !low;
    this.audio.setVolumes({ master: o.master, music: o.music, sfx: o.sfx });
    this.ui.applyOptions(o);
    if (this.player) this.player.setAssisted(o.assisted);
    if (this.guardian) this.guardian.setAssisted(o.assisted);
    if (this.level) {
      // alto contraste: interativos mais brilhantes
      for (const n of this.level.nodes) n.circle.material.color.set(o.highContrast ? '#FFFFFF' : PALETTE.ressonancia);
    }
  }

  // --- eventos de sistemas -----------------------------------------------------------

  onTide(type, d) {
    if (type === 'start') {
      this.world.tide = d.to;
      this.stats.tideToggles++;
      this.audio.play(d.to === TIDE.HIGH ? 'tideUp' : 'tideDown');
      this.camRig.shake = 0.08;
      this.level.nodes.forEach((n) => { n.pulse = 1; });
    }
    if (type === 'end') {
      if (d.state === TIDE.LOW) this.lumeSayOnce('lume.tideLowFirst', 4.5, () => this.area === AREAS.CISTERN_TOP || this.area === AREAS.CISTERN_BOTTOM);
    }
    if (type === 'refused') this.audio.play('fail');
  }

  onGuardian(type) {
    // só avisa quando Íris já está no jardim (a maré é do setor inteiro)
    if (type === 'state' && this.guardian.state === 'waking') this.lumeSayOnce('lume.guardianWake', 4.5, () => this.world.reachedGarden);
    if (type === 'alert') {
      this.audio.play('alert');
      if (!this.said.has('saw2')) { this.lumeSay('lume.guardianSaw', 3.5); if (this.said.has('saw1')) this.said.add('saw2'); this.said.add('saw1'); }
    }
    if (type === 'lost') this.lumeSayOnce('lume.guardianLost', 4);
    if (type === 'hit') this.onHit();
  }

  lumeSay(key, seconds = 4.5) {
    this.ui.say(t(key), seconds);
    this.audio.play('lume');
  }

  lumeSayOnce(key, seconds, cond = () => true) {
    if (this.said.has(key) || !cond()) return;
    this.said.add(key);
    this.lumeSay(key, seconds);
  }

  // --- falhas e recuperação ------------------------------------------------------------

  async returnToSafe(reason) {
    if (this.respawning) return;
    this.respawning = true;
    this.stats.falls++;
    this.audio.play('fall');
    await this.ui.fade(1, 0.3);
    const lv = this.tide.level;
    let spot = null;
    for (let i = this.safePoints.length - 1; i >= 0; i--) {
      const s = this.safePoints[i];
      if (s.col && !s.col.enabled) continue;
      const ground = this.physics.groundAt(s.x, s.z, s.y + 0.5);
      if (!ground || ground.yMax < s.y - 0.6) continue;
      if (this.level.waterAt(s.x, s.z, lv) > s.y - 0.3) continue;
      if (this.area === AREAS.PLAZA && guardianActive(this.world) && s.y < -1) continue;
      spot = s; break;
    }
    if (!spot) { const cp = this.checkpointPos(this.checkpoint); spot = cp.pos; }
    this.player.teleport(V(spot.x, spot.y + 0.05, spot.z));
    this.lume.place(V(spot.x + 0.8, spot.y + 1.9, spot.z));
    if (this.stats.falls <= 2 || reason === 'drown') this.lumeSay('lume.fall', 2.5);
    await this.ui.fade(0, 0.35);
    this.respawning = false;
  }

  async onHit() {
    if (this.respawning) return;
    this.integrity--;
    this.stats.hits++;
    this.audio.play('hit');
    this.camRig.shake = 0.35;
    this.irisHurt = 0.6;
    this.player.locked = 0.4;
    if (this.integrity <= 0) { await this.reboot(true); return; }
    this.respawning = true;
    await this.ui.fade(1, 0.35);
    this.player.teleport(this.level.plazaSafeExit.clone(), Math.PI);
    this.lume.place(this.level.plazaSafeExit.clone().add(V(0.8, 1.9, 0)));
    if (this.integrity === 1) this.lumeSay('lume.hitLow', 4);
    await this.ui.fade(0, 0.35);
    this.respawning = false;
  }

  /** Reinicia no último checkpoint (integridade zerada ou pelo menu). */
  async reboot(fromDamage) {
    this.respawning = true;
    await this.ui.fade(1, 0.5);
    this.integrity = 3;
    this.placeAtCheckpoint(this.checkpoint);
    this.guardian.reset(guardianActive(this.world));
    this.lume.follow();
    if (fromDamage) this.lumeSay('lume.reboot', 3);
    await this.ui.fade(0, 0.5);
    this.respawning = false;
  }

  reachCheckpoint(id) {
    if (CHECKPOINT_ORDER.indexOf(id) <= CHECKPOINT_ORDER.indexOf(this.checkpoint)) return;
    this.checkpoint = id;
    if (id === 'santuario') this.integrity = 3;
    this.autosave();
    if (id === 'jardim') this.lumeSay('lume.checkpoint', 2.5);
  }

  // --- ações -----------------------------------------------------------------------

  scan() {
    if (this.scanCd > 0) return;
    this.scanCd = 1.2;
    this.scanT = 0;
    this.labelT = 5;
    this.lume.scanPulse();
    this.audio.play('scan');
    const p = this.irisPos;
    for (const n of this.level.nodes) {
      if (p.distanceTo(n.pos) < 5.5 && !this.world.nodeScanned) {
        this.world.nodeScanned = true;
        this.lumeSay('lume.scannedNode', 4.5);
        this.audio.play('confirm');
      }
    }
    if (this.area === AREAS.PLAZA && plazaDry(this.world) && !this.world.platesScanned) {
      const near = this.level.plates.some((pl) => pl.pos.distanceTo(p) < 10);
      if (near) {
        this.world.platesScanned = true;
        this.audio.play('confirm');
        this.lumeSay('lume.plates', 5.5);
      }
    }
    this.markObjective(4);
  }

  objectiveTarget(obj) {
    const L = this.level;
    const inGarden = this.area === AREAS.GARDEN || this.area === AREAS.PLAZA;
    const node = inGarden ? L.nodes[1] : L.nodes[0];
    switch (obj) {
      case 'reach_cistern': return V(0, 0.9, 30.2);
      case 'scan_node': case 'lower_tide': case 'raise_tide': return node.pos;
      case 'rotate_conductor': return L.conductor.pos;
      case 'climb_out': return V(-2.4, 0, 11.4);
      case 'cross_bridge': return V(0, 0, 1.2);
      case 'expose_plates': return L.nodes[1].pos;
      case 'scan_plates': return V(0, -2.2, -16);
      case 'activate_relay': return L.plates.find((pl) => pl.correct).pos;
      case 'reach_sanctuary': return V(0, 0, L.gate.z);
      case 'recover_echo': case 'rest': return L.fountain.pos;
      default: return null;
    }
  }

  markObjective(seconds) {
    const target = this.objectiveTarget(this.objective);
    if (!target) return;
    this.beam.position.copy(target);
    this.beamT = seconds;
  }

  rotateConductor() {
    this.world.conductorRotated = true;
    this.level.conductor.target = Math.PI / 2;
    this.player.locked = 0.8;
    this.irisInteract = 0.8;
    this.audio.play('rotate');
    setTimeout(() => { this.audio.play('activate'); this.lumeSay('lume.conductor', 4.5); }, 900);
  }

  activateRelay() {
    this.busy = 99;
    this.player.locked = 0.8;
    this.irisInteract = 0.8;
    this.lumeSay('lume.relayGo', 3);
    this.audio.play('confirm');
    this.lume.flyTo(this.level.relay.pos, () => {
      this.world.relayActive = true;
      this.guardian.pacify();
      this.audio.play('activate');
      setTimeout(() => this.audio.play('pacify'), 400);
      this.lumeSay('lume.relayOn', 5);
      this.relayFlash = 2.5;
      setTimeout(() => { this.lume.follow(); this.busy = 0; }, 1600);
    });
  }

  recoverEcho() {
    const me = this.level.mainEcho;
    this.world.echoRecovered = true;
    this.world.shortcutOpen = true;
    this.collected.push('main');
    this.player.locked = 2.2;
    this.irisInteract = 1.2;
    this.audio.play('echo');
    this.level.firePulse();
    me.flying = { t: 0, from: me.pos.clone() };
    this.ui.toast(t('echo.main.title'), t('echo.main.text'), 9);
    setTimeout(() => this.lumeSay('lume.shortcut', 5), 3200);
    this.autosave();
  }

  rest() {
    this.world.rested = true;
    this.integrity = 3;
    this.player.locked = 2;
    this.audio.play('success');
    this.level.firePulse();
    this.lumeSay('lume.rest', 3.5);
    this.autosave();
    setTimeout(() => this.showEnd(), 2200);
  }

  showEnd() {
    this.mode = 'end';
    this.ended = true;
    this.wantLock = false;
    this.input.releaseLock();
    this.ui.endScreen(
      { ...this.stats, echoes: this.collected.length, echoTotal: ECHO_TOTAL },
      () => this.resume(),
      () => this.showMainMenu(),
    );
  }

  collectOptional(e) {
    e.collected = true;
    this.collected.push(e.id);
    this.audio.play('echo');
    this.ui.toast(t(`echo.${e.id}.title`), t(`echo.${e.id}.text`), 8);
    this.lumeSayOnce('lume.optionalEcho', 4);
    this.autosave();
  }

  // --- laço principal ------------------------------------------------------------

  get irisPos() { const p = this.player.pos; return V(p.x, p.y, p.z); }

  loop() {
    requestAnimationFrame(() => this.loop());
    const dt = Math.min(0.05, this.clock.getDelta());
    this.frame(dt);
  }

  frame(dt) {
    this.input.pollPad();
    setPadPrompts(this.input.usingPad);
    this.time = (this.time || 0) + dt;

    if (this.ui.menuOpen) this.menuInput();
    if (this.mode === 'intro' && (this.input.pressed.size || this.input.mouse.dx)) {
      if (this.input.pressed.size) this.camRig.skip();
    }
    if (this.mode === 'play') this.updatePlay(dt);
    else if (this.mode === 'menu') this.menuCamera(dt);

    // atualizações visuais compartilhadas
    const tideLevel = this.tide.level;
    if (this.mode !== 'paused') {
      const target = this.world.conductorRotated ? tideLevel : 0;
      this.bridgeLevel += (target - this.bridgeLevel) * (1 - Math.exp(-3 * dt));
      this.level.update({ tideLevel, bridgeLevel: this.bridgeLevel, world: this.world, dt, tideTransition: this.tide.transitioning });
      for (const n of this.level.nodes) n.hold = this.holds.get(n.id).ratio;
      this.ocean.material.uniforms.uTime.value += dt;
      this.distant.children.forEach((c, i) => { c.position.y += Math.sin(this.time * 0.2 + i) * 0.004; });
    }
    if (this.mode === 'intro') {
      this.camRig.update(dt, { dx: 0, dy: 0, wheel: 0 }, this.irisPos, null);
      this.animateActors(dt);
    }
    this.updateEffects(dt);
    const sp = this.irisPos;
    this.sun.position.copy(sp).add(this.sunOffset);
    this.sun.target.position.copy(sp);
    this.ui.update(dt);
    this.audio.update(tideLevel, this.guardian.alertLevel);
    this.composer.render();
    this.input.endFrame();
  }

  menuInput() {
    const gp = this.input.pad;
    if (gp) {
      const now = { up: gp.buttons[12]?.pressed || gp.axes[1] < -0.6, down: gp.buttons[13]?.pressed || gp.axes[1] > 0.6, a: gp.buttons[0]?.pressed, b: gp.buttons[1]?.pressed };
      const prev = this.padMenuPrev || {};
      if (now.up && !prev.up) this.ui.navigate(-1);
      if (now.down && !prev.down) this.ui.navigate(1);
      if (now.a && !prev.a) this.ui.activate();
      this.padMenuPrev = now;
    }
    if (this.input.wasPressed('pause') && this.mode === 'paused') this.resume();
  }

  menuCamera(dt) {
    const a = this.time * 0.05;
    this.camera.position.set(Math.sin(a) * 58, 24, -4 + Math.cos(a) * 58);
    this.camera.lookAt(0, -2, -4);
    this.animateActors(dt);
  }

  animateActors(dt) {
    const p = this.irisPos;
    this.iris.object.position.copy(p);
    this.iris.object.rotation.y = this.player.yaw;
    this.iris.update(dt, { speed: 0, grounded: true, vy: 0, integrity: this.integrity });
    this.lume.update(dt, p, this.player.yaw, this.camera.position);
    this.guardian.update(dt, { active: guardianActive(this.world), player: { pos: p, inZone: false, dodging: false } });
  }

  updatePlay(dt) {
    const inp = this.input;
    if (inp.wasPressed('pause')) { this.pause(); return; }
    this.stats.time += dt;
    this.tide.update(dt);
    this.scanCd = Math.max(0, this.scanCd - dt);

    // jogador
    const look = inp.look(dt);
    const events = this.player.update(dt, {
      move: this.respawning ? { x: 0, y: 0 } : inp.move(),
      camYaw: this.camRig.yaw,
      jumpPressed: inp.wasPressed('jump'),
      jumpHeld: inp.isDown('jump'),
      dodgePressed: inp.wasPressed('dodge'),
    }, this.physics);
    for (const e of events) this.audio.play(e);
    const p = this.irisPos;

    // área e progresso
    this.area = this.level.areaAt(p, this.area);
    const w = this.world;
    if (this.area === AREAS.CISTERN_TOP && !w.reachedCistern) { w.reachedCistern = true; this.lumeSay('lume.arrivedCistern', 4.5); }
    if ((this.area === AREAS.GARDEN || this.area === AREAS.PLAZA) && !w.reachedGarden && p.z < -4) { w.reachedGarden = true; this.lumeSay('lume.garden', 5); }
    if (this.area === AREAS.SANCTUARY && !w.reachedSanctuary) { w.reachedSanctuary = true; this.lumeSay('lume.sanctuary', 4.5); this.reachCheckpoint('santuario'); }
    if (p.distanceTo(this.level.checkpointGarden.pos) < this.level.checkpointGarden.radius) this.reachCheckpoint('jardim');
    if (this.area === AREAS.ARRIVAL && p.z < 33.5 && !w.reachedCistern) this.lumeSayOnce('lume.glideTeach', 5);
    if (this.bridgeLevel > 0.9) this.lumeSayOnce('lume.bridge', 4.5, () => this.area === AREAS.CISTERN_TOP);

    // quedas e água
    if (!this.respawning) {
      if (p.y < -16) this.returnToSafe('fall');
      else if (p.y < this.level.waterAt(p.x, p.z, this.tide.level) - 0.55) this.returnToSafe('drown');
    }
    // pontos seguros
    const b = this.player.body;
    this.safeTimer -= dt;
    if (this.safeTimer <= 0 && b.grounded && b.ground?.tags.safe && b.wellSupported()) {
      this.safeTimer = 0.25;
      const last = this.safePoints[this.safePoints.length - 1];
      if (!last || Math.hypot(last.x - p.x, last.z - p.z) > 0.6 || Math.abs(last.y - p.y) > 0.3) {
        this.safePoints.push({ x: p.x, y: p.y, z: p.z, col: b.ground });
        if (this.safePoints.length > 16) this.safePoints.shift();
      }
    }

    // ecos opcionais (coleta por toque)
    for (const e of this.level.echoes) if (!e.collected && p.distanceTo(e.pos) < e.radius + 0.5) this.collectOptional(e);

    this.updateInteraction(dt);

    // guardião
    const inZone = this.area === AREAS.PLAZA && p.y < -1.0;
    this.guardian.update(dt, { active: guardianActive(w), player: { pos: p, inZone, dodging: this.player.dodging } });

    // objetivo e dicas
    const obj = currentObjective(w, this.area);
    if (obj !== this.objective) { this.objective = obj; this.objTimer = 0; this.hintLevel = 0; if (obj !== 'done') this.audio.play('confirm'); }
    this.ui.setObjective(obj);
    this.objTimer += dt;
    const delay = this.options.assisted ? HINT_DELAY / 2 : HINT_DELAY;
    if (this.options.hints && obj !== 'done' && this.hintLevel < 3 && this.objTimer > delay + this.hintLevel * HINT_STEP) {
      this.hintLevel++;
      this.stats.hints++;
      this.ui.say(t(`hint.${obj}.${this.hintLevel}`), 7, 'Lume', true);
      this.audio.play('lume');
      if (this.hintLevel >= 2) this.markObjective(8);
    }

    // câmera e atores
    this.camRig.update(dt, look, p, this.level.cameraBlockers);
    this.iris.object.position.copy(p);
    this.iris.object.rotation.y = this.player.yaw;
    this.irisHurt = Math.max(0, (this.irisHurt || 0) - dt);
    this.irisInteract = Math.max(0, (this.irisInteract || 0) - dt);
    this.iris.update(dt, {
      speed: this.player.speed, grounded: b.grounded, vy: b.vel.y, gliding: this.player.gliding,
      scanning: this.scanT < 0.6, interacting: this.irisInteract > 0, dodging: this.player.dodging,
      hurt: this.irisHurt > 0, integrity: this.integrity, turnRate: this.player.turnRate,
    });
    this.lume.update(dt, p, this.player.yaw, this.camera.position);

    // HUD
    this.ui.setIntegrity(this.integrity);
    this.ui.setTide(this.tide.state, this.tide.transitioning, this.tide.progress, this.tide.cooldown / this.tide.rules.COOLDOWN);
    this.ui.setEchoes(this.collected.length, ECHO_TOTAL);
    this.updateLabels(dt);
  }

  /** Decide o prompt contextual e executa a interação. */
  updateInteraction(dt) {
    const inp = this.input, p = this.irisPos, w = this.world, L = this.level;
    const grounded = this.player.body.grounded;
    let prompt = null;
    const key = (a) => t(`${this.input.usingPad ? 'pad' : 'key'}.${a}`);
    const free = this.busy <= 0 && !this.respawning && this.player.locked <= 0;

    // nós de maré
    for (const n of L.nodes) {
      const hold = this.holds.get(n.id);
      const near = grounded && Math.hypot(p.x - n.pos.x, p.z - n.pos.z) < n.radius && Math.abs(p.y - n.pos.y) < 1.5;
      if (!near) { hold.update(dt, false); continue; }
      if (!w.nodeScanned) { prompt = { text: t('prompt.scan'), key: key('scan') }; hold.update(dt, false); continue; }
      const refusal = this.tide.refusal({ playerUnsafe: UNSAFE_FOR_HIGH_TIDE.has(this.area) });
      if (refusal) {
        const msg = refusal === REFUSAL.COOLDOWN ? 'refuse.cooldown' : refusal === REFUSAL.TRANSITIONING ? 'refuse.transitioning' : 'refuse.unsafe';
        prompt = { text: t(msg), key: key('tide'), disabled: true };
        hold.update(dt, false);
        if (inp.wasPressed('tide')) this.audio.play('fail');
        continue;
      }
      const fired = free && hold.update(dt, inp.isDown('tide'));
      prompt = { text: t('prompt.tide'), key: key('tide'), hold: hold.ratio };
      if (inp.wasPressed('tide')) this.audio.play('ui');
      if (fired) this.tide.toggle({ playerUnsafe: UNSAFE_FOR_HIGH_TIDE.has(this.area) });
    }

    // condutor
    const c = L.conductor;
    if (!prompt && this.area === AREAS.CISTERN_BOTTOM && !w.conductorRotated && cisternDry(w) && Math.hypot(p.x - c.pos.x, p.z - c.pos.z) < c.radius) {
      prompt = { text: t('prompt.conductor'), key: key('interact') };
      if (free && inp.wasPressed('interact')) this.rotateConductor();
    }

    // placas
    if (!prompt && this.area === AREAS.PLAZA && plazaDry(w) && !w.relayActive) {
      for (const pl of L.plates) {
        if (Math.hypot(p.x - pl.pos.x, p.z - pl.pos.z) > pl.radius) continue;
        if (!w.platesScanned) prompt = { text: t('prompt.plateUnknown'), key: key('scan'), disabled: true };
        else if (pl.correct) {
          prompt = { text: t('prompt.plate'), key: key('interact') };
          if (free && inp.wasPressed('interact')) this.activateRelay();
        } else {
          prompt = { text: t('refuse.plateBroken'), key: key('interact'), disabled: true };
          if (inp.wasPressed('interact')) this.audio.play('fail');
        }
      }
    }

    // santuário: eco e descanso
    const f = L.fountain;
    if (!prompt && this.area === AREAS.SANCTUARY && Math.hypot(p.x - f.pos.x, p.z - f.pos.z) < f.radius) {
      if (!w.echoRecovered) {
        prompt = { text: t('prompt.echo'), key: key('interact') };
        if (free && inp.wasPressed('interact')) this.recoverEcho();
      } else if (!w.rested) {
        prompt = { text: t('prompt.rest'), key: key('interact') };
        if (free && inp.wasPressed('interact')) this.rest();
      }
    }

    if (free && inp.wasPressed('scan')) this.scan();
    if (prompt) this.ui.setPrompt(prompt.text, prompt.key, prompt.hold || 0, prompt.disabled);
    else this.ui.setPrompt(null);
  }

  updateLabels(dt) {
    this.labelT = Math.max(0, this.labelT - dt);
    if (this.labelT <= 0) { this.ui.setLabels([]); return; }
    const p = this.irisPos, w = this.world;
    const out = [];
    const v = new THREE.Vector3();
    const alpha = Math.min(1, this.labelT / 0.8);
    for (const s of this.level.scannables) {
      if (s.pos.distanceTo(p) > 20) continue;
      let key = s.key, kind = 'energy';
      if (s.kind === 'conductor') { key = w.conductorRotated ? 'scan.conductorOn' : 'scan.conductor'; kind = 'interact'; }
      if (s.kind === 'plate') {
        if (!plazaDry(w) || this.tide.level > 0.4) { key = 'scan.plateSub'; kind = 'muted'; }
        else if (!w.platesScanned) continue;
        else kind = s.plate.correct ? 'energy' : 'threat';
      }
      if (s.kind === 'echo' && s.echo.collected) continue;
      if (s.kind === 'guardian') { if (w.relayActive) continue; kind = 'threat'; }
      if (s.kind === 'relay') kind = 'interact';
      if (s.kind === 'emitter' && !w.conductorRotated) kind = 'interact';
      v.copy(s.pos).project(this.camera);
      if (v.z > 1 || Math.abs(v.x) > 1.1 || Math.abs(v.y) > 1.1) continue;
      out.push({ x: (v.x * 0.5 + 0.5) * innerWidth, y: (-v.y * 0.5 + 0.5) * innerHeight, text: t(key), kind, alpha, d: s.pos.distanceTo(p) });
    }
    // evita sobreposição: os mais próximos têm prioridade; os demais sobem
    out.sort((a, b) => a.d - b.d);
    const placed = [];
    const scale = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--ui-scale')) || 1;
    for (const l of out) {
      const w = l.text.length * 7.2 * scale + 24, hgt = 26 * scale;
      for (let tries = 0; tries < 6; tries++) {
        const hit = placed.find((q) => Math.abs(q.x - l.x) < (q.w + w) / 2 && Math.abs(q.y - l.y) < hgt);
        if (!hit) break;
        l.y = hit.y - hgt - 2;
      }
      l.w = w;
      placed.push(l);
    }
    this.ui.setLabels(placed);
  }

  updateEffects(dt) {
    // feixe de Lume
    if (this.beamT > 0) {
      this.beamT -= dt;
      this.beam.visible = true;
      this.beam.material.opacity = Math.min(0.35, this.beamT * 0.3) * (0.75 + 0.25 * Math.sin(this.time * 6));
    } else this.beam.visible = false;
    // pulso de escaneamento
    if (this.scanT < 1) {
      this.scanT = Math.min(1, this.scanT + dt / 1.1);
      this.scanSphere.visible = this.scanT < 1;
      this.scanSphere.position.copy(this.lume.pos);
      this.scanSphere.scale.setScalar(0.3 + this.scanT * 18);
      this.scanSphere.material.opacity = (1 - this.scanT) * 0.25;
    }
    // feixe relé -> portão
    if (this.relayFlash > 0) {
      this.relayFlash -= dt;
      const a = this.level.relay.pos, bpos = V(0, 3, this.level.gate.z);
      const mid = a.clone().add(bpos).multiplyScalar(0.5);
      this.relayBeam.visible = true;
      this.relayBeam.position.copy(mid);
      this.relayBeam.scale.set(1, a.distanceTo(bpos), 1);
      this.relayBeam.quaternion.setFromUnitVectors(V(0, 1, 0), bpos.clone().sub(a).normalize());
      this.relayBeam.material.opacity = Math.min(1, this.relayFlash) * 0.8;
    } else this.relayBeam.visible = false;
    // eco voando até o núcleo da Íris
    const me = this.level.mainEcho;
    if (me.flying) {
      me.flying.t += dt / 1.4;
      const k = Math.min(1, me.flying.t);
      const target = this.irisPos.add(V(0, 0.85, 0));
      const pos = me.flying.from.clone().lerp(target, k * k);
      pos.y += Math.sin(k * Math.PI) * 1.5;
      me.mesh.parent.worldToLocal(pos);
      me.mesh.position.copy(pos);
      me.mesh.scale.setScalar(1 - k * 0.7);
      if (k >= 1) { me.flying = null; me.recovered = true; me.mesh.visible = false; this.irisInteract = 0.5; }
    }
  }
}
