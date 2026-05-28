import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'benchmark_result.dart';
import 'iteration_timer.dart';
import 'student_t_table.dart';

class BenchmarkSampler {
  const BenchmarkSampler();

  static final UserTag _benchmarkBodyTag = UserTag('benchmark-body');

  Future<BenchmarkResult> sample({
    required FutureOr<void> Function() body,
    required Duration minDuration,
    required int minSamples,
    required int warmupMinSamples,
    required Duration warmupMinDuration,
    required double? targetRme,
    required int? maxSamples,
    required List<FutureOr<void> Function()> setUps,
    required List<FutureOr<void> Function()> tearDowns,
    required String name,
    required String compiler,
  }) async {
    if (minSamples < 1) {
      throw ArgumentError.value(minSamples, 'minSamples', 'Must be >= 1.');
    }
    if (warmupMinSamples < 0) {
      throw ArgumentError.value(
        warmupMinSamples,
        'warmupMinSamples',
        'Must be >= 0.',
      );
    }
    if (targetRme != null && targetRme <= 0) {
      throw ArgumentError.value(targetRme, 'targetRme', 'Must be > 0.');
    }
    if (maxSamples != null && maxSamples < minSamples) {
      throw ArgumentError.value(
        maxSamples,
        'maxSamples',
        'Must be >= minSamples.',
      );
    }

    var i = 0;
    var sum = 0;
    var sum2 = 0;

    final d = minDuration.inMicroseconds;
    final warmupDurationMicros = warmupMinDuration.inMicroseconds;
    final warmupStopwatch = Stopwatch()..start();
    var warmupIterations = 0;

    while (warmupIterations < warmupMinSamples ||
        warmupStopwatch.elapsedMicroseconds < warmupDurationMicros) {
      warmupIterations++;
      for (var setup in setUps) {
        await setup();
      }
      await body();
      for (var teardown in tearDowns) {
        await teardown();
      }
    }

    final iterationTimer = createIterationTimer();
    while (true) {
      i++;

      for (var setup in setUps) {
        await setup();
      }
      iterationTimer.start();
      final previousTag = getCurrentTag();
      _benchmarkBodyTag.makeCurrent();
      try {
        await body();
      } finally {
        previousTag.makeCurrent();
      }
      final v = iterationTimer.elapsedMicroseconds();
      for (var teardown in tearDowns) {
        await teardown();
      }

      sum += v;
      sum2 += v * v;

      final reachedSampleCeiling = maxSamples != null && i >= maxSamples;
      if (reachedSampleCeiling) break;
      if (!_reachedRequiredMinimums(
          sum: sum, runs: i, minDurationMicros: d, minSamples: minSamples)) {
        continue;
      }
      if (targetRme == null) break;
      if (i < 2) continue;

      final statistics = _calculateStatistics(sum: sum, sum2: sum2, runs: i);
      if (statistics.relativeMarginOfError <= targetRme) break;
    }

    final statistics = _calculateStatistics(sum: sum, sum2: sum2, runs: i);

    final mean = statistics.mean;
    final hz = mean == 0 ? double.infinity : 1000000 / mean;
    return BenchmarkResult(
      name: name,
      compiler: compiler,
      operationsPerSecond: hz,
      relativeMarginOfError: statistics.relativeMarginOfError,
      runs: i,
      averageDuration: Duration(
        microseconds: mean.isFinite ? mean.round() : 0,
      ),
    );
  }

  bool _reachedRequiredMinimums({
    required int sum,
    required int runs,
    required int minDurationMicros,
    required int minSamples,
  }) {
    return sum >= minDurationMicros && runs >= minSamples;
  }

  _SampleStatistics _calculateStatistics({
    required int sum,
    required int sum2,
    required int runs,
  }) {
    final mean = sum / runs;
    if (runs < 2) {
      return _SampleStatistics(mean: mean, relativeMarginOfError: 0);
    }

    final numerator = sum2 - mean * mean * runs;
    final variance = math.max(numerator / (runs - 1), 0).toDouble();
    final sd = math.sqrt(variance);
    final sem = sd / math.sqrt(runs);
    final df = runs - 1;
    final critical = studentTTable[df.toString()] ?? studentTTable['infinity']!;
    final moe = sem * critical;
    final rme = mean == 0 ? 0.0 : (moe / mean) * 100;

    return _SampleStatistics(mean: mean, relativeMarginOfError: rme);
  }
}

class _SampleStatistics {
  const _SampleStatistics({
    required this.mean,
    required this.relativeMarginOfError,
  });

  final double mean;
  final double relativeMarginOfError;
}
