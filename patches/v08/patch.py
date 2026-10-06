from pathlib import Path

# Refine GLB framing and lighting without touching the loader/runtime API.
p = Path('lib/avatar/avatar_stage.dart')
s = p.read_text()
repls = {
    'widget.compact ? 31 : 34,': 'widget.compact ? 30 : 33,',
    'threeJs.camera.position.setValues(0, 0, widget.compact ? 3.45 : 3.25);': 'threeJs.camera.position.setValues(0, 0, widget.compact ? 3.55 : 3.35);',
    'three.AmbientLight(0xffffff, 1.35)': 'three.AmbientLight(0xffffff, 1.05)',
    'three.DirectionalLight(0xffe8ff, 2.1)': 'three.DirectionalLight(0xfff4ff, 1.55)',
    'three.DirectionalLight(0x8f7cff, 1.25)': 'three.DirectionalLight(0x8f7cff, 0.95)',
    'three.DirectionalLight(0x6edcff, 0.55)': 'three.DirectionalLight(0x6edcff, 0.38)',
    'r.position.y -= center.y;': 'r.position.y -= center.y - (size.y * 0.03);',
    '_baseScale = (widget.compact ? 2.45 : 2.60) / maxDim;': '_baseScale = (widget.compact ? 1.52 : 1.72) / maxDim;',
    'borderRadius: BorderRadius.circular(widget.compact ? 30 : 34),': 'borderRadius: BorderRadius.zero,',
    'Color(0xFF261B42),\n                    Color(0xFF11131D),\n                    Color(0xFF090B11),': 'Color(0xFF18152E),\n                    Color(0xFF0B0F16),\n                    Color(0xFF06080C),',
    'borderRadius: BorderRadius.circular(20),': 'borderRadius: BorderRadius.zero,',
}
for old, new in repls.items():
    if old not in s:
        raise SystemExit(f'avatar_stage expected block not found: {old}')
    s = s.replace(old, new)
p.write_text(s)

# Remove the remaining rounded/card look from the assistant screen.
p = Path('lib/ui/assistant_page.dart')
s = p.read_text()
repls = {
    'showDragHandle: true,': 'showDragHandle: false,',
    "backgroundColor: const Color(0xFF151720),": "backgroundColor: const Color(0xFF0D1016),",
    "color: const Color(0xFF181923),\n                  borderRadius: BorderRadius.circular(30),": "color: const Color(0xFF0F1219),\n                  borderRadius: BorderRadius.zero,",
    "colors: [Color(0xFF232033), Color(0xFF171821)],": "colors: [Color(0xFF15172A), Color(0xFF0D1016)],",
    'borderRadius: BorderRadius.circular(28),': 'borderRadius: BorderRadius.zero,',
    "border: Border.all(color: const Color(0xFF343447)),": "border: Border.all(color: const Color(0xFF313747)),",
    'borderRadius: BorderRadius.circular(16),': 'borderRadius: BorderRadius.zero,',
    'borderRadius: BorderRadius.circular(20),': 'borderRadius: BorderRadius.zero,',
    "color: const Color(0xFF171822),": "color: const Color(0xFF0F1219),",
    "color: message.user ? const Color(0xFF3B2F65) : const Color(0xFF191C28),": "color: message.user ? const Color(0xFF211D3B) : const Color(0xFF10141C),",
}
for old, new in repls.items():
    if old not in s:
        continue
    s = s.replace(old, new)

old_bubble = '''          borderRadius: BorderRadius.only(\n            topLeft: const Radius.circular(22),\n            topRight: const Radius.circular(22),\n            bottomLeft: Radius.circular(message.user ? 22 : 7),\n            bottomRight: Radius.circular(message.user ? 7 : 22),\n          ),'''
if old_bubble in s:
    s = s.replace(old_bubble, '          borderRadius: BorderRadius.zero,')
p.write_text(s)
