import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'benchmark_result.dart';
import 'student_t_table.dart';

class BenchmarkSampler {
  const BenchmarkSampler();

  Future<BenchmarkResult> sample({
    required FutureOr<void> Function() body,
    required Duration minDuration,
    required int minSamples,
    required List<FutureOr<void> Function()> setUps,
    required List<FutureOr<void> Function()> tearDowns,
    required String name,
  }) async {
    var i = 0;
    var sum = 0;
    var sum2 = 0;

    var d = minDuration.inMicroseconds;

    var warmUp = true;

    while (sum < d || i < minSamples) {
      i++;

      for (var setup in setUps) {
        await setup();
      }
      var s = Timeline.now;
      await body();
      var v = Timeline.now - s;
      for (var teardown in tearDowns) {
        await teardown();
      }

      if (warmUp) {
        warmUp = false;
        continue;
      }
      sum += v;
      sum2 += v * v;
    }

    // Compute the sample mean (estimate of the population mean).
    var mean = sum / i;
    // Compute the sample variance (estimate of the population variance).
    var variance = (sum2 - mean * mean * i) / (i - 1);
    // Compute the sample standard deviation (estimate of the population standard deviation).
    var sd = math.sqrt(variance);
    // Compute the standard error of the mean (a.k.a. the standard deviation of the sampling distribution of the sample mean).
    var sem = sd / math.sqrt(i);
    // Compute the degrees of freedom.
    var df = i - 1;
    // Compute the critical value.
    var critical =
        studentTTable[df.round().toString()] ?? studentTTable['infinity']!;
    // Compute the margin of error.
    var moe = sem * critical;
    // Compute the relative margin of error.
    var rme = (moe / mean) * 100;

    var hz = 1 / (sum / i) * 1000 * 1000;
    return BenchmarkResult(
      name: name,
      operationsPerSecond: hz,
      relativeMarginOfError: rme,
      runs: i,
      averageDuration: Duration(microseconds: sum ~/ i),
    );
  }
}
