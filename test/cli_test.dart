import 'dart:io';

import 'package:benchmark_test/src/cli.dart';
import 'package:benchmark_test/src/cli/benchmark_cli_output.dart';
import 'package:benchmark_test/src/direct_runner/benchmark_test_invocation.dart';
import 'package:benchmark_test/src/direct_runner/benchmark_test_name_filter.dart';
import 'package:benchmark_test/src/direct_runner/process_runner.dart';
import 'package:benchmark_test/src/benchmark/benchmark_baseline_store.dart';
import 'package:test/test.dart';

void main() {
  group('benchmark cli', () {
    test('runs jit by default', () async {
      final runner = _RecordingRunner();

      final exitCode = await _runBenchmarkCliQuiet(
        const [],
        runDartTest: runner.call,
      );

      expect(exitCode, 0);
      expect(runner.calls, [
        _RunCall(
          invocation: const BenchmarkTestInvocation(
            compiler: 'kernel',
            enableAsserts: false,
            runSkipped: false,
            profile: false,
            paths: [],
            nameFilter: null,
          ),
          captureStdout: true,
          forwardStdout: false,
        ),
      ]);
    });

    test('accepts repeated and comma-separated compile types', () async {
      final runner = _RecordingRunner();

      final exitCode = await _runBenchmarkCliQuiet(
        const [
          '--compile',
          'jit',
          '--compile=aot,jit',
          '--name',
          'parse json',
          'test/benchmarks_test.dart',
        ],
        runDartTest: runner.call,
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

    test('accepts js compile type', () async {
      final runner = _RecordingRunner();

      final exitCode = await _runBenchmarkCliQuiet(
        const [
          '--compile',
          'js',
          'test/benchmarks_test.dart',
        ],
        runDartTest: runner.call,
      );

      expect(exitCode, 0);
      expect(runner.calls, hasLength(1));
      expect(runner.calls.single.invocation.compiler, 'js');
    });

    test('accepts wasm compile type', () async {
      final runner = _RecordingRunner();

      final exitCode = await _runBenchmarkCliQuiet(
        const [
          '--compile',
          'wasm',
          'test/benchmarks_test.dart',
        ],
        runDartTest: runner.call,
      );

      expect(exitCode, 0);
      expect(runner.calls, hasLength(1));
      expect(runner.calls.single.invocation.compiler, 'wasm');
    });

    test('formats captured jsonl runner output for --output', () async {
      final runner = _RecordingRunner(stdout: _sampleBenchmarkJsonl);
      final output = <String>[];

      final exitCode = await _runBenchmarkCliQuiet(
        const [
          '--compile',
          'jit',
          '--output',
          'jsonl',
          'test/benchmarks_test.dart',
        ],
        runDartTest: runner.call,
        printOutput: output.add,
      );

      expect(exitCode, 0);
      expect(runner.calls.single.captureStdout, isTrue);
      expect(output.single, startsWith('{"formatVersion":1'));
    });

    test('passes assertion opt-in to the benchmark runner', () async {
      final runner = _RecordingRunner();

      final exitCode = await _runBenchmarkCliQuiet(
        const [
          '--compile',
          'jit',
          '--enable-asserts',
          'test/benchmarks_test.dart',
        ],
        runDartTest: runner.call,
      );

      expect(exitCode, 0);
      expect(runner.calls.single.invocation.enableAsserts, isTrue);
    });

    test('passes run-skipped to the benchmark runner', () async {
      final runner = _RecordingRunner();

      final exitCode = await _runBenchmarkCliQuiet(
        const [
          '--compile',
          'jit',
          '--run-skipped',
          'test/benchmarks_test.dart',
        ],
        runDartTest: runner.call,
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

      final exitCode = await _runBenchmarkCliQuiet(
        const [
          '--compile',
          'jit',
          '--update-baseline',
          'test/benchmarks_test.dart',
        ],
        runDartTest: runner.call,
        cliOutput: BenchmarkCliOutput(
          baselineStore: BenchmarkBaselineStore(baselineFile),
          printLine: output.add,
        ),
      );

      expect(exitCode, 0);
      expect(runner.calls.single.captureStdout, isTrue);
      expect(baselineFile.existsSync(), isTrue);
      expect(output.last, contains('Baseline updated: ${baselineFile.path}'));
    });

    test('runs skipped tests when --run-skipped is set', () async {
      final testFile = _writeSkippedTestFile();

      final skippedExitCode = await _runBenchmarkCliQuiet(
        ['--compile', 'jit', testFile.path],
      );
      expect(skippedExitCode, 0);

      final runSkippedExitCode = await _runBenchmarkCliQuiet(
        ['--compile', 'jit', '--run-skipped', testFile.path],
      );
      expect(runSkippedExitCode, 1);
    });

    test('runs benchmark files with assertions disabled by default', () async {
      final benchmarkFile = _writeAssertSensitiveBenchmark();

      final exitCode = await _runBenchmarkCliQuiet(
        ['--compile', 'jit', benchmarkFile.path],
      );

      expect(exitCode, 0);
    });

    test('runs aot benchmark files with assertions disabled by default',
        () async {
      final benchmarkFile = _writeAssertSensitiveBenchmark();

      final exitCode = await _runBenchmarkCliQuiet(
        ['--compile', 'aot', benchmarkFile.path],
      );

      expect(exitCode, 0);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('can opt in to assertions for benchmark files', () async {
      final benchmarkFile = _writeAssertSensitiveBenchmark();

      final exitCode = await _runBenchmarkCliQuiet(
        ['--compile', 'jit', '--enable-asserts', benchmarkFile.path],
      );

      expect(exitCode, 1);
    });

    test('stops after the first failing compile type', () async {
      final runner = _RecordingRunner(exitCodes: [2, 0]);

      final exitCode = await _runBenchmarkCliQuiet(
        const [],
        runDartTest: runner.call,
      );

      expect(exitCode, 2);
      expect(runner.calls, hasLength(1));
    });

    test('passes profile mode to the benchmark runner', () async {
      final runner = _RecordingRunner();
      final status = <String>[];

      final exitCode = await _runBenchmarkCliQuiet(
        const [
          '--profile',
          '--compile',
          'jit',
          '--name',
          '^delay 100ms\$',
          'test/src/benchmark.dart',
        ],
        runDartTest: runner.call,
        printStatus: status.add,
      );

      expect(exitCode, 0);
      expect(runner.calls, hasLength(1));
      expect(runner.calls.single.invocation.profile, isTrue);
      expect(runner.calls.single.invocation.compiler, 'kernel');
      expect(status.first, contains('Profiling benchmarks with jit'));
    });

    test('rejects profile mode with aot', () async {
      final errors = <String>[];

      final exitCode = await _runBenchmarkCliQuiet(
        const ['--profile', '--compile', 'aot'],
        runDartTest: _RecordingRunner().call,
        printError: errors.add,
      );

      expect(exitCode, 64);
      expect(
          errors.first, contains('CPU profiling is only supported with JIT'));
    });

    test('prints usage for unknown compile types', () async {
      final errors = <String>[];

      final exitCode = await _runBenchmarkCliQuiet(
        const ['--compile', 'wat'],
        runDartTest: _RecordingRunner().call,
        printError: errors.add,
      );

      expect(exitCode, 64);
      expect(errors.first, contains('Unsupported compile type `wat`'));
    });
  });
}

Future<int> _runBenchmarkCliQuiet(
  List<String> arguments, {
  DartTestRunner? runDartTest,
  BenchmarkCliOutput? cliOutput,
  void Function(String line)? printStatus,
  void Function(String line)? printUsage,
  void Function(String line)? printError,
  void Function(String line)? printOutput,
}) {
  return runBenchmarkCli(
    arguments,
    runDartTest: runDartTest,
    cliOutput: cliOutput,
    forwardChildOutput: false,
    printStatus: printStatus ?? _discardLine,
    printUsage: printUsage ?? _discardLine,
    printError: printError ?? _discardLine,
    printOutput: printOutput ?? _discardLine,
  );
}

void _discardLine(String _) {}

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
    bool captureStdout = false,
    bool forwardStdout = false,
  }) async {
    calls.add(
      _RunCall(
        invocation: invocation,
        captureStdout: captureStdout,
        forwardStdout: forwardStdout,
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
  final bool captureStdout;
  final bool forwardStdout;

  const _RunCall({
    required this.invocation,
    required this.captureStdout,
    required this.forwardStdout,
  });

  @override
  bool operator ==(Object other) {
    return other is _RunCall &&
        invocation.compiler == other.invocation.compiler &&
        invocation.enableAsserts == other.invocation.enableAsserts &&
        invocation.runSkipped == other.invocation.runSkipped &&
        invocation.profile == other.invocation.profile &&
        _listEquals(invocation.paths, other.invocation.paths) &&
        invocation.nameFilter == other.invocation.nameFilter &&
        captureStdout == other.captureStdout &&
        forwardStdout == other.forwardStdout;
  }

  @override
  int get hashCode => Object.hash(
        invocation.compiler,
        invocation.enableAsserts,
        invocation.runSkipped,
        invocation.profile,
        Object.hashAll(invocation.paths),
        invocation.nameFilter,
        captureStdout,
        forwardStdout,
      );

  @override
  String toString() {
    return '_RunCall(invocation: $invocation, captureStdout: $captureStdout, forwardStdout: $forwardStdout)';
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
