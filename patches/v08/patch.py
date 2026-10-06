from pathlib import Path

# Refine GLB framing for the current v0.8 mobile source.
p = Path('lib/avatar/avatar_stage.dart')
s = p.read_text()
repls = {
    'widget.compact ? 31 : 34,': 'widget.compact ? 30 : 33,',
    'threeJs.camera.position.setValues(0, 0, widget.compact ? 3.45 : 3.25);': 'threeJs.camera.position.setValues(0, 0, widget.compact ? 3.55 : 3.35);',
    'r.position.y -= center.y - (size.y * 0.07);': 'r.position.y -= center.y - (size.y * 0.03);',
    '_baseScale = (widget.compact ? 2.75 : 2.92) / maxDim;': '_baseScale = (widget.compact ? 1.52 : 1.72) / maxDim;',
    'borderRadius: BorderRadius.circular(2),': 'borderRadius: BorderRadius.zero,',
}
for old, new in repls.items():
    if old not in s:
        raise SystemExit(f'avatar_stage expected block not found: {old}')
    s = s.replace(old, new)
p.write_text(s)

# Make all remaining assistant panels fully square.
p = Path('lib/ui/assistant_page.dart')
s = p.read_text()
s = s.replace('BorderRadius.circular(3)', 'BorderRadius.zero')
s = s.replace('BorderRadius.circular(2)', 'BorderRadius.zero')
p.write_text(s)
