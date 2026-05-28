import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../cli/benchmark_vm_profile_session.dart';
import 'benchmark_test_discovery.dart';
import 'benchmark_test_invocation.dart';
import 'benchmark_test_name_filter.dart';
import 'direct_runner_source_generator.dart';
import 'process_runner.dart' show ProcessRunResult, ProcessRunner;

const _runnerStatusPrefix = '__BENCHMARK_TEST_STATUS__:';
const _rawBenchmarkJsonlPrefix = '{"formatVersion":';

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
    bool captureStdout = false,
    bool forwardStdout = false,
  }) async {
    try {
      final testFiles = _discovery.collect(invocation.paths);
      final workDir = await Directory(
        '.dart_tool/benchmark_test',
      ).create(recursive: true);
      final runDir = await workDir.createTemp('run_');

      try {
        final bootstrap = File('${runDir.path}/benchmark_direct_runner.dart');
        if (invocation.compiler == 'js') {
          await bootstrap.writeAsString(
            _sourceGenerator.generateNodeBootstrap(
              testFiles,
              profileMode: invocation.profile,
            ),
          );
        } else {
          await bootstrap.writeAsString(
            _sourceGenerator.generate(
              testFiles,
              invocation.nameFilter,
              runSkipped: invocation.runSkipped,
              profileMode: invocation.profile,
            ),
          );
        }

        if (invocation.profile) {
          if (invocation.compiler == 'exe') {
            stderr.writeln('CPU profiling is only supported with JIT.');
            return const ProcessRunResult(exitCode: 64);
          }

          return await _runProfiled(
            bootstrap: bootstrap,
            invocation: invocation,
            printStatus: stderr.writeln,
          );
        }

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
          );
          if (compileResult.exitCode != 0) return compileResult;

          return await _processRunner.start(
            executable.path,
            const [],
            environment: _environmentFor(),
            captureStdout: captureStdout,
            forwardStdout: forwardStdout,
          );
        }

        if (invocation.compiler == 'js') {
          final args = <String>[
            'test',
            '-p',
            'node',
            if (invocation.runSkipped) '--run-skipped',
            ..._nameFilterTestArgs(invocation.nameFilter),
            bootstrap.path,
          ];

          return await _processRunner.start(
            Platform.resolvedExecutable,
            args,
            environment: _environmentFor(),
            captureStdout: captureStdout,
            forwardStdout: forwardStdout,
          );
        }

        return await _processRunner.start(
          Platform.resolvedExecutable,
          [
            if (invocation.enableAsserts) '--enable-asserts',
            bootstrap.path,
          ],
          environment: _environmentFor(),
          captureStdout: captureStdout,
          forwardStdout: forwardStdout,
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

  Future<ProcessRunResult> _runProfiled({
    required File bootstrap,
    required BenchmarkTestInvocation invocation,
    required void Function(String line) printStatus,
  }) async {
    final workDir = bootstrap.parent;
    final serviceInfoFile = File('${workDir.path}/vm_service.json');
    final profileOutputDir = Directory('build/benchmark_test/profiles');
    final session = BenchmarkVmProfileSession(
      serviceInfoFile: serviceInfoFile,
      outputDirectory: profileOutputDir,
      printStatus: printStatus,
    );

    final started = await _processRunner.startTracked(
      Platform.resolvedExecutable,
      [
        if (invocation.enableAsserts) '--enable-asserts',
        bootstrap.path,
      ],
      environment: _environmentFor(),
      vmServiceInfoFile: serviceInfoFile.path,
      pauseIsolatesOnStart: true,
    );

    final stdoutBuffer = StringBuffer();
    final stdoutDone = Completer<void>();
    started.process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        session.trackStdoutLine(line);
        stdoutBuffer.writeln(line);
        if (!line.startsWith(_runnerStatusPrefix) &&
            !line.startsWith(_rawBenchmarkJsonlPrefix)) {
          stdout.writeln(line);
        }
      },
      onDone: () {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
      onError: stdoutDone.completeError,
    );

    try {
      await session.connect();
      await session.synchronizePausedIsolates();
      final exitCode = await started.exitCode;
      await stdoutDone.future;
      return ProcessRunResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
      );
    } finally {
      await session.dispose();
      if (serviceInfoFile.existsSync()) {
        serviceInfoFile.deleteSync();
      }
    }
  }

  Map<String, String> _environmentFor() =>
      Map<String, String>.from(Platform.environment)..remove('PROFILE_MODE');

  List<String> _nameFilterTestArgs(BenchmarkNameFilter? filter) {
    if (filter is BenchmarkPatternNameFilter) {
      return ['-n', filter.pattern];
    }
    if (filter is BenchmarkPlainNameFilter) {
      return ['-n', '^${RegExp.escape(filter.name)}\$'];
    }
    return const [];
  }
}

Future<ProcessRunResult> runBenchmarkTestInvocation(
  BenchmarkTestInvocation invocation, {
  bool captureStdout = false,
  bool forwardStdout = false,
  DirectRunner? runner,
}) {
  return (runner ?? const DirectRunner()).run(
    invocation,
    captureStdout: captureStdout,
    forwardStdout: forwardStdout,
  );
}
