import 'dart:io';

/// A child process started without waiting for exit.
class StartedProcess {
  final Process process;
  final Future<int> exitCode;

  const StartedProcess({
    required this.process,
    required this.exitCode,
  });
}
