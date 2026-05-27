import 'dart:io';

import 'package:ansi/ansi.dart' as ansi;

import '../benchmark/benchmark_baseline_store.dart';
import '../benchmark/benchmark_output_format.dart';
import 'benchmark_result_parser.dart';

class BenchmarkCliOutput {
  BenchmarkCliOutput({
    BenchmarkBaselineStore? baselineStore,
    void Function(String line)? printLine,
  })  : _baselineStore = baselineStore ?? benchmarkBaselineStore,
        _printLine = printLine ?? ((line) => stdout.writeln(line));

  final BenchmarkBaselineStore _baselineStore;
  final void Function(String line) _printLine;

  void writeFromRunnerOutput(
    String runnerOutput, {
    required BenchmarkOutputFormat displayFormat,
    required bool updateBaseline,
  }) {
    final results = parseBenchmarkJsonlOutput(runnerOutput);
    if (results.isEmpty) return;

    if (updateBaseline) {
      _baselineStore.updateBenchmarks(results);
    }

    if (displayFormat == BenchmarkOutputFormat.ndjson) {
      _printLine(runnerOutput.trimRight());
      if (updateBaseline) {
        _printBaselineUpdated();
      }
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

    if (updateBaseline) {
      _printBaselineUpdated();
    }
  }

  void _printBaselineUpdated() {
    _printLine(
      ansi.yellow(
        'Baseline updated: ${_baselineStore.file.path}',
      ),
    );
  }
}
