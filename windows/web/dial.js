import { clockState, rulerTicks, minuteMarkOpacity, minuteMarkHighlights } from './clock-model.js';
import { drawNumber } from './clock-glyphs.js';

export function createDial(canvas, referenceAnimation = false) {
const context = canvas.getContext('2d');
const minuteGlow = createMinuteGlow();
function createMinuteGlow() {
  const sprite = document.createElement('canvas');
  sprite.width = 32;
  sprite.height = 192;
  const light = sprite.getContext('2d');
  light.scale(2, 2);
  light.translate(8, 48);
  light.scale(8, 48);
  const gradient = light.createRadialGradient(0, 0, 0, 0, 0, 1);
  for (let i = 0; i <= 8; i++) {
    const r = i / 8;
    const alpha = i === 8 ? 0 : .24 * Math.exp(-5.12 * r * r);
    gradient.addColorStop(r, `rgba(235,243,255,${alpha})`);
  }
  light.fillStyle = gradient;
  light.fillRect(-1, -1, 2, 2);
  return sprite;
}

function drawRuler(seconds, reverse) {
  const baseline = reverse ? 567 : 150;
  const direction = reverse ? 1 : -1;
  context.save();
  context.beginPath();
  context.rect(170, reverse ? 560 : 94, 644, 65);
  context.clip();
  for (const tick of rulerTicks(seconds, reverse)) {
    const alpha = tick.alpha;
    if (!alpha) continue;
    context.strokeStyle = `rgba(201,220,255,${alpha * (tick.major ? .9 : .8)})`;
    context.lineWidth = tick.major ? 3.2 : 2.6;
    context.beginPath();
    context.moveTo(492 + tick.x, baseline);
    context.lineTo(492 + tick.x, baseline + direction * (tick.major ? 35 : 18));
    context.stroke();
    if (tick.label !== null) {
      drawNumber(context, tick.label, 492 + tick.x, baseline + direction * 44, 10, tick.label < 10 ? 13 : 30, `rgba(224,234,255,${alpha * .75})`);
    }
  }
  context.restore();
}

function drawCounter(value, y) {
  const digits = String(value).padStart(2, '0');
  const widths = [34, 19, 30, 30, 34, 31, 31, 28, 32, 32];
  for (let i = 0; i < 2; i++) {
    const x = 452 + i * 40;
    context.fillStyle = 'rgba(181,203,238,.28)';
    context.fillRect(x, y - 17, 39, 34);
    drawNumber(context, digits[i], x + 20, y, 22, widths[Number(digits[i])], '#eaf2ff');
  }
}

function drawStructure(animation) {
  const phase = animation * (referenceAnimation ? 1 : 112 / 116);
  for (const light of minuteMarkHighlights(phase)) {
    if (light.strength < .002) continue;
    context.save();
    context.translate(492, 359);
    context.scale(1.03, 1);
    context.rotate(light.index * Math.PI / 30);
    context.globalAlpha = light.strength;
    context.drawImage(minuteGlow, -8, -light.radius - 48, 16, 96);
    context.restore();
  }
  for (let i = 0; i < 60; i++) {
    const angle = i * Math.PI / 30;
    const dx = Math.sin(angle) * 1.03;
    const dy = -Math.cos(angle);
    const gradient = context.createLinearGradient(492 + dx * 112, 359 + dy * 112, 492 + dx * 280, 359 + dy * 280);
    for (let radius = 112; radius <= 280; radius += 8) {
      gradient.addColorStop((radius - 112) / 168, `rgba(235,243,255,${minuteMarkOpacity(i, radius, phase)})`);
    }
    context.strokeStyle = gradient;
    context.lineWidth = i % 5 === 0 ? 3.2 : 2.5;
    context.beginPath();
    context.moveTo(492 + dx * 112, 359 + dy * 112);
    context.lineTo(492 + dx * 280, 359 + dy * 280);
    context.stroke();
  }
}

const numerals = [
  [10, 202.5, 185, 147, 46], [11, 351, 185, 112, 46], [12, 496, 185, 138, 46],
  [1, 638.5, 185, 51, 46], [2, 777, 185, 78, 46], [3, 782, 357.5, 88, 47],
  [4, 782, 534.5, 100, 47], [5, 646, 533, 86, 46], [6, 495.5, 534, 91, 46],
  [7, 352.5, 534, 83, 46], [8, 201, 533, 94, 46], [9, 197.5, 357.5, 91, 47],
];

function drawHand(angle, length, tail, tailWidth, tipWidth) {
  context.save();
  context.translate(492, 359);
  context.scale(1.03, 1);
  context.rotate(angle);
  context.beginPath();
  context.moveTo(-tailWidth / 2, tail);
  context.lineTo(tailWidth / 2, tail);
  context.lineTo(tipWidth / 2, -length);
  context.lineTo(-tipWidth / 2, -length);
  context.closePath();
  context.fillStyle = '#f5f9ff';
  context.fill();
  context.restore();
}

return function draw(time, audioPhase, animation) {
  const width = canvas.width, height = canvas.height;
  const state = clockState(time, audioPhase);
  context.setTransform(1, 0, 0, 1, 0, 0);
  context.clearRect(0, 0, width, height);
  const scale = Math.min(width / 984, height / 718);
  context.translate((width - 984 * scale) / 2, (height - 718 * scale) / 2);
  context.scale(scale, scale);
  drawStructure(animation);
  for (const [value, x, y, w, h] of numerals) {
    const brightness = .63 + .30 * (.5 + .5 * Math.sin(animation * Math.PI * 12 / 116 + value * .83));
    drawNumber(context, value, x, y, h, w, `rgba(235,243,255,${brightness})`);
  }
  drawRuler(state.seconds, false);
  drawRuler(state.seconds, true);
  drawCounter(state.elapsed, 107);
  drawCounter(state.remaining, 611);
  drawHand(state.hourAngle, 175.5, 13, 15, 6);
  drawHand(state.minuteAngle, 194, 29, 10, 3);
  drawHand(state.secondAngle, 200, 30, 5.6, 1.3);
};
}
