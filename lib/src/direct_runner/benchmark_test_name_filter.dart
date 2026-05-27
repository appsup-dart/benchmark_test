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
      // Properly encode the pattern for use within a Dart raw string literal.
      // We use r'''...''' as the most general raw string solution,
      // and escape only triple-quotes if they appear.
      final pattern = filter.pattern.replaceAll("'''", r"\'\'\'");
      return "RegExp(r'''$pattern''')";
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
