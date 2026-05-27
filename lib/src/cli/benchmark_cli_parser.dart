import 'package:args/args.dart';

import 'benchmark_cli_config.dart';
import 'benchmark_compile_type.dart';

const benchmarkOutputFormats = ['human', 'benchmarkjs', 'jsonl'];

ArgParser createBenchmarkArgParser() {
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
      allowed: benchmarkOutputFormats,
      allowedHelp: const {
        'human': 'Human-readable local development output.',
        'benchmarkjs': 'benchmark.js-compatible output.',
        'jsonl': 'One JSON object per benchmark result.',
      },
      help: 'Benchmark output format.',
      valueHelp: 'format',
    )
    ..addFlag(
      'enable-asserts',
      help: 'Run benchmark tests with Dart assertions enabled.',
      negatable: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this help.',
      negatable: false,
    );
}

BenchmarkCliConfig parseBenchmarkCliArguments(
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
    return BenchmarkCliConfig.error(
      '${error.message}. Pass dart test options after `--`.',
    );
  }

  if (results.flag('help')) {
    return BenchmarkCliConfig.help();
  }

  final compileTypes = <BenchmarkCompileType>[];
  final error = addBenchmarkCompileTypes(
    compileTypes,
    results.multiOption('compile'),
  );
  if (error != null) return BenchmarkCliConfig.error(error);

  return BenchmarkCliConfig(
    compileTypes: compileTypes.isEmpty
        ? BenchmarkCompileType.values
        : List.unmodifiable(compileTypes),
    enableAsserts: results.flag('enable-asserts'),
    outputFormat: results.option('output'),
    paths: List.unmodifiable(results.rest),
    testRunnerArguments: testRunnerArguments,
  );
}

String benchmarkCliUsage(ArgParser parser) {
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
  dart run benchmark_test --enable-asserts test/benchmarks_test.dart
  dart run benchmark_test -c jit,aot test/benchmarks_test.dart -- --reporter expanded
''';
}
