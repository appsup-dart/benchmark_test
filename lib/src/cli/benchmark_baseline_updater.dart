import 'dart:io';

import 'package:ansi/ansi.dart' as ansi;

import '../benchmark/benchmark_baseline_store.dart';
import '../benchmark/benchmark_output_format.dart';
import 'benchmark_result_parser.dart';

const benchmarkBaselineFilePath = 'build/benchmark_test/baselines.json';

class BenchmarkBaselineUpdater {
  BenchmarkBaselineUpdater({
    BenchmarkBaselineStore? baselineStore,
    void Function(String line)? printLine,
  })  : _baselineStore = baselineStore ??
            BenchmarkBaselineStore(File(benchmarkBaselineFilePath)),
        _printLine = printLine ?? ((line) => stdout.writeln(line));

  final BenchmarkBaselineStore _baselineStore;
  final void Function(String line) _printLine;

  void updateFromRunnerOutput(
    String runnerOutput, {
    required BenchmarkOutputFormat displayFormat,
  }) {
    final results = parseBenchmarkJsonlOutput(runnerOutput);
    if (results.isEmpty) return;

    _baselineStore.updateBenchmarks(results);

    if (displayFormat == BenchmarkOutputFormat.ndjson) {
      _printLine(runnerOutput.trimRight());
      return;
    }

    for (final result in results) {
      _printLine(
        displayFormat.format(
          result,
          baselineStore: _baselineStore,
        ),
      );
    }

    _printLine(
      ansi.yellow(
        'Baseline updated: ${_baselineStore.file.path}',
      ),
    );
  }
}

BenchmarkOutputFormat resolveBenchmarkOutputFormat(String? value) {
  if (value == null) return BenchmarkOutputFormat.human;
  return BenchmarkOutputFormat.fromEnvironment(value);
}
