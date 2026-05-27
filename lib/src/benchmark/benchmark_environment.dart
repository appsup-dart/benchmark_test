import 'dart:io';

import 'benchmark_baseline_store.dart';
import 'benchmark_output_format.dart';

final bool isProfileMode = Platform.environment['PROFILE_MODE'] == 'true';

final benchmarkEnvironment = BenchmarkEnvironment._();

class BenchmarkEnvironment {
  BenchmarkEnvironment._()
      : outputFormat = BenchmarkOutputFormat.fromEnvironment(
          Platform.environment['BENCHMARK_OUTPUT'],
        ),
        baselineStore = BenchmarkBaselineStore(
          File('build/benchmark_test/baselines.json'),
        );

  final BenchmarkOutputFormat outputFormat;
  final BenchmarkBaselineStore baselineStore;
}
