"""Rebuild flat source SVG and transparent PNG layers: python render.py (Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
SCALE = 4
SIZE = 1024
COLORS = {"body": "#DED3BF", "screen": "#191D1B", "glyph": "#91E6A2"}
glyphs = [
    ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    ["00000", "00000", "01110", "10001", "11111", "10000", "01111"],
    ["00000", "00000", "10001", "10001", "10001", "01010", "00100"],
    ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
]
rects = []
for char, rows in enumerate(glyphs):
    for row, bits in enumerate(rows):
        for col, bit in enumerate(bits):
            if bit == "1":
                rects.append((236 + char * 144 + col * 24, 404 + row * 24, 24, 24))

svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">',
       '<title>Dev Island — flat layered app icon</title>']
composite = Image.new("RGBA", (SIZE, SIZE))
for name in ("body", "screen", "glyph"):
    layer = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE))
    draw = ImageDraw.Draw(layer)
    svg.append(f'<g id="{name}" fill="{COLORS[name]}">')
    if name in ("body", "screen"):
        x, y, w, h, radius = (100, 100, 824, 824, 180) if name == "body" else (188, 244, 648, 536, 62)
        draw.rounded_rectangle((x*SCALE, y*SCALE, (x+w)*SCALE-1, (y+h)*SCALE-1), radius*SCALE, fill=COLORS[name])
        svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}"/>')
    else:
        for x, y, w, h in rects:
            draw.rectangle((x*SCALE, y*SCALE, (x+w)*SCALE-1, (y+h)*SCALE-1), fill=COLORS[name])
            svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}"/>')
    svg.append('</g>')
    layer = layer.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    layer.save(ROOT / f'{name}.png')
    composite = Image.alpha_composite(composite, layer)
svg.append('</svg>')
(ROOT / 'source.svg').write_text('\n'.join(svg) + '\n', encoding='utf-8')
composite.save(ROOT / 'composite.png')
for size in (16, 32):
    composite.resize((size, size), Image.Resampling.LANCZOS).save(ROOT / f'preview-{size}.png')

comparison = Image.new('RGB', (560, 260), '#F0F0ED')
draw = ImageDraw.Draw(comparison)
draw.text((16, 12), 'Actual size / nearest-neighbor enlargement', fill='#191D1B')
for x, size in ((32, 16), (304, 32)):
    preview = Image.open(ROOT / f'preview-{size}.png')
    comparison.paste(preview, (x, 44), preview)
    enlarged = preview.resize((128, 128), Image.Resampling.NEAREST)
    comparison.paste(enlarged, (x, 92), enlarged)
    draw.text((x, 232), f'{size} px', fill='#191D1B')
comparison.save(ROOT / 'thumbnail-comparison.png')

for name in ('body', 'screen', 'glyph', 'composite'):
    image = Image.open(ROOT / f'{name}.png')
    assert image.size == (1024, 1024) and image.mode == 'RGBA'
    assert image.getpixel((0, 0))[3] == 0
print('Rendered SVG, three RGBA layers, composite and thumbnail comparison.')
