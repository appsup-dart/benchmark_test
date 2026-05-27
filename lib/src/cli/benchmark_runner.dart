import 'dart:io';

import '../direct_runner/benchmark_test_invocation.dart';
import '../direct_runner/direct_runner.dart' as direct_runner;
import 'benchmark_cli_parser.dart';

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
  final parser = createBenchmarkArgParser();
  final config = parseBenchmarkCliArguments(parser, arguments);
  if (config.showHelp) {
    printUsage(benchmarkCliUsage(parser));
    return 0;
  }

  if (config.error != null) {
    printError(config.error!);
    printError('');
    printError(benchmarkCliUsage(parser));
    return 64;
  }

  final runner = runDartTest ?? direct_runner.runDartTest;
  for (final compileType in config.compileTypes) {
    printStatus('Running benchmarks with ${compileType.label}...');

    final exitCode = await runner(
      [
        if (config.enableAsserts) enableAssertsRunnerArgument,
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

void _stdoutWriteln(String line) => stdout.writeln(line);

void _stderrWriteln(String line) => stderr.writeln(line);
