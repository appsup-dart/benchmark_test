import 'dart:developer';

import 'package:meta/meta.dart';
import 'package:test/test.dart';
import 'package:test_api/hooks.dart';

import 'benchmark_baseline_store.dart';
import 'benchmark_configuration.dart';
import 'benchmark_iteration_hooks.dart';
import 'benchmark_output_format.dart';
import 'benchmark_sampler.dart';

export 'benchmark_iteration_hooks.dart' show setUpEach, tearDownEach;
export 'benchmark_profile_mode.dart' show isProfileMode;

/// Creates a new benchmark test with the given [description] and [body].
///
/// The test will execute [body] repeatedly until [minDuration] has elapsed and
/// at least [minSamples] measured iterations have been run.
///
/// A warmup phase runs before measured iterations. Warmup defaults to a single
/// run and can be expanded with [warmupMinSamples] and [warmupMinDuration].
///
/// When [targetRme] is set, the benchmark keeps sampling after minimum
/// thresholds are reached until the relative margin of error is at most
/// [targetRme], or [maxSamples] is hit.
///
/// The test will output the number of operations per second, the relative
/// margin of error, and the number of runs sampled.
///
/// Benchmarks print human-readable output by default. When run through the
/// `benchmark_test` CLI, results are emitted as JSONL for the CLI to format.
///
/// The human output format compares results against the baseline stored in
/// `build/benchmark_test/baselines.json`. Use `--update-baseline` on the
/// benchmark CLI to create or overwrite the baseline.
///
/// If profile mode is enabled, the test pauses at benchmark start and end so
/// profiling sessions can capture per-benchmark samples.
///
/// The test will fail if [timeout] is reached. The default timeout is twice the
/// [minDuration].
@isTest
void benchmark(
  String description,
  dynamic Function() body, {
  Duration minDuration = const Duration(seconds: 2),
  int minSamples = 5,
  int warmupMinSamples = 1,
  Duration warmupMinDuration = Duration.zero,
  double? targetRme,
  int? maxSamples,
  Timeout? timeout,
}) =>
    test(description, () async {
      if (benchmarkConfiguration.profileMode) {
        print('Profiling: $description');
        debugger(message: 'START: $description');
      }

      final result = await const BenchmarkSampler().sample(
        body: body,
        minDuration: minDuration,
        minSamples: minSamples,
        warmupMinSamples: warmupMinSamples,
        warmupMinDuration: warmupMinDuration,
        targetRme: targetRme,
        maxSamples: maxSamples,
        setUps: benchmarkSetUpsEach,
        tearDowns: benchmarkTearDownsEach,
        name: TestHandle.current.name,
        compiler: benchmarkConfiguration.compilerType,
      );

      final outputFormat = benchmarkConfiguration.emitJsonlResults
          ? BenchmarkOutputFormat.ndjson
          : BenchmarkOutputFormat.human;
      print(
        outputFormat.format(
          result,
          baselineStore: benchmarkBaselineStore,
        ),
      );

      if (benchmarkConfiguration.profileMode) {
        debugger(message: 'END: $description');
      }
    }, timeout: timeout ?? Timeout(_defaultTimeout(minDuration)));

Duration _defaultTimeout(Duration minDuration) {
  final multiplier = benchmarkConfiguration.timeoutMultiplier;
  final micros = minDuration.inMicroseconds * 2 * multiplier;
  return Duration(microseconds: micros);
}
