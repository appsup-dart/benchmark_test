import 'dart:io';

import 'package:test/test.dart';

import '../tool/github_action/benchmark_action_results.dart';

void main() {
  group('github action benchmark results', () {
    test('converts benchmark JSONL to custom benchmark-action JSON', () {
      final temp = Directory.systemTemp.createTempSync('benchmark_test_');
      addTearDown(() => temp.deleteSync(recursive: true));

      final input = File('${temp.path}/jit.jsonl')..writeAsStringSync('''
Running benchmarks with jit...
{"formatVersion":1,"name":"parse json","throughput":{"value":123.4,"unit":"ops/sec"},"statistics":{"relativeMarginOfError":1.23,"samples":10},"latency":{"mean":8100,"unit":"microseconds"}}
''');

      final results = convertBenchmarkActionResults([
        BenchmarkInput('jit', input),
      ]);

      expect(results, [
        {
          'name': 'parse json [jit]',
          'unit': 'ops/sec',
          'value': 123.4,
          'range': '±1.23%',
          'extra': 'compile: jit\nsamples: 10\nmean latency: 8100 microseconds',
        },
      ]);
    });

    test('keeps compile types as separate benchmark names', () {
      final temp = Directory.systemTemp.createTempSync('benchmark_test_');
      addTearDown(() => temp.deleteSync(recursive: true));

      final jit = File('${temp.path}/jit.jsonl')
        ..writeAsStringSync(
          '{"name":"parse json","throughput":{"value":100,"unit":"ops/sec"}}\n',
        );
      final aot = File('${temp.path}/aot.jsonl')
        ..writeAsStringSync(
          '{"name":"parse json","throughput":{"value":200,"unit":"ops/sec"}}\n',
        );

      final results = convertBenchmarkActionResults([
        BenchmarkInput('jit', jit),
        BenchmarkInput('aot', aot),
      ]);

      expect(
        results.map((result) => result['name']),
        ['parse json [jit]', 'parse json [aot]'],
      );
    });

    test('requires at least one benchmark result', () {
      final temp = Directory.systemTemp.createTempSync('benchmark_test_');
      addTearDown(() => temp.deleteSync(recursive: true));

      final input = File('${temp.path}/empty.jsonl')
        ..writeAsStringSync('No benchmark lines here\n');

      expect(
        () => convertBenchmarkActionResults([BenchmarkInput('jit', input)]),
        throwsFormatException,
      );
    });
  });
}
