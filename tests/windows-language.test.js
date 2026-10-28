import test from 'node:test';
import assert from 'node:assert/strict';
import { languageFromTag, createText } from '../windows/web/language.js';
import { createCloudRenderer } from '../windows/web/cloud-renderer.js';
import { CloudScene } from '../windows/web/cloud-scene.js';

test('Russian UI language variants select Russian; all others fall back to English', () => {
  for (const tag of ['ru', 'ru-RU', 'ru-BY', 'ru_KZ', 'RU-ru']) {
    assert.equal(languageFromTag(tag), 'ru');
  }
  for (const tag of [null, undefined, '', 'en', 'en-RU', 'de', 'uk-UA', 'russian', 'fr,ru', 25]) {
    assert.equal(languageFromTag(tag), 'en');
  }
  assert.equal(createText('ru-RU')('Save', 'Сохранить'), 'Сохранить');
  assert.equal(createText('de-DE')('Save', 'Сохранить'), 'Save');
  assert.equal(createText(null)('Save', 'Сохранить'), 'Save');
});

test('renderer and animation failures use the language supplied by the host', () => {
  const canvas = { getContext: () => null };
  assert.throws(() => createCloudRenderer(canvas, 'ru'), /Для облаков требуется WebGL 2/);
  assert.throws(() => createCloudRenderer(canvas, 'en'), /WebGL 2 is required/);
  assert.throws(() => createCloudRenderer(canvas), /WebGL 2 is required/);
  assert.throws(() => new CloudScene(null, 'ru'), /Неверные данные анимации прямоугольников/);
  assert.throws(() => new CloudScene(null, 'en'), /Invalid rectangle tracks/);
});
