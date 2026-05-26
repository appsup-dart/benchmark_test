import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';

typedef DartTestRunner = Future<int> Function(
  List<String> arguments, {
  Map<String, String>? environment,
});

Future<int> runBenchmarkCli(
  List<String> arguments, {
  DartTestRunner? runDartTest,
  void Function(String line) printStatus = _stderrWriteln,
  void Function(String line) printUsage = _stdoutWriteln,
  void Function(String line) printError = _stderrWriteln,
}) async {
  final parser = _createArgParser();
  final config = _parseArguments(parser, arguments);
  if (config.showHelp) {
    printUsage(_usage(parser));
    return 0;
  }

  if (config.error != null) {
    printError(config.error!);
    printError('');
    printError(_usage(parser));
    return 64;
  }

  final runner = runDartTest ?? _runDartTest;
  for (final compileType in config.compileTypes) {
    printStatus('Running benchmarks with ${compileType.label}...');

    final exitCode = await runner(
      [
        '--platform',
        'vm',
        '--compiler',
        compileType.testCompiler,
        ...config.paths,
        ...config.testRunnerArguments,
      ],
      environment: {
        'BENCHMARK_COMPILE_TYPE': compileType.label,
        if (config.outputFormat != null)
          'BENCHMARK_OUTPUT': config.outputFormat!,
      },
    );

    if (exitCode != 0) return exitCode;
  }

  return 0;
}

Future<int> _runDartTest(
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['test', ...arguments],
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

ArgParser _createArgParser() {
  return ArgParser()
    ..addMultiOption(
      'compile',
      abbr: 'c',
      aliases: ['compiler'],
      help: 'Compile type to run. Repeat or comma-separate values.',
      valueHelp: 'type',
    )
    ..addOption(
      'output',
      abbr: 'o',
      aliases: ['format'],
      allowed: _benchmarkOutputFormats,
      allowedHelp: const {
        'human': 'Human-readable local development output.',
        'benchmarkjs': 'benchmark.js-compatible output.',
        'jsonl': 'One JSON object per benchmark result.',
      },
      help: 'Benchmark output format.',
      valueHelp: 'format',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this help.',
      negatable: false,
    );
}

_BenchmarkCliConfig _parseArguments(
  ArgParser parser,
  List<String> arguments,
) {
  final separatorIndex = arguments.indexOf('--');
  final cliArguments = separatorIndex == -1
      ? arguments
      : arguments.take(separatorIndex).toList(growable: false);
  final testRunnerArguments = separatorIndex == -1
      ? const <String>[]
      : arguments.skip(separatorIndex + 1).toList(growable: false);

  final ArgResults results;
  try {
    results = parser.parse(cliArguments);
  } on FormatException catch (error) {
    return _BenchmarkCliConfig.error(
      '${error.message}. Pass dart test options after `--`.',
    );
  }

  if (results.flag('help')) {
    return _BenchmarkCliConfig.help();
  }

  final compileTypes = <_BenchmarkCompileType>[];
  final error = _addCompileTypes(
    compileTypes,
    results.multiOption('compile'),
  );
  if (error != null) return _BenchmarkCliConfig.error(error);

  return _BenchmarkCliConfig(
    compileTypes: compileTypes.isEmpty
        ? _BenchmarkCompileType.values
        : List.unmodifiable(compileTypes),
    outputFormat: results.option('output'),
    paths: List.unmodifiable(results.rest),
    testRunnerArguments: testRunnerArguments,
  );
}

String? _addCompileTypes(
  List<_BenchmarkCompileType> compileTypes,
  List<String> rawValues,
) {
  for (final value in rawValues) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'Compile type cannot be empty.';
    }

    if (normalized == 'all') {
      for (final compileType in _BenchmarkCompileType.values) {
        if (!compileTypes.contains(compileType)) compileTypes.add(compileType);
      }
      continue;
    }

    final compileType = _BenchmarkCompileType.tryParse(normalized);
    if (compileType == null) {
      return 'Unsupported compile type `$value`. Supported values: jit, aot.';
    }

    if (!compileTypes.contains(compileType)) compileTypes.add(compileType);
  }

  return null;
}

const _benchmarkOutputFormats = ['human', 'benchmarkjs', 'jsonl'];

enum _BenchmarkCompileType {
  jit('jit', 'kernel'),
  aot('aot', 'exe');

  const _BenchmarkCompileType(this.label, this.testCompiler);

  final String label;
  final String testCompiler;

  static _BenchmarkCompileType? tryParse(String value) {
    for (final compileType in values) {
      if (compileType.label == value) return compileType;
    }
    return null;
  }
}

class _BenchmarkCliConfig {
  final List<_BenchmarkCompileType> compileTypes;
  final String? outputFormat;
  final List<String> paths;
  final List<String> testRunnerArguments;
  final bool showHelp;
  final String? error;

  _BenchmarkCliConfig({
    required this.compileTypes,
    required this.outputFormat,
    required this.paths,
    required this.testRunnerArguments,
  })  : showHelp = false,
        error = null;

  _BenchmarkCliConfig.help()
      : compileTypes = const [],
        outputFormat = null,
        paths = const [],
        testRunnerArguments = const [],
        showHelp = true,
        error = null;

  _BenchmarkCliConfig.error(this.error)
      : compileTypes = const [],
        outputFormat = null,
        paths = const [],
        testRunnerArguments = const [],
        showHelp = false;
}

void _stdoutWriteln(String line) => stdout.writeln(line);

void _stderrWriteln(String line) => stderr.writeln(line);

String _usage(ArgParser parser) {
  return '''
Run benchmark tests for one or more Dart compile types.

Usage:
  dart run benchmark_test [options] [test-path ...] [-- <dart test args>]

Options:
${parser.usage}

Supported compile types: jit, aot. Default: jit,aot.
Default output format: human.

Examples:
  dart run benchmark_test test/benchmarks_test.dart
  dart run benchmark_test --compile jit -- -n parse
  dart run benchmark_test --output jsonl test/benchmarks_test.dart
  dart run benchmark_test -c jit,aot test/benchmarks_test.dart -- --reporter expanded
''';
}
