import 'dart:io';

import 'package:benchmark_test/src/cli.dart';
import 'package:benchmark_test/src/direct_runner/benchmark_test_invocation.dart';
import 'package:benchmark_test/src/direct_runner/benchmark_test_name_filter.dart';
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

class _RecordingRunner {
  final List<int> exitCodes;
  final calls = <_RunCall>[];

  _RecordingRunner({this.exitCodes = const []});

  Future<int> call(
    BenchmarkTestInvocation invocation, {
    Map<String, String>? environment,
  }) async {
    calls.add(
      _RunCall(
        invocation: invocation,
        environment: Map.unmodifiable(environment ?? const {}),
      ),
    );
    if (exitCodes.length >= calls.length) return exitCodes[calls.length - 1];
    return 0;
  }
}

class _RunCall {
  final BenchmarkTestInvocation invocation;
  final Map<String, String> environment;

  const _RunCall({
    required this.invocation,
    required this.environment,
  });

  @override
  bool operator ==(Object other) {
    return other is _RunCall &&
        invocation.compiler == other.invocation.compiler &&
        invocation.enableAsserts == other.invocation.enableAsserts &&
        invocation.runSkipped == other.invocation.runSkipped &&
        _listEquals(invocation.paths, other.invocation.paths) &&
        invocation.nameFilter == other.invocation.nameFilter &&
        _mapEquals(environment, other.environment);
  }

  @override
  int get hashCode => Object.hash(
        invocation.compiler,
        invocation.enableAsserts,
        invocation.runSkipped,
        Object.hashAll(invocation.paths),
        invocation.nameFilter,
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
