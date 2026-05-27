import 'dart:io';

import 'package:benchmark_test/src/cli.dart';
import 'package:benchmark_test/src/cli/benchmark_baseline_updater.dart';
import 'package:benchmark_test/src/direct_runner/benchmark_test_invocation.dart';
import 'package:benchmark_test/src/direct_runner/benchmark_test_name_filter.dart';
import 'package:benchmark_test/src/direct_runner/process_runner.dart';
import 'package:benchmark_test/src/benchmark/benchmark_baseline_store.dart';
import 'package:test/test.dart';

void main() {
  group('benchmark cli', () {
    test('runs jit and aot by default', () async {
      final runner = _RecordingRunner();

      final exitCode = await runBenchmarkCli(
        const [],
        runDartTest: runner.call,
        printStatus: (_) {},
      );

      expect(exitCode, 0);
      expect(runner.calls, [
        _RunCall(
          invocation: const BenchmarkTestInvocation(
            compiler: 'kernel',
            enableAsserts: false,
            runSkipped: false,
            paths: [],
            nameFilter: null,
          ),
          environment: const {'BENCHMARK_COMPILE_TYPE': 'jit'},
          captureStdout: false,
        ),
        _RunCall(
          invocation: const BenchmarkTestInvocation(
            compiler: 'exe',
            enableAsserts: false,
            runSkipped: false,
            paths: [],
            nameFilter: null,
          ),
          environment: const {'BENCHMARK_COMPILE_TYPE': 'aot'},
          captureStdout: false,
        ),
      ]);
    });

    test('accepts repeated and comma-separated compile types', () async {
      final runner = _RecordingRunner();

      final exitCode = await runBenchmarkCli(
        const [
          '--compile',
          'jit',
          '--compile=aot,jit',
          '--name',
          'parse json',
          'test/benchmarks_test.dart',
        ],
        runDartTest: runner.call,
        printStatus: (_) {},
      );

      expect(exitCode, 0);
      expect(runner.calls.first.invocation.compiler, 'kernel');
      expect(
          runner.calls.first.invocation.paths, ['test/benchmarks_test.dart']);
      expect(
        runner.calls.first.invocation.nameFilter,
        isA<BenchmarkPatternNameFilter>().having(
          (filter) => filter.pattern,
          'pattern',
          'parse json',
        ),
      );
    });

    test('passes output format through the benchmark environment', () async {
      final runner = _RecordingRunner();

      final exitCode = await runBenchmarkCli(
        const [
          '--compile',
          'jit',
          '--output',
          'jsonl',
          'test/benchmarks_test.dart',
        ],
        runDartTest: runner.call,
        printStatus: (_) {},
      );

      expect(exitCode, 0);
      expect(runner.calls.single.environment, {
        'BENCHMARK_COMPILE_TYPE': 'jit',
        'BENCHMARK_OUTPUT': 'jsonl',
      });
    });

    test('passes assertion opt-in to the benchmark runner', () async {
      final runner = _RecordingRunner();

      final exitCode = await runBenchmarkCli(
        const [
          '--compile',
          'jit',
          '--enable-asserts',
          'test/benchmarks_test.dart',
        ],
        runDartTest: runner.call,
        printStatus: (_) {},
      );

      expect(exitCode, 0);
      expect(runner.calls.single.invocation.enableAsserts, isTrue);
    });

    test('passes run-skipped to the benchmark runner', () async {
      final runner = _RecordingRunner();

      final exitCode = await runBenchmarkCli(
        const [
          '--compile',
          'jit',
          '--run-skipped',
          'test/benchmarks_test.dart',
        ],
        runDartTest: runner.call,
        printStatus: (_) {},
      );

      expect(exitCode, 0);
      expect(runner.calls.single.invocation.runSkipped, isTrue);
    });

    test('updates baselines from captured jsonl runner output', () async {
      final temp = Directory.systemTemp.createTempSync('benchmark_test_cli_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final baselineFile = File('${temp.path}/baselines.json');
      final runner = _RecordingRunner(stdout: _sampleBenchmarkJsonl);
      final output = <String>[];

      final exitCode = await runBenchmarkCli(
        const [
          '--compile',
          'jit',
          '--update-baseline',
          'test/benchmarks_test.dart',
        ],
        runDartTest: runner.call,
        printStatus: (_) {},
        baselineUpdater: BenchmarkBaselineUpdater(
          baselineStore: BenchmarkBaselineStore(baselineFile),
          printLine: output.add,
        ),
      );

      expect(exitCode, 0);
      expect(runner.calls.single.captureStdout, isTrue);
      expect(runner.calls.single.environment, {
        'BENCHMARK_COMPILE_TYPE': 'jit',
        'BENCHMARK_OUTPUT': 'jsonl',
      });
      expect(baselineFile.existsSync(), isTrue);
      expect(output.last, contains('Baseline updated: ${baselineFile.path}'));
    });

    test('runs skipped tests when --run-skipped is set', () async {
      final testFile = _writeSkippedTestFile();

      final skippedExitCode = await runBenchmarkCli(
        ['--compile', 'jit', testFile.path],
        printStatus: (_) {},
      );
      expect(skippedExitCode, 0);

      final runSkippedExitCode = await runBenchmarkCli(
        ['--compile', 'jit', '--run-skipped', testFile.path],
        printStatus: (_) {},
      );
      expect(runSkippedExitCode, 1);
    });

    test('runs benchmark files with assertions disabled by default', () async {
      final benchmarkFile = _writeAssertSensitiveBenchmark();

      final exitCode = await runBenchmarkCli(
        ['--compile', 'jit', benchmarkFile.path],
        printStatus: (_) {},
      );

      expect(exitCode, 0);
    });

    test('runs aot benchmark files with assertions disabled by default',
        () async {
      final benchmarkFile = _writeAssertSensitiveBenchmark();

      final exitCode = await runBenchmarkCli(
        ['--compile', 'aot', benchmarkFile.path],
        printStatus: (_) {},
      );

      expect(exitCode, 0);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('can opt in to assertions for benchmark files', () async {
      final benchmarkFile = _writeAssertSensitiveBenchmark();

      final exitCode = await runBenchmarkCli(
        ['--compile', 'jit', '--enable-asserts', benchmarkFile.path],
        printStatus: (_) {},
      );

      expect(exitCode, 1);
    });

    test('stops after the first failing compile type', () async {
      final runner = _RecordingRunner(exitCodes: [2, 0]);

      final exitCode = await runBenchmarkCli(
        const [],
        runDartTest: runner.call,
        printStatus: (_) {},
      );

      expect(exitCode, 2);
      expect(runner.calls, hasLength(1));
    });

    test('prints usage for unknown compile types', () async {
      final errors = <String>[];

      final exitCode = await runBenchmarkCli(
        const ['--compile', 'wasm'],
        runDartTest: _RecordingRunner().call,
        printError: errors.add,
      );

      expect(exitCode, 64);
      expect(errors.first, contains('Unsupported compile type `wasm`'));
    });
  });
}

File _writeSkippedTestFile() {
  final temp = Directory.systemTemp.createTempSync('benchmark_test_cli_');
  addTearDown(() => temp.deleteSync(recursive: true));

  return File('${temp.path}/skipped_test.dart')..writeAsStringSync('''
import 'package:test/test.dart';

void main() {
  test('skipped', () {
    throw StateError('Skipped test ran.');
  }, skip: true);
}
''');
}

File _writeAssertSensitiveBenchmark() {
  final temp = Directory.systemTemp.createTempSync('benchmark_test_cli_');
  addTearDown(() => temp.deleteSync(recursive: true));

  return File('${temp.path}/assert_sensitive_benchmark_test.dart')
    ..writeAsStringSync('''
import 'package:benchmark_test/benchmark_test.dart';

void main() {
  benchmark(
    'assert side effect',
    () {
      var assertionsEnabled = false;
      assert(assertionsEnabled = true);
      if (assertionsEnabled) {
        throw StateError('Assertions were enabled.');
      }
    },
    minDuration: const Duration(microseconds: 1),
    minSamples: 2,
  );
}
''');
}

const _sampleBenchmarkJsonl = '''
{"formatVersion":1,"name":"sample benchmark","throughput":{"value":42,"unit":"ops/sec"},"statistics":{"relativeMarginOfError":1.5,"samples":10},"latency":{"mean":1000,"unit":"microseconds"}}
''';

class _RecordingRunner {
  final List<int> exitCodes;
  final String stdout;
  final calls = <_RunCall>[];

  _RecordingRunner({this.exitCodes = const [], this.stdout = ''});

  Future<ProcessRunResult> call(
    BenchmarkTestInvocation invocation, {
    Map<String, String>? environment,
    bool captureStdout = false,
  }) async {
    calls.add(
      _RunCall(
        invocation: invocation,
        environment: Map.unmodifiable(environment ?? const {}),
        captureStdout: captureStdout,
      ),
    );
    final exitCode =
        exitCodes.length >= calls.length ? exitCodes[calls.length - 1] : 0;
    return ProcessRunResult(
      exitCode: exitCode,
      stdout: captureStdout ? stdout : '',
    );
  }
}

class _RunCall {
  final BenchmarkTestInvocation invocation;
  final Map<String, String> environment;
  final bool captureStdout;

  const _RunCall({
    required this.invocation,
    required this.environment,
    required this.captureStdout,
  });

  @override
  bool operator ==(Object other) {
    return other is _RunCall &&
        invocation.compiler == other.invocation.compiler &&
        invocation.enableAsserts == other.invocation.enableAsserts &&
        invocation.runSkipped == other.invocation.runSkipped &&
        _listEquals(invocation.paths, other.invocation.paths) &&
        invocation.nameFilter == other.invocation.nameFilter &&
        captureStdout == other.captureStdout &&
        _mapEquals(environment, other.environment);
  }

  @override
  int get hashCode => Object.hash(
        invocation.compiler,
        invocation.enableAsserts,
        invocation.runSkipped,
        Object.hashAll(invocation.paths),
        invocation.nameFilter,
        captureStdout,
        Object.hashAll(
          environment.entries
              .map((entry) => Object.hash(entry.key, entry.value)),
        ),
      );

  @override
  String toString() {
    return '_RunCall(invocation: $invocation, environment: $environment)';
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
