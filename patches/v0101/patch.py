from pathlib import Path

# Current official DeepSeek V4.1 Flash model id.
p = Path('lib/llm/deepseek_api_backend.dart')
s = p.read_text()
s = s.replace("deepseek-v4-flash", "deepseek-flash")
s = s.replace("DeepSeek V4 Flash", "DeepSeek V4.1 Flash")
p.write_text(s)

# Keep launch label aligned with the real build.
p = Path('lib/ui/launch_gate.dart')
s = p.read_text().replace("v0.10", "v0.10.1")
p.write_text(s)
