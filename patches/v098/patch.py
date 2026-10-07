from pathlib import Path

for path in [
    'lib/ui/assistant_shell.dart',
    'lib/ui/assistant_page.dart',
    'lib/ui/launch_gate.dart',
]:
    p = Path(path)
    s = p.read_text()
    s = s.replace('v0.9.7 SMART', 'v0.9.8 LIVE TRACE')
    s = s.replace('v0.9.7', 'v0.9.8')
    p.write_text(s)
