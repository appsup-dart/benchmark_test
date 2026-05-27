import 'dart:io';

import '../direct_runner/benchmark_test_invocation.dart';
import '../direct_runner/direct_runner.dart' as direct_runner;
import '../direct_runner/process_runner.dart';
import 'benchmark_baseline_updater.dart';
import 'benchmark_cli_parser.dart';

typedef DartTestRunner = Future<ProcessRunResult> Function(
  BenchmarkTestInvocation invocation, {
  Map<String, String>? environment,
  bool captureStdout,
});

Future<int> runBenchmarkCli(
  List<String> arguments, {
  DartTestRunner? runDartTest,
  BenchmarkBaselineUpdater? baselineUpdater,
  void Function(String line) printStatus = _stderrWriteln,
  void Function(String line) printUsage = _stdoutWriteln,
  void Function(String line) printError = _stderrWriteln,
  void Function(String line) printOutput = _stdoutWriteln,
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

  final runner = runDartTest ?? direct_runner.runBenchmarkTestInvocation;
  final updater =
      baselineUpdater ?? BenchmarkBaselineUpdater(printLine: printOutput);
  final displayFormat = resolveBenchmarkOutputFormat(config.outputFormat);

  for (final compileType in config.compileTypes) {
    printStatus('Running benchmarks with ${compileType.label}...');

    final captureStdout = config.updateBaseline;
    final runResult = await runner(
      BenchmarkTestInvocation(
        compiler: compileType.testCompiler,
        enableAsserts: config.enableAsserts,
        runSkipped: config.runSkipped,
        paths: config.paths,
        nameFilter: config.nameFilter,
      ),
      environment: {
        'BENCHMARK_COMPILE_TYPE': compileType.label,
        if (captureStdout)
          'BENCHMARK_OUTPUT': 'jsonl'
        else if (config.outputFormat != null)
          'BENCHMARK_OUTPUT': config.outputFormat!,
      },
      captureStdout: captureStdout,
    );

    if (runResult.exitCode != 0) return runResult.exitCode;

    if (config.updateBaseline) {
      updater.updateFromRunnerOutput(
        runResult.stdout,
        displayFormat: displayFormat,
      );
    }
  }

  return 0;
}

void _stdoutWriteln(String line) => stdout.writeln(line);

void _stderrWriteln(String line) => stderr.writeln(line);
