const TAU = Math.PI * 2;
export const wrap = (value, period) => ((value % period) + period) % period;

export const REFERENCE_START = 8 * 3600 + 58 * 60 + 22.12;

// Peaks measured on the visible hour marks; the lost original easing is approximated.
const MARK_GLINTS = [[0, 2.2, 180], [10, 3.1, 180], [15, 2.2, 180], [15, 5.2, 195],
  [20, 3.5, 180], [30, 2.2, 180], [35, 4.5, 180], [55, 3.0, 180]];
const smoothstep = value => { const x = Math.max(0, Math.min(1, value)); return x * x * (3 - 2 * x); };

function markHighlight(index, peak, origin, seconds) {
  const delta = wrap(seconds - peak + 4, 8) - 4;
  return {
    index,
    radius: origin + 12 * Math.max(-1, Math.min(1, delta / .8)),
    strength: Math.exp(-.5 * (delta / .55) ** 2),
  };
}

export function minuteMarkHighlights(seconds) {
  return MARK_GLINTS.map(([index, peak, origin]) => markHighlight(index, peak, origin, seconds));
}

export function minuteMarkOpacity(index, radius, seconds) {
  const envelope = smoothstep((radius - 112) / 68) * (1 - smoothstep((radius - 232) / 48));
  let alpha = index % 5 === 0 ? .19 : .15;
  for (const [mark, peak, origin] of MARK_GLINTS) {
    if (index !== mark) continue;
    const light = markHighlight(mark, peak, origin, seconds);
    alpha += .72 * light.strength * Math.exp(-.5 * ((radius - light.radius) / 12) ** 2);
  }
  return envelope * Math.min(.9, alpha);
}

// Measured 1 kHz tone onsets in clock-minute.wav, including its recorded A/V delay.
const SHORT_BEEP_ONSETS = [55.180, 56.182, 57.185, 58.187, 59.190];

export function clockState(secondsOfDay, audioPhase = secondsOfDay) {
  if (!Number.isFinite(secondsOfDay) || !Number.isFinite(audioPhase)) throw new TypeError('Time must be finite');
  const seconds = wrap(secondsOfDay, 60);
  const elapsed = Math.floor(seconds);
  const phase = wrap(audioPhase, 60);
  const tick = Math.floor(phase);
  const onset = tick === 0 ? .134 : tick >= 55 ? SHORT_BEEP_ONSETS[tick - 55] : tick;
  const secondTick = wrap(tick - (phase < onset ? 1 : 0), 60);
  return {
    seconds,
    elapsed,
    remaining: (60 - elapsed) % 60,
    hourAngle: wrap(secondsOfDay, 43200) / 43200 * TAU,
    minuteAngle: wrap(secondsOfDay, 3600) / 3600 * TAU,
    secondAngle: secondTick / 60 * TAU,
  };
}

// Ten subdivisions per second projected onto the visible face of a cylinder.
export function rulerTicks(seconds, reverse = false) {
  const value = reverse ? wrap(-seconds, 60) : wrap(seconds, 60);
  const centerTick = Math.floor(value * 10);
  return Array.from({ length: 101 }, (_, index) => {
    const tick = centerTick - 50 + index;
    const x = 346 * Math.sin((tick / 10 - value) * TAU / 30);
    return {
      x,
      alpha: 1 - smoothstep((Math.abs(x) - 80) / 220),
      major: tick % 10 === 0,
      label: tick % 50 === 0 ? wrap(tick / 10, 60) : null,
    };
  });
}
