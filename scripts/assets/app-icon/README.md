# Flat layered Dev Island icon

Prepared for task 2 of the Windows collaborator plan. The source is original
vector geometry: beige body, black screen and green pixel `Dev_` lettering.
No gradients, highlights, glass, bevels or shadows are baked in.

- `source.svg`: editable 1024 × 1024 source; named body/screen/glyph groups.
- `body.png`, `screen.png`, `glyph.png`: lossless RGBA layers, all 1024 × 1024,
  same origin. Composite in that order, without offsets.
- `composite.png`: transparent flattened preview.
- `preview-16.png`, `preview-32.png`: actual-size thumbnails.
- `thumbnail-comparison.png`: actual sizes plus nearest-neighbor enlargements.

Body geometry is 824 × 824 at (100, 100). Beige `#DED3BF`, black `#191D1B`,
green `#91E6A2`. Glyphs are paths made from rectangles; no external font needed.
Antialiasing may extend a few low-alpha pixels beyond the geometric bounds.

Rebuild with `python scripts/assets/app-icon/render.py` (Python 3 + Pillow;
verified with Pillow 13.0.0 on Windows). The SVG and PNG geometry share the
same generator. At 16 px the black screen and green mark remain identifiable;
the word itself is not intended to be fully legible at that size.

Owner handoff: review on macOS, generate `.icns` using the existing
`scripts/make-icon.sh` or import the separate layers into the appropriate icon
workflow, and check Dock/menu-bar appearance. This delivery does not replace
`IslandApp/Resources/AppIcon.icns` and does not claim macOS visual acceptance.
