import 'dart:convert';
import 'dart:io';

import 'package:ansi/ansi.dart' as ansi;

import 'benchmark_result.dart';

const benchmarkChangeThreshold = 5;

class BenchmarkBaselineStore {
  final File file;

  Map<String, BenchmarkResult>? _baselines;

  BenchmarkBaselineStore(this.file);

  void updateBenchmarks(Iterable<BenchmarkResult> results) {
    final baselines = _readBaselines();
    for (final result in results) {
      baselines[result.name] = result;
    }
    _writeBaselines(baselines);
  }

  List<String> formatComparison(BenchmarkResult result) {
    var baselines = _readBaselines();
    var baseline = baselines[result.name];
    var lines = <String>[];

    if (baseline == null) {
      lines.add(
        ansi.yellow(
          '  Baseline: none (use --update-baseline to create one)',
        ),
      );
    } else {
      lines.add(
        '  Baseline: ${baseline.formattedOperationsPerSecond} ops/sec '
        '(${baseline.averageDuration} average duration)',
      );
      lines.add(formatBenchmarkChange(result, baseline));
    }

    return lines;
  }

  Map<String, BenchmarkResult> _readBaselines() {
    var baselines = _baselines;
    if (baselines != null) return baselines;

    if (!file.existsSync()) {
      return _baselines = <String, BenchmarkResult>{};
    }

    var decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      return _baselines = <String, BenchmarkResult>{};
    }

    var benchmarks = decoded['benchmarks'];
    if (benchmarks is! Map) {
      return _baselines = <String, BenchmarkResult>{};
    }

    baselines = <String, BenchmarkResult>{};
    for (var entry in benchmarks.entries) {
      var name = entry.key;
      if (name is! String) continue;

      var result = BenchmarkResult.fromJson(entry.value, name: name);
      if (result != null) baselines[name] = result;
    }
    return _baselines = baselines;
  }

  void _writeBaselines(Map<String, BenchmarkResult> baselines) {
    file.parent.createSync(recursive: true);
    var encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync(
      '${encoder.convert({
            'formatVersion': 1,
            'benchmarks': {
              for (var entry in baselines.entries)
                entry.key: entry.value.toJson(),
            },
          })}\n',
    );
  }
}

String formatBenchmarkChange(
  BenchmarkResult result,
  BenchmarkResult baseline,
) {
  var baselineOps = baseline.operationsPerSecond;
  if (baselineOps == 0) {
    return '  Change: unavailable (baseline is 0 ops/sec)';
  }

  var change = (result.operationsPerSecond - baselineOps) / baselineOps * 100;
  var formattedChange = change.toStringAsFixed(2);

  if (change >= benchmarkChangeThreshold) {
    return ansi.green('  ✅ Change: +$formattedChange% improvement');
  }

  if (change <= -benchmarkChangeThreshold) {
    return ansi.red('  ⚠️ Change: $formattedChange% regression');
  }

  var prefix = change >= 0 ? '+' : '';
  return '  Change: $prefix$formattedChange% '
      '(within ±$benchmarkChangeThreshold% threshold)';
}
