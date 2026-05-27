import 'dart:io';

import 'benchmark_test_discovery.dart';
import 'benchmark_test_invocation.dart';
import 'direct_runner_source_generator.dart';
import 'process_runner.dart' show ProcessRunResult, ProcessRunner;

class DirectRunner {
  const DirectRunner({
    BenchmarkTestDiscovery? discovery,
    DirectRunnerSourceGenerator? sourceGenerator,
    ProcessRunner? processRunner,
  })  : _discovery = discovery ?? const BenchmarkTestDiscovery(),
        _sourceGenerator =
            sourceGenerator ?? const DirectRunnerSourceGenerator(),
        _processRunner = processRunner ?? const ProcessRunner();

  final BenchmarkTestDiscovery _discovery;
  final DirectRunnerSourceGenerator _sourceGenerator;
  final ProcessRunner _processRunner;

  Future<ProcessRunResult> run(
    BenchmarkTestInvocation invocation, {
    Map<String, String>? environment,
    bool captureStdout = false,
  }) async {
    try {
      final testFiles = _discovery.collect(invocation.paths);
      final workDir = await Directory(
        '.dart_tool/benchmark_test',
      ).create(recursive: true);
      final runDir = await workDir.createTemp('run_');

      try {
        final bootstrap = File('${runDir.path}/benchmark_direct_runner.dart');
        await bootstrap.writeAsString(
          _sourceGenerator.generate(
            testFiles,
            invocation.nameFilter,
            runSkipped: invocation.runSkipped,
          ),
        );

        if (invocation.compiler == 'exe') {
          final executable = File(
            '${runDir.path}/benchmark_direct_runner${Platform.isWindows ? '.exe' : ''}',
          );
          final compileResult = await _processRunner.start(
            Platform.resolvedExecutable,
            [
              'compile',
              'exe',
              if (invocation.enableAsserts) '--enable-asserts',
              bootstrap.path,
              '--output',
              executable.path,
            ],
            environment: environment,
          );
          if (compileResult.exitCode != 0) return compileResult;

          return await _processRunner.start(
            executable.path,
            const [],
            environment: environment,
            captureStdout: captureStdout,
          );
        }

        return await _processRunner.start(
          Platform.resolvedExecutable,
          [
            if (invocation.enableAsserts) '--enable-asserts',
            bootstrap.path,
          ],
          environment: environment,
          captureStdout: captureStdout,
        );
      } finally {
        await runDir.delete(recursive: true);
      }
    } on FormatException catch (error) {
      stderr.writeln(error.message);
      return const ProcessRunResult(exitCode: 64);
    } on FileSystemException catch (error) {
      stderr.writeln('${error.message}: ${error.path}');
      return const ProcessRunResult(exitCode: 66);
    }
  }
}

Future<ProcessRunResult> runBenchmarkTestInvocation(
  BenchmarkTestInvocation invocation, {
  Map<String, String>? environment,
  bool captureStdout = false,
  DirectRunner? runner,
}) {
  return (runner ?? const DirectRunner()).run(
    invocation,
    environment: environment,
    captureStdout: captureStdout,
  );
}
