export function languageFromTag(tag) {
  return typeof tag === 'string' && /^ru(?:[-_]|$)/i.test(tag) ? 'ru' : 'en';
}

export function createText(tag) {
  const russian = languageFromTag(tag) === 'ru';
  return (english, russianText) => russian ? russianText : english;
}
