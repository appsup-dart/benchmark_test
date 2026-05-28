import 'package:args/args.dart';

import '../direct_runner/benchmark_test_name_filter.dart';
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
    ..addOption(
      'name',
      abbr: 'n',
      help: 'Run only benchmarks whose names match this pattern.',
      valueHelp: 'pattern',
    )
    ..addOption(
      'plain-name',
      abbr: 'N',
      help:
          'Run only benchmarks whose names contain this plain-text substring.',
      valueHelp: 'name',
    )
    ..addFlag(
      'enable-asserts',
      help: 'Run benchmark tests with Dart assertions enabled.',
      negatable: false,
    )
    ..addFlag(
      'run-skipped',
      help: 'Run skipped tests instead of skipping them.',
    )
    ..addFlag(
      'update-baseline',
      help: 'Write benchmark results to build/benchmark_test/baselines.json.',
      negatable: false,
    )
    ..addFlag(
      'profile',
      help:
          'Profile benchmarks with the CPU sampler (JIT only). Writes profiles '
          'to build/benchmark_test/profiles/.',
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
  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (error) {
    return BenchmarkCliConfig.error(error.message);
  }

  if (results.flag('help')) {
    return BenchmarkCliConfig.help();
  }

  final profile = results.flag('profile');

  final compileTypes = <BenchmarkCompileType>[];
  final error = addBenchmarkCompileTypes(
    compileTypes,
    results.multiOption('compile'),
  );
  if (error != null) return BenchmarkCliConfig.error(error);

  if (profile) {
    if (compileTypes.isEmpty) {
      compileTypes.add(BenchmarkCompileType.jit);
    }
    if (compileTypes.any((type) => type == BenchmarkCompileType.aot)) {
      return BenchmarkCliConfig.error(
        'CPU profiling is only supported with JIT (--compile jit).',
      );
    }
  }

  final plainName = results.option('plain-name');
  final name = results.option('name');
  if (plainName != null && name != null) {
    return BenchmarkCliConfig.error(
      'Cannot use both --name and --plain-name.',
    );
  }

  final BenchmarkNameFilter? nameFilter;
  if (plainName != null) {
    nameFilter = BenchmarkPlainNameFilter(plainName);
  } else if (name != null) {
    nameFilter = BenchmarkPatternNameFilter(name);
  } else {
    nameFilter = null;
  }

  return BenchmarkCliConfig(
    compileTypes: compileTypes.isEmpty
        ? BenchmarkCompileType.values
        : List.unmodifiable(compileTypes),
    enableAsserts: results.flag('enable-asserts'),
    runSkipped: results.flag('run-skipped'),
    profile: profile,
    updateBaseline: results.flag('update-baseline'),
    outputFormat: results.option('output'),
    paths: List.unmodifiable(results.rest),
    nameFilter: nameFilter,
  );
}

String benchmarkCliUsage(ArgParser parser) {
  return '''
Run benchmark tests for one or more Dart compile types.

Usage:
  dart run benchmark_test [options] [test-path ...]

Options:
${parser.usage}

Supported compile types: jit, aot. Default: jit,aot.
Default output format: human.

Examples:
  dart run benchmark_test test/benchmarks_test.dart
  dart run benchmark_test --compile jit --name parse test/benchmarks_test.dart
  dart run benchmark_test --output jsonl test/benchmarks_test.dart
  dart run benchmark_test --enable-asserts test/benchmarks_test.dart
  dart run benchmark_test --run-skipped test/benchmarks_test.dart
  dart run benchmark_test --update-baseline test/benchmarks_test.dart
  dart run benchmark_test --profile --compile jit test/benchmarks_test.dart
  dart run benchmark_test -c jit,aot test/benchmarks_test.dart
''';
}
