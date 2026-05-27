import 'dart:convert';

sealed class BenchmarkNameFilter {}

class BenchmarkPatternNameFilter extends BenchmarkNameFilter {
  final String pattern;

  BenchmarkPatternNameFilter(this.pattern);
}

class BenchmarkPlainNameFilter extends BenchmarkNameFilter {
  final String name;

  BenchmarkPlainNameFilter(this.name);
}

extension BenchmarkNameFilterCodegen on BenchmarkNameFilter? {
  String get namePatternSource {
    final filter = this;
    if (filter is BenchmarkPatternNameFilter) {
      return 'RegExp(${jsonEncode(filter.pattern)})';
    }
    return 'null';
  }

  String get plainNameSource {
    final filter = this;
    if (filter is BenchmarkPlainNameFilter) {
      return jsonEncode(filter.name);
    }
    return 'null';
  }
}
