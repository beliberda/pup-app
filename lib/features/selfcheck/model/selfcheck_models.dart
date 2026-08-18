enum CheckStatus { good, warning, bad, info, error }

class SelfCheckItem {
  const SelfCheckItem({required this.id, required this.status, required this.detail});

  final String id;
  final CheckStatus status;
  final String detail;
}

class SelfCheckReport {
  const SelfCheckReport({required this.items, required this.generatedAt});

  final List<SelfCheckItem> items;
  final DateTime generatedAt;

  /// Overall verdict, ignoring info/error-only rows (those aren't pass/fail signals).
  CheckStatus get verdict {
    final relevant = items.where((e) => e.status == CheckStatus.good || e.status == CheckStatus.warning || e.status == CheckStatus.bad);
    if (relevant.any((e) => e.status == CheckStatus.bad)) return CheckStatus.bad;
    if (relevant.any((e) => e.status == CheckStatus.warning)) return CheckStatus.warning;
    if (relevant.isEmpty) return CheckStatus.info;
    return CheckStatus.good;
  }
}
