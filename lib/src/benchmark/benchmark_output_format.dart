import 'dart:convert';

import 'benchmark_baseline_store.dart';
import 'benchmark_result.dart';

enum BenchmarkOutputFormat {
  human,
  benchmarkjs,
  ndjson;

  static BenchmarkOutputFormat fromEnvironment(String? value) {
    switch (value?.toLowerCase()) {
      case null:
      case '':
      case 'human':
        return human;
      case 'benchmarkjs':
      case 'benchmark-js':
      case 'benchmark_js':
        return benchmarkjs;
      case 'ndjson':
      case 'jsonl':
        return ndjson;
      default:
        throw ArgumentError.value(
          value,
          'BENCHMARK_OUTPUT',
          'Expected `human`, `benchmarkjs`, or `ndjson`.',
        );
    }
  }

  String format(
    BenchmarkResult result, {
    required BenchmarkBaselineStore baselineStore,
  }) {
    switch (this) {
      case human:
        var lines = [
          'Benchmark: ${result.name}',
          '  ${result.formattedOperationsPerSecond} ops/sec',
          '  ±${result.formattedRelativeMarginOfError}% margin of error',
          '  ${result.runs} runs sampled',
          '  ${result.averageDuration} average duration',
        ];
        lines.addAll(baselineStore.formatComparison(result));
        return lines.join('\n');
      case benchmarkjs:
        return '${result.name} x ${result.formattedOperationsPerSecond} '
            'ops/sec ±${result.formattedRelativeMarginOfError}% '
            '(${result.runs} runs sampled)';
      case ndjson:
        return jsonEncode(result.toJson());
    }
  }
}
