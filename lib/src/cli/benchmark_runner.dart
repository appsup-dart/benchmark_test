import 'dart:io';

import '../benchmark/benchmark_output_format.dart';
import '../direct_runner/benchmark_test_invocation.dart';
import '../direct_runner/direct_runner.dart' as direct_runner;
import '../direct_runner/process_runner.dart';
import 'benchmark_cli_output.dart';
import 'benchmark_cli_parser.dart';

typedef DartTestRunner = Future<ProcessRunResult> Function(
  BenchmarkTestInvocation invocation, {
  bool captureStdout,
  bool forwardStdout,
});

Future<int> runBenchmarkCli(
  List<String> arguments, {
  DartTestRunner? runDartTest,
  BenchmarkCliOutput? cliOutput,
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
  final output = cliOutput ?? BenchmarkCliOutput(printLine: printOutput);
  final displayFormat = BenchmarkOutputFormat.parse(config.outputFormat);

  for (final compileType in config.compileTypes) {
    if (config.profile) {
      printStatus('Profiling benchmarks with ${compileType.label}...');
    } else {
      printStatus('Running benchmarks with ${compileType.label}...');
    }

    final forwardChildOutput =
        config.profile || displayFormat == BenchmarkOutputFormat.human;
    final runResult = await runner(
      BenchmarkTestInvocation(
        compiler: compileType.testCompiler,
        enableAsserts: config.enableAsserts,
        runSkipped: config.runSkipped,
        profile: config.profile,
        paths: config.paths,
        nameFilter: config.nameFilter,
      ),
      captureStdout: true,
      forwardStdout: forwardChildOutput,
    );

    if (runResult.exitCode != 0) return runResult.exitCode;

    output.writeFromRunnerOutput(
      runResult.stdout,
      displayFormat: displayFormat,
      updateBaseline: config.updateBaseline,
    );
  }

  return 0;
}

void _stdoutWriteln(String line) => stdout.writeln(line);

void _stderrWriteln(String line) => stderr.writeln(line);
