import '../net/tablet_web_search.dart';

/// A conservative, device-local evidence filter.
///
/// This is NOT semantic fact-checking. It only prevents ungrounded outputs
/// and unrelated search snippets from being classified as trusted knowledge.
/// A future independent verifier can implement [EvidenceGate] without
/// changing DreamPulseEngine or the Android application.
abstract class EvidenceGate {
  const EvidenceGate();

  EvidenceAssessment assess({
    required String question,
    required String answer,
    required List<SearchHit> sources,
  });
}

class EvidenceAssessment {
  const EvidenceAssessment({
    required this.supportedHosts,
    required this.reason,
  });

  final int supportedHosts;
  final String reason;

  bool get sourceSupported => supportedHosts >= 2;
}

class ConservativeEvidenceGate extends EvidenceGate {
  const ConservativeEvidenceGate();

  static const Set<String> _stopwords = {
    'который', 'которая', 'которые', 'которое', 'потому', 'может',
    'можно', 'также', 'этого', 'этот', 'такая', 'такие', 'очень',
    'через', 'после', 'между', 'будет', 'были', 'было', 'является',
    'about', 'which', 'these', 'those', 'there', 'their',
    'with', 'from', 'that', 'this', 'have', 'will',
  };

  @override
  EvidenceAssessment assess({
    required String question,
    required String answer,
    required List<SearchHit> sources,
  }) {
    final questionTerms = _terms(question);
    final answerTerms = _terms(answer).difference(questionTerms);
    if (questionTerms.isEmpty || answerTerms.length < 2) {
      return const EvidenceAssessment(
        supportedHosts: 0,
        reason: 'insufficient_claim_terms',
      );
    }

    final sourceDomains = <String>{};
    final minQuestionOverlap = questionTerms.length >= 2 ? 2 : 1;

    for (final source in sources) {
      final uri = Uri.tryParse(source.url);
      if (uri == null || uri.scheme.toLowerCase() != 'https') continue;
      final domain = _domain(uri.host);
      if (domain.isEmpty || sourceDomains.contains(domain)) continue;
      if (source.snippet.trim().length < 32) continue;

      final sourceTerms = _terms('${source.title} ${source.snippet}');
      if (sourceTerms.intersection(questionTerms).length < minQuestionOverlap) {
        continue;
      }
      // Require at least two non-question terms from the claimed answer
      // in each independent search result.
      if (sourceTerms.intersection(answerTerms).length < 2) continue;
      sourceDomains.add(domain);
    }

    return EvidenceAssessment(
      supportedHosts: sourceDomains.length,
      reason: sourceDomains.length >= 2
          ? 'two_independent_relevant_snippets'
          : 'independent_support_not_found',
    );
  }

  Set<String> _terms(String value) => RegExp(
        r'[a-zа-яё0-9]{4,}',
        caseSensitive: false,
      )
          .allMatches(value.toLowerCase())
          .map((match) => match.group(0)!)
          .where((word) => !_stopwords.contains(word))
          .toSet();

  // Group common subdomains; imperfect for the whole public suffix list,
  // but prevents counting foo.example.com and bar.example.com separately.
  String _domain(String host) {
    final clean = host.toLowerCase().replaceFirst(RegExp(r'^www\\.'), '');
    if (clean.isEmpty || clean == 'localhost') return '';
    final parts = clean.split('.');
    if (parts.length < 2 || parts.any((part) => part.isEmpty)) return '';
    if (parts.every((part) => int.tryParse(part) != null)) return '';
    if (parts.length >= 3 &&
        const {'co.uk', 'org.uk', 'com.au', 'co.jp'}
            .contains(parts.sublist(parts.length - 2).join('.'))) {
      return parts.sublist(parts.length - 3).join('.');
    }
    return parts.sublist(parts.length - 2).join('.');
  }
}
