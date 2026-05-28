import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'started_process.dart';

const _runnerStatusPrefix = '__BENCHMARK_TEST_STATUS__:';
const _rawBenchmarkJsonlPrefix = '{"formatVersion":';

class ProcessRunResult {
  final int exitCode;
  final String stdout;

  const ProcessRunResult({
    required this.exitCode,
    this.stdout = '',
  });
}

class ProcessRunner {
  const ProcessRunner();

  /// Starts [executable] and returns before the process exits.
  ///
  /// When [vmServiceInfoFile] is set, VM service flags are passed before
  /// [arguments]. Stdout is captured; stderr is forwarded to this process stderr.
  Future<StartedProcess> startTracked(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? vmServiceInfoFile,
    bool pauseIsolatesOnStart = false,
  }) async {
    final vmArguments = <String>[
      if (vmServiceInfoFile != null) ...[
        '--enable-vm-service=0',
        '--write-service-info=$vmServiceInfoFile',
        if (pauseIsolatesOnStart) '--pause-isolates-on-start',
      ],
      ...arguments,
    ];

    final process = await Process.start(
      executable,
      vmArguments,
      environment: environment,
      mode: ProcessStartMode.normal,
    );

    unawaited(process.stderr.forEach(stderr.add));

    return StartedProcess(
      process: process,
      exitCode: process.exitCode,
    );
  }

  Future<ProcessRunResult> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    bool captureStdout = false,
    bool forwardStdout = false,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      environment: environment,
      mode: captureStdout
          ? ProcessStartMode.normal
          : ProcessStartMode.inheritStdio,
    );

    late final String capturedStdout;
    if (captureStdout) {
      final buffer = StringBuffer();
      final stderrDrain = process.stderr.forEach(stderr.add);
      var forwardPending = '';
      void flushForwardLines(String chunk, {required bool flushTail}) {
        if (!forwardStdout) return;
        forwardPending += chunk;
        final lines = forwardPending.split('\n');
        if (!flushTail) {
          forwardPending = lines.removeLast();
        } else {
          forwardPending = '';
        }
        for (final line in lines) {
          if (_isSuppressedForwardLine(line)) continue;
          stdout.writeln(line);
        }
      }

      await for (final chunk in process.stdout.transform(utf8.decoder)) {
        buffer.write(chunk);
        // Forward progress immediately; captureStdout alone buffers until exit,
        // which makes long CLI benchmark runs look hung.
        flushForwardLines(chunk, flushTail: false);
      }
      flushForwardLines('', flushTail: true);
      await stderrDrain;
      capturedStdout = buffer.toString();
    } else {
      capturedStdout = '';
    }
    final exitCode = await process.exitCode;
    return ProcessRunResult(exitCode: exitCode, stdout: capturedStdout);
  }
}

bool _isSuppressedForwardLine(String line) {
  return line.startsWith(_runnerStatusPrefix) ||
      line.startsWith(_rawBenchmarkJsonlPrefix);
}
