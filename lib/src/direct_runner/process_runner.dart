import 'dart:convert';
import 'dart:io';

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

  Future<ProcessRunResult> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    bool captureStdout = false,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      environment: environment,
      mode: captureStdout
          ? ProcessStartMode.normal
          : ProcessStartMode.inheritStdio,
    );

    late final String stdout;
    if (captureStdout) {
      final results = await Future.wait([
        process.stdout.transform(utf8.decoder).join(),
        process.stderr.forEach(stderr.add),
      ]);
      stdout = results[0] as String;
    } else {
      stdout = '';
    }
    final exitCode = await process.exitCode;
    return ProcessRunResult(exitCode: exitCode, stdout: stdout);
  }
}
