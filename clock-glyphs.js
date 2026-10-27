// Vector redraws of the broad numerals in the supplied recording; no font dependency.
const outlines = {
  '0': 'M17 0H83Q100 0 100 12V38Q100 50 83 50H17Q0 50 0 38V12Q0 0 17 0ZM27 13V37H73V13Z',
  '1': 'M0 0H57V50H29V13H0Z',
  '2': 'M0 0H78Q100 0 100 15Q100 25 83 30L33 38H100V50H0V36L69 20Q76 18 73 13H0Z',
  '3': 'M0 0H78Q100 0 100 12Q100 22 87 25Q100 27 100 38Q100 50 78 50H0V37H69Q75 37 75 32H24V19H72Q76 13 69 13H0Z',
  '4': 'M67 0H94V28H106V41H94V50H67V41H0V26ZM67 13L30 28H67Z',
  '5': 'M0 0H98V13H28V20H75Q100 20 100 35Q100 50 76 50H0V37H67Q76 37 76 33Q76 30 67 30H0Z',
  '6': 'M24 0H100V13H35Q27 13 27 20H75Q100 20 100 35Q100 50 77 50H24Q0 50 0 37V13Q0 0 24 0ZM27 32V37H70Q76 37 76 34Q76 32 70 32Z',
  '7': 'M0 0H100V15L51 50H16L68 14H0Z',
  '8': 'M23 0H77Q100 0 100 12Q100 21 86 25Q100 29 100 38Q100 50 77 50H23Q0 50 0 38Q0 29 14 25Q0 21 0 12Q0 0 23 0ZM28 12V18H72V12ZM28 32V38H72V32Z',
  '9': 'M23 0H77Q100 0 100 13V37Q100 50 77 50H0V37H65Q74 37 74 30H24Q0 30 0 15Q0 0 23 0ZM27 13Q23 13 23 16Q23 18 27 18H74V13Z',
};
const paths = Object.fromEntries(Object.entries(outlines).map(([digit, path]) => [digit, new Path2D(path)]));
const widths = { '1': 57, '2': 87, '4': 106 };

export function drawNumber(context, value, x, y, height, width, color = '#ecf3ff') {
  const text = String(value);
  const gap = text === '11' || text === '12' ? 12 : 7;
  const naturalWidth = [...text].reduce((sum, digit) => sum + (widths[digit] || 100), 0) + (text.length - 1) * gap;
  context.save();
  context.translate(x - width / 2, y - height / 2);
  context.scale(width / naturalWidth, height / 50);
  context.fillStyle = color;
  for (const digit of text) {
    context.save();
    if (digit === '2') context.scale(.87, 1);
    context.fill(paths[digit], 'evenodd');
    context.restore();
    context.translate((widths[digit] || 100) + gap, 0);
  }
  context.restore();
}
