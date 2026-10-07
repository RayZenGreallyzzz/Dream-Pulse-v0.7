from pathlib import Path

p = Path('lib/llm/deepseek_api_backend.dart')
s = p.read_text()
s = s.replace(
    "..set(HttpHeaders.contentTypeHeader, 'application/json')",
    "..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')",
)
old = """      request.write(jsonEncode({
        'model': 'deepseek-flash',
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'stream': true,
        'thinking': {
          'type': thinking ? 'enabled' : 'disabled',
        },
        'max_tokens': thinking ? 2048 : 1024,
      }));"""
new = """      request.add(utf8.encode(jsonEncode({
        'model': 'deepseek-flash',
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'stream': true,
        'thinking': {
          'type': thinking ? 'enabled' : 'disabled',
        },
        'max_tokens': thinking ? 2048 : 1024,
      })));"""
if old not in s:
    raise SystemExit('DeepSeek request.write block not found')
s = s.replace(old, new)
p.write_text(s)
