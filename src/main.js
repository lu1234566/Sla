import './style.css';
import { Game } from './game.js';

const canvas = document.getElementById('game');
const ui = document.getElementById('ui');

function webglAvailable() {
  try {
    const c = document.createElement('canvas');
    return !!(c.getContext('webgl2') || c.getContext('webgl'));
  } catch {
    return false;
  }
}

if (!webglAvailable()) {
  ui.innerHTML = '<div class="screen fatal"><h1>MARÉ DE VIDRO</h1><p>Seu navegador não oferece WebGL, necessário para o jogo.</p></div>';
} else {
  const game = new Game(canvas, ui);
  game.init().catch((err) => {
    console.error(err);
    const msg = String(err.message || err).replace(/data:[^"\s]+/g, 'data:…').slice(0, 300).replace(/</g, '&lt;');
    ui.innerHTML = `<div class="screen fatal"><h1>MARÉ DE VIDRO</h1><p>Falha ao iniciar: ${msg}</p></div>`;
  });
}
