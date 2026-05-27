import 'dart:io';

import 'benchmark_test_discovery.dart';
import 'benchmark_test_invocation.dart';
import 'direct_runner_source_generator.dart';
import 'process_runner.dart';

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

  Future<int> run(
    BenchmarkTestInvocation invocation, {
    Map<String, String>? environment,
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
          _sourceGenerator.generate(testFiles, invocation.nameFilter),
        );

        if (invocation.compiler == 'exe') {
          final executable = File(
            '${runDir.path}/benchmark_direct_runner${Platform.isWindows ? '.exe' : ''}',
          );
          final compileExitCode = await _processRunner.start(
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
          if (compileExitCode != 0) return compileExitCode;

          return await _processRunner.start(
            executable.path,
            const [],
            environment: environment,
          );
        }

        return await _processRunner.start(
          Platform.resolvedExecutable,
          [
            if (invocation.enableAsserts) '--enable-asserts',
            bootstrap.path,
          ],
          environment: environment,
        );
      } finally {
        await runDir.delete(recursive: true);
      }
    } on FormatException catch (error) {
      stderr.writeln(error.message);
      return 64;
    } on FileSystemException catch (error) {
      stderr.writeln('${error.message}: ${error.path}');
      return 66;
    }
  }
}

Future<int> runBenchmarkTestInvocation(
  BenchmarkTestInvocation invocation, {
  Map<String, String>? environment,
  DirectRunner? runner,
}) {
  return (runner ?? const DirectRunner()).run(
    invocation,
    environment: environment,
  );
}

Future<int> runDartTest(
  List<String> arguments, {
  Map<String, String>? environment,
  DirectRunner? runner,
}) async {
  final invocation = BenchmarkTestInvocation.parse(arguments);
  if (invocation.error != null) {
    stderr.writeln(invocation.error);
    return 64;
  }

  return runBenchmarkTestInvocation(
    invocation,
    environment: environment,
    runner: runner,
  );
}
