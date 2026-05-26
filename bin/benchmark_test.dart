import 'dart:io';

import 'package:benchmark_test/src/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runBenchmarkCli(arguments);
}
