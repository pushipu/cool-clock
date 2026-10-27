import test from 'node:test';
import assert from 'node:assert/strict';
import { clockState, rulerTicks, REFERENCE_START, minuteMarkOpacity, minuteMarkHighlights } from './clock-model.js';

test('reference time and complementary counters match the recording', () => {
  const clock = clockState(8 * 3600 + 58 * 60 + 22);
  assert.equal(clock.elapsed, 22);
  assert.equal(clock.remaining, 38);
  assert.equal(clock.secondAngle, 22 / 60 * Math.PI * 2);
  assert.ok(clock.hourAngle > 8.9 / 12 * Math.PI * 2);
  assert.ok(clock.hourAngle < 9 / 12 * Math.PI * 2);
});

test('both counters wrap to zero at the minute and midnight', () => {
  assert.equal(clockState(59.999).elapsed, 59);
  assert.equal(clockState(59.999).remaining, 1);
  for (const time of [0, 60, 3600, 86400]) {
    assert.equal(clockState(time).elapsed, 0);
    assert.equal(clockState(time).remaining, 0);
  }
  assert.equal(clockState(86400).hourAngle, 0);
});

test('hour and minute hands advance continuously while the second hand steps', () => {
  const a = clockState(12345);
  const b = clockState(12345.5);
  assert.equal(b.secondAngle, a.secondAngle);
  assert.ok(b.hourAngle > a.hourAngle);
  assert.ok(b.minuteAngle > a.minuteAngle);
  assert.throws(() => clockState(NaN), TypeError);
});

test('the last five steps land on the recorded short beep onsets', () => {
  for (const [second, onset] of [[55, 55.180], [56, 56.182], [57, 57.185], [58, 58.187], [59, 59.190]]) {
    assert.equal(clockState(onset - .001).secondAngle, (second - 1) / 60 * Math.PI * 2);
    assert.equal(clockState(onset + .001).secondAngle, second / 60 * Math.PI * 2);
  }
});

test('the second hand arrives at twelve on the long tone and holds through it', () => {
  assert.equal(clockState(60.133).secondAngle, 59 / 60 * Math.PI * 2);
  for (const phase of [.135, .2, .5, .609, .999]) assert.equal(clockState(60 + phase).secondAngle, 0);
  assert.equal(clockState(61).secondAngle, 1 / 60 * Math.PI * 2);
  // The sound position drives the hand even if the render clock has drifted.
  assert.equal(clockState(59.9, .2).secondAngle, 0);
  assert.equal(clockState(60.2, 59.9).secondAngle, 59 / 60 * Math.PI * 2);
  assert.equal(clockState(60.2, 59.9).elapsed, 0);
  assert.equal(clockState(-.1).secondAngle, clockState(59.9).secondAngle);
  assert.throws(() => clockState(0, NaN), TypeError);
});

test('upper and lower rulers move in opposite directions and wrap their labels', () => {
  const position = (s, reverse) => rulerTicks(s, reverse).find(t => t.label === 25).x;
  assert.ok(position(22.2, false) < position(22, false));
  assert.ok(position(37.2, true) > position(37, true));
  const reference = rulerTicks(22.12, false);
  assert.ok(Math.abs(492 + reference.find(t => t.label === 20).x - 343) < 2);
  assert.ok(Math.abs(492 + reference.find(t => t.label === 25).x - 687) < 2);
  assert.ok(reference.filter(t => Math.abs(t.x) > 280).every(t => t.alpha < .03));
  for (const reverse of [false, true]) {
    const ticks = rulerTicks(59.99, reverse);
    assert.ok(ticks.some(t => t.label === 0));
    assert.ok(ticks.every(t => t.label === null || (t.label >= 0 && t.label < 60)));
  }
});


test('recording starts 120 milliseconds into second22', () => {
  assert.equal(clockState(REFERENCE_START).elapsed, 22);
  assert.equal(clockState(REFERENCE_START + .88).elapsed, 23);
});

test('minute marks fade out at the hub and rim, and their light travels outwards', () => {
  for (let index = 0; index < 60; index++) {
    assert.ok(minuteMarkOpacity(index, 112, 2.2) < .001);
    assert.ok(minuteMarkOpacity(index, 280, 2.2) < .001);
    assert.ok(minuteMarkOpacity(index, 208, 7) > .1);
  }
  const brightestRadius = time => Array.from({ length: 100 }, (_, index) => 140 + index)
    .reduce((best, radius) => minuteMarkOpacity(15, radius, time) > minuteMarkOpacity(15, best, time) ? radius : best, 140);
  assert.ok(brightestRadius(2.5) > brightestRadius(1.9) + 5);
  assert.ok(minuteMarkOpacity(15, 180, 2.2) > .7);
  assert.ok(minuteMarkOpacity(16, 180, 2.2) < .3);
});

test('minute mark illumination repeats smoothly, including the background loop', () => {
  for (let index = 0; index < 60; index++) {
    for (const radius of [128, 176, 208, 264]) {
      assert.ok(Math.abs(minuteMarkOpacity(index, radius, 0) - minuteMarkOpacity(index, radius, 8)) < 1e-12);
      assert.ok(Math.abs(minuteMarkOpacity(index, radius, 116 * 112 / 116) - minuteMarkOpacity(index, radius, 0)) < 1e-12);
      assert.ok(Math.abs(minuteMarkOpacity(index, radius, 8 - 1e-5) - minuteMarkOpacity(index, radius, 1e-5)) < 1e-4);
    }
  }
});

test('glow follows the existing local glints and fades away between flashes', () => {
  const before = minuteMarkHighlights(1.8);
  const peak = minuteMarkHighlights(2.2);
  const after = minuteMarkHighlights(2.6);
  assert.equal(peak.length, 8);
  assert.deepEqual(peak.map(light => light.index), [0, 10, 15, 15, 20, 30, 35, 55]);
  assert.equal(peak[0].radius, 180);
  assert.equal(peak[0].strength, 1);
  assert.ok(before[0].radius < peak[0].radius && after[0].radius > peak[0].radius);
  assert.ok(before[0].strength < peak[0].strength && after[0].strength < peak[0].strength);
  assert.ok(Math.abs(before[0].strength - after[0].strength) < 1e-12);
  assert.ok(minuteMarkHighlights(6.2)[0].strength < 1e-10);
});

test('glow keeps the eight-second period and crosses the scene boundary smoothly', () => {
  for (const time of [0, 1.8, 2.2, 3.1, 5.2, 7.9, 112]) {
    const lights = minuteMarkHighlights(time);
    const repeated = minuteMarkHighlights(time + 8);
    lights.forEach((light, index) => {
      assert.equal(light.index, repeated[index].index);
      assert.ok(Math.abs(light.radius - repeated[index].radius) < 1e-12);
      assert.ok(Math.abs(light.strength - repeated[index].strength) < 1e-12);
      assert.ok(light.strength >= 0 && light.strength <= 1);
    });
  }
  const before = minuteMarkHighlights(8 - 1e-5);
  const after = minuteMarkHighlights(1e-5);
  before.forEach((light, index) => {
    assert.ok(Math.abs(light.strength - after[index].strength) < 1e-4);
    assert.ok(Math.abs(light.radius - after[index].radius) < 1e-3);
  });
});
