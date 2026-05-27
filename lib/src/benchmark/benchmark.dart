import 'dart:developer';

import 'package:meta/meta.dart';
import 'package:test/test.dart';
import 'package:test_api/hooks.dart';

import 'benchmark_baseline_store.dart';
import 'benchmark_configuration.dart';
import 'benchmark_iteration_hooks.dart';
import 'benchmark_output_format.dart';
import 'benchmark_profile_mode.dart';
import 'benchmark_sampler.dart';

export 'benchmark_configuration.dart' show configureBenchmarkRunner;
export 'benchmark_iteration_hooks.dart' show setUpEach, tearDownEach;
export 'benchmark_profile_mode.dart' show isProfileMode;

/// Creates a new benchmark test with the given [description] and [body].
///
/// The test will execute [body] repeatedly until [minDuration] has elapsed and
/// at least [minSamples] iterations have been run.
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
/// If the environment variable `PROFILE_MODE` is set to `true`, the test will
/// pause at the beginning and end of the test to allow the user to start and
/// stop the CPU profiler.
///
/// The test will fail if [timeout] is reached. The default timeout is twice the
/// [minDuration].
@isTest
void benchmark(
  String description,
  dynamic Function() body, {
  Duration minDuration = const Duration(seconds: 2),
  int minSamples = 5,
  Timeout? timeout,
}) =>
    test(description, () async {
      if (isProfileMode) {
        print('Profiling: $description');
        print('  - open the CPU profiler');
        print('  - select the main #2 isolate');
        print('  - start recording');
        print('  - resume the debugger');
        debugger(message: 'START: $description');
      }

      final result = await const BenchmarkSampler().sample(
        body: body,
        minDuration: minDuration,
        minSamples: minSamples,
        setUps: benchmarkSetUpsEach,
        tearDowns: benchmarkTearDownsEach,
        name: TestHandle.current.name,
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

      if (isProfileMode) {
        print('  - stop recording');
        debugger(message: 'END: $description');
      }
    }, timeout: timeout ?? Timeout(minDuration * 2));
