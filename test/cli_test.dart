import 'package:benchmark_test/src/cli.dart';
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
          arguments: const [
            '--platform',
            'vm',
            '--compiler',
            'kernel',
          ],
          environment: const {'BENCHMARK_COMPILE_TYPE': 'jit'},
        ),
        _RunCall(
          arguments: const [
            '--platform',
            'vm',
            '--compiler',
            'exe',
          ],
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
          'test/benchmarks_test.dart',
          '--',
          '-n',
          'parse json',
        ],
        runDartTest: runner.call,
        printStatus: (_) {},
      );

      expect(exitCode, 0);
      expect(runner.calls, [
        _RunCall(
          arguments: const [
            '--platform',
            'vm',
            '--compiler',
            'kernel',
            'test/benchmarks_test.dart',
            '-n',
            'parse json',
          ],
          environment: const {'BENCHMARK_COMPILE_TYPE': 'jit'},
        ),
        _RunCall(
          arguments: const [
            '--platform',
            'vm',
            '--compiler',
            'exe',
            'test/benchmarks_test.dart',
            '-n',
            'parse json',
          ],
          environment: const {'BENCHMARK_COMPILE_TYPE': 'aot'},
        ),
      ]);
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
      expect(runner.calls, [
        _RunCall(
          arguments: const [
            '--platform',
            'vm',
            '--compiler',
            'kernel',
            'test/benchmarks_test.dart',
          ],
          environment: const {
            'BENCHMARK_COMPILE_TYPE': 'jit',
            'BENCHMARK_OUTPUT': 'jsonl',
          },
        ),
      ]);
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

class _RecordingRunner {
  final List<int> exitCodes;
  final calls = <_RunCall>[];

  _RecordingRunner({this.exitCodes = const []});

  Future<int> call(
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    calls.add(
      _RunCall(
        arguments: List.unmodifiable(arguments),
        environment: Map.unmodifiable(environment ?? const {}),
      ),
    );
    if (exitCodes.length >= calls.length) return exitCodes[calls.length - 1];
    return 0;
  }
}

class _RunCall {
  final List<String> arguments;
  final Map<String, String> environment;

  const _RunCall({
    required this.arguments,
    required this.environment,
  });

  @override
  bool operator ==(Object other) {
    return other is _RunCall &&
        _listEquals(arguments, other.arguments) &&
        _mapEquals(environment, other.environment);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(arguments),
        Object.hashAll(
          environment.entries
              .map((entry) => Object.hash(entry.key, entry.value)),
        ),
      );

  @override
  String toString() {
    return '_RunCall(arguments: $arguments, environment: $environment)';
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
