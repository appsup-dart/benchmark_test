import 'dart:convert';
import 'dart:io';

import 'package:benchmark_test/src/benchmark/benchmark_baseline_store.dart';
import 'package:benchmark_test/src/benchmark/benchmark_result.dart';
import 'package:test/test.dart';

void main() {
  group('BenchmarkBaselineStore', () {
    test('stores compiler in baseline entries', () {
      final temp = Directory.systemTemp.createTempSync('benchmark_test_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}/baselines.json');
      final store = BenchmarkBaselineStore(file);

      store.updateBenchmarks([
        _result(name: 'parse json', compiler: 'jit', ops: 100),
      ]);

      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final benchmarks = decoded['benchmarks'] as Map<String, dynamic>;
      final entry = benchmarks['jit::parse json'] as Map<String, dynamic>;
      expect(entry['compiler'], 'jit');
    });

    test('compares only against matching compiler baseline', () {
      final temp = Directory.systemTemp.createTempSync('benchmark_test_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}/baselines.json');
      final store = BenchmarkBaselineStore(file);

      store.updateBenchmarks([
        _result(name: 'parse json', compiler: 'aot', ops: 200),
      ]);

      final lines = store.formatComparison(
        _result(name: 'parse json', compiler: 'jit', ops: 100),
      );
      expect(lines.join('\n'), contains('Baseline: none'));
    });
  });
}

BenchmarkResult _result({
  required String name,
  required String compiler,
  required double ops,
}) {
  return BenchmarkResult(
    name: name,
    compiler: compiler,
    operationsPerSecond: ops,
    relativeMarginOfError: 1.0,
    runs: 10,
    averageDuration: const Duration(microseconds: 100),
  );
}
