import 'dart:convert';
import 'dart:io';

class SearchHit {
  const SearchHit({required this.title, required this.url, required this.snippet});

  final String title;
  final String url;
  final String snippet;

  String get host {
    try {
      return Uri.parse(url).host.toLowerCase().replaceFirst('www.', '');
    } catch (_) {
      return '';
    }
  }
}

/// Lightweight HTTPS-only search worker for the tablet.
/// It keeps results ephemeral; Dream Pulse Core decides later what, if
/// anything, is safe enough to persist.
class TabletWebSearch {
  Future<List<SearchHit>> search(String query, {int limit = 4}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    try {
      final html = await _getText(
        Uri.https('html.duckduckgo.com', '/html/', {'q': q}),
      );
      final hits = _parseDuckDuckGo(html, limit);
      if (hits.isNotEmpty) return hits;
    } catch (_) {}

    try {
      final hits = await _duckDuckGoInstant(q, limit);
      if (hits.isNotEmpty) return hits;
    } catch (_) {}

    try {
      final hits = await _bingHtml(q, limit);
      if (hits.isNotEmpty) return hits;
    } catch (_) {}

    try {
      return await _wikipediaFallback(q, limit);
    } catch (_) {
      return const [];
    }
  }

  String evidenceText(List<SearchHit> hits, {int maxChars = 3600}) {
    if (hits.isEmpty) return '';
    final out = StringBuffer();
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      out.writeln('[${i + 1}] ${h.title}');
      if (h.snippet.isNotEmpty) out.writeln(h.snippet);
      out.writeln('SOURCE: ${h.url}');
      out.writeln();
      if (out.length >= maxChars) break;
    }
    final text = out.toString();
    return text.length <= maxChars ? text : text.substring(0, maxChars);
  }

  Future<String> _getText(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(uri);
      req.headers
        ..set(HttpHeaders.userAgentHeader,
            'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 DreamPulse/0.9')
        ..set(HttpHeaders.acceptLanguageHeader, 'ru,en;q=0.8');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${res.statusCode}', uri: uri);
      }
      return await res.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  List<SearchHit> _parseDuckDuckGo(String html, int limit) {
    final links = RegExp(
      r'<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html).toList();
    final snippets = RegExp(
      r'<(?:a|div)[^>]*class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</(?:a|div)>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html).toList();

    final out = <SearchHit>[];
    for (var i = 0; i < links.length && out.length < limit; i++) {
      final rawUrl = _decodeEntities(links[i].group(1) ?? '');
      final url = _unwrapDuckDuckGoUrl(rawUrl);
      if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
      final title = _cleanHtml(links[i].group(2) ?? '');
      final snippet = i < snippets.length ? _cleanHtml(snippets[i].group(1) ?? '') : '';
      if (title.isEmpty) continue;
      out.add(SearchHit(title: title, url: url, snippet: snippet));
    }
    return out;
  }

  Future<List<SearchHit>> _bingHtml(String query, int limit) async {
    final html = await _getText(
      Uri.https('www.bing.com', '/search', {'q': query, 'setlang': 'ru'}),
    );

    final blocks = RegExp(
      r'<li[^>]*class="[^"]*b_algo[^"]*"[^>]*>([\s\S]*?)</li>',
      caseSensitive: false,
    ).allMatches(html);

    final out = <SearchHit>[];
    for (final block in blocks) {
      if (out.length >= limit) break;
      final body = block.group(1) ?? '';
      final link = RegExp(
        r'<h2[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>',
        caseSensitive: false,
      ).firstMatch(body);
      if (link == null) continue;

      final url = _decodeEntities(link.group(1) ?? '');
      if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
      final title = _cleanHtml(link.group(2) ?? '');
      final p = RegExp(
        r'<p[^>]*>([\s\S]*?)</p>',
        caseSensitive: false,
      ).firstMatch(body);
      final snippet = p == null ? '' : _cleanHtml(p.group(1) ?? '');
      if (title.isEmpty) continue;
      out.add(SearchHit(title: title, url: url, snippet: snippet));
    }
    return out;
  }

  Future<List<SearchHit>> _duckDuckGoInstant(String query, int limit) async {
    final body = await _getText(Uri.https('api.duckduckgo.com', '/', {
      'q': query,
      'format': 'json',
      'no_html': '1',
      'no_redirect': '1',
      'skip_disambig': '1',
    }));
    final json = jsonDecode(body) as Map<String, dynamic>;
    final out = <SearchHit>[];
    final abstract = (json['AbstractText'] ?? '').toString().trim();
    final abstractUrl = (json['AbstractURL'] ?? '').toString().trim();
    if (abstract.isNotEmpty && abstractUrl.isNotEmpty) {
      out.add(SearchHit(
        title: (json['Heading'] ?? query).toString(),
        url: abstractUrl,
        snippet: abstract,
      ));
    }
    final related = json['RelatedTopics'];
    if (related is List) {
      for (final item in related) {
        if (out.length >= limit) break;
        if (item is! Map) continue;
        final text = (item['Text'] ?? '').toString().trim();
        final url = (item['FirstURL'] ?? '').toString().trim();
        if (text.isEmpty || url.isEmpty) continue;
        out.add(SearchHit(title: text.split(' - ').first, url: url, snippet: text));
      }
    }
    return out;
  }

  Future<List<SearchHit>> _wikipediaFallback(String query, int limit) async {
    final body = await _getText(Uri.https('ru.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'list': 'search',
      'srsearch': query,
      'format': 'json',
      'utf8': '1',
      'srlimit': '$limit',
    }));
    final json = jsonDecode(body) as Map<String, dynamic>;
    final queryMap = json['query'];
    if (queryMap is! Map) return const [];
    final rows = queryMap['search'];
    if (rows is! List) return const [];
    return rows.whereType<Map>().take(limit).map((row) {
      final title = (row['title'] ?? '').toString();
      return SearchHit(
        title: title,
        url: Uri.https('ru.wikipedia.org', '/wiki/${title.replaceAll(' ', '_')}').toString(),
        snippet: _cleanHtml((row['snippet'] ?? '').toString()),
      );
    }).where((h) => h.title.isNotEmpty).toList();
  }

  String _unwrapDuckDuckGoUrl(String raw) {
    var value = raw;
    if (value.startsWith('//')) value = 'https:$value';
    try {
      final uri = Uri.parse(value);
      final wrapped = uri.queryParameters['uddg'];
      if (wrapped != null && wrapped.isNotEmpty) return wrapped;
    } catch (_) {}
    return value;
  }

  String _cleanHtml(String value) {
    final noTags = value.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return _decodeEntities(noTags).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _decodeEntities(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');
}
