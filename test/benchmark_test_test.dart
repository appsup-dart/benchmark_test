import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('benchmark', () {
    test('can update and compare against a human baseline', () {
      _preserveBaseline();

      var update = _runBenchmarkCli(
        const [
          '--compile',
          'jit',
          '--update-baseline',
          '--name',
          '^delay 10ms baseline fixture\$',
          'test/src/benchmark.dart',
        ],
      );

      expect(update.stdout, contains('Benchmark: delay 10ms baseline fixture'));
      expect(update.stdout, contains('Baseline updated: $_baselinePath'));
      expect(File(_baselinePath).existsSync(), isTrue);

      var compare = _runBenchmarkProcess(
        'delay 10ms baseline fixture',
      );

      expect(compare.stdout, contains('Baseline:'));
      expect(compare.stdout, contains('Change:'));
    });

    test('shows icons for significant baseline changes', () {
      _preserveBaseline();

      _writeBaseline(
        name: 'delay 10ms baseline fixture',
        operationsPerSecond: 10,
      );
      var improvement = _runBenchmarkProcess(
        'delay 10ms baseline fixture',
      );
      expect(improvement.stdout, contains('✅ Change:'));
      expect(improvement.stdout, contains('\u001B['));

      _writeBaseline(
        name: 'delay 10ms baseline fixture',
        operationsPerSecond: 1000,
      );
      var regression = _runBenchmarkProcess(
        'delay 10ms baseline fixture',
      );
      expect(regression.stdout, contains('⚠️ Change:'));
    });

    test('can output jsonl through the benchmark cli', () {
      var v = _runBenchmarkCli(
        const [
          '--compile',
          'jit',
          '--output',
          'jsonl',
          '--name',
          '^delay 100ms\$',
          'test/src/benchmark.dart',
        ],
      );

      var jsonLine = v.stdout
          .toString()
          .split('\n')
          .singleWhere((line) => line.startsWith('{"formatVersion"'));
      var result = jsonDecode(jsonLine) as Map<String, dynamic>;

      expect(result['formatVersion'], 1);
      expect(result['name'], 'delay 100ms');

      var throughput = result['throughput'] as Map<String, dynamic>;
      expect(throughput['value'], closeTo(10, 0.5));
      expect(throughput['unit'], 'ops/sec');

      var statistics = result['statistics'] as Map<String, dynamic>;
      expect(statistics['relativeMarginOfError'], isA<num>());
      expect(statistics['samples'], closeTo(20, 1));

      var latency = result['latency'] as Map<String, dynamic>;
      expect(
        latency['mean'],
        closeTo(Duration(milliseconds: 100).inMicroseconds, 20000),
      );
      expect(latency['unit'], 'microseconds');
    });

    test('iteration of 100ms should run about 20 times', () {
      var r = _runBenchmark('delay 100ms');

      expect(r[0], closeTo(10, 0.5));
      expect(r[2], closeTo(20, 1));
    });

    test(
        'iteration of 100ms should run about 40 times when minDuration 4 seconds',
        () {
      var r = _runBenchmark('delay 100ms, minDuration 4 seconds');

      expect(r[0], closeTo(10, 0.5));
      expect(r[2], closeTo(40, 1));
    });

    test('iteration of 100ms should run 30 times when minSamples 30', () {
      var r = _runBenchmark('delay 100ms, minSamples 30');

      expect(r[0], closeTo(10, 0.5));
      expect(r[2], 30);
    });

    test('runs sampled counts measured iterations only', () {
      var r = _runBenchmark('delay 1ms, minSamples 3');

      expect(r[2], 3);
    });
  });

  group('setUpEach', () {
    test('should be called before each iteration', () {
      _runBenchmark('setUpEach group 2 100ms');
    });
  });
  group('tearDownEach', () {
    test('should be called after each iteration', () {
      _runBenchmark('tearDownEach group 2 100ms');
    });
  });
}

List<num> _runBenchmark(String name) {
  var v = _runBenchmarkCli(
    [
      '--compile',
      'jit',
      '--output',
      'benchmarkjs',
      '--name',
      '^${RegExp.escape(name)}\$',
      'test/src/benchmark.dart',
    ],
  );

  var o = _parseOutput(v.stdout);
  if (!o.containsKey(name)) {
    throw Exception('Benchmark failed: ${v.stdout}');
  }
  return o[name]!;
}

ProcessResult _runBenchmarkProcess(
  String name, {
  Map<String, String> environment = const {},
}) {
  return Process.runSync(
    'dart',
    [
      'test',
      'test/src/benchmark.dart',
      '--no-color',
      '-n',
      '^${RegExp.escape(name)}\$',
    ],
    environment: environment,
  );
}

ProcessResult _runBenchmarkCli(List<String> arguments) {
  return Process.runSync(
    Platform.resolvedExecutable,
    ['run', 'benchmark_test', ...arguments],
  );
}

void _writeBaseline({
  required String name,
  required num operationsPerSecond,
}) {
  var file = File(_baselinePath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    jsonEncode({
      'formatVersion': 1,
      'benchmarks': {
        name: {
          'formatVersion': 1,
          'name': name,
          'compiler': 'jit',
          'throughput': {
            'value': operationsPerSecond,
            'unit': 'ops/sec',
          },
          'statistics': {
            'relativeMarginOfError': 0,
            'samples': 10,
          },
          'latency': {
            'mean': 10000,
            'unit': 'microseconds',
          },
        },
      },
    }),
  );
}

void _preserveBaseline() {
  var file = File(_baselinePath);
  var original = file.existsSync() ? file.readAsStringSync() : null;

  addTearDown(() {
    if (original == null) {
      if (file.existsSync()) file.deleteSync();
      return;
    }

    file.parent.createSync(recursive: true);
    file.writeAsStringSync(original);
  });

  if (file.existsSync()) file.deleteSync();
}

Map<String, List<num>> _parseOutput(String output) {
  var lines = output.split('\n');
  var results = <String, List<num>>{};
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    var m =
        RegExp(r'(.*) x ([0-9\.]+) ops/sec ±([0-9\.]+)% \((\d+) runs sampled\)')
            .firstMatch(line);

    if (m != null) {
      var ops = num.parse(m.group(2)!);
      var margin = num.parse(m.group(3)!);
      var runs = num.parse(m.group(4)!);
      results[m.group(1)!] = [ops, margin, runs];
    }
  }
  return results;
}

const _baselinePath = 'build/benchmark_test/baselines.json';
