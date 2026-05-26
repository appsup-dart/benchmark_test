import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:test/test.dart';
import 'package:test_api/hooks.dart';

final bool isProfileMode = Platform.environment['PROFILE_MODE'] == 'true';
final _benchmarkOutputFormat = _BenchmarkOutputFormat.fromEnvironment(
  Platform.environment['BENCHMARK_OUTPUT'],
);

final _setUpsEach = <dynamic Function()>[];
final _tearDownsEach = <dynamic Function()>[];

/// Registers a function to be run before each iteration of a benchmark test.
///
/// If this is called within a test group, it applies only to benchmark tests
/// within that group.
void setUpEach(FutureOr<void> Function() callback) {
  setUp(() {
    _setUpsEach.add(callback);
  });
  tearDown(() => _setUpsEach.clear());
}

/// Registers a function to be run after each iteration of a benchmark test.
///
/// If this is called within a test group, it applies only to benchmark tests
/// within that group.
void tearDownEach(FutureOr<void> Function() callback) {
  setUp(() {
    _tearDownsEach.add(callback);
  });
  tearDown(() => _tearDownsEach.clear());
}

/// Creates a new benchmark test with the given [description] and [body].
///
/// The test will execute [body] repeatedly until [minDuration] has elapsed and
/// at least [minSamples] iterations have been run.
///
/// The test will output the number of operations per second, the relative
/// margin of error, and the number of runs sampled.
///
/// The environment variable `BENCHMARK_OUTPUT` controls the output format.
/// Supported values are `human`, `benchmarkjs`, and `ndjson`. If unset,
/// `human` is used.
///
/// If the environment variable `PROFILE_MODE` is set to `true`, the test will
/// pause at the beginning and end of the test to allow the user to start and
/// stop the CPU profiler.
///
/// The test will fail if [timeout] is reached. The default timeout is twice the
/// [minDuration].
@isTest
void benchmark(String description, dynamic Function() body,
        {Duration minDuration = const Duration(seconds: 2),
        int minSamples = 5,
        Timeout? timeout}) =>
    test(description, () async {
      if (isProfileMode) {
        print('Profiling: $description');
        print('  - open the CPU profiler');
        print('  - select the main #2 isolate');
        print('  - start recording');
        print('  - resume the debugger');
        debugger(message: 'START: $description');
      }
      var i = 0;
      var sum = 0;
      var sum2 = 0;

      var d = minDuration.inMicroseconds;

      var warmUp = true;

      while (sum < d || i < minSamples) {
        i++;

        for (var setup in _setUpsEach) {
          await setup();
        }
        var s = Timeline.now;
        await body();
        var v = Timeline.now - s;
        for (var teardown in _tearDownsEach) {
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
      var critical = _tTable[df.round().toString()] ?? _tTable['infinity']!;
      // Compute the margin of error.
      var moe = sem * critical;
      // Compute the relative margin of error.
      var rme = (moe / mean) * 100;

      var hz = 1 / (sum / i) * 1000 * 1000;
      var result = _BenchmarkResult(
        name: TestHandle.current.name,
        operationsPerSecond: hz,
        relativeMarginOfError: rme,
        runs: i,
        averageDuration: Duration(microseconds: sum ~/ i),
      );

      print(_benchmarkOutputFormat.format(result));
      if (isProfileMode) {
        print('  - stop recording');
        debugger(message: 'END: $description');
      }
    }, timeout: timeout ?? Timeout(minDuration * 2));

enum _BenchmarkOutputFormat {
  human,
  benchmarkjs,
  ndjson;

  static _BenchmarkOutputFormat fromEnvironment(String? value) {
    switch (value?.toLowerCase()) {
      case null:
      case '':
      case 'human':
        return human;
      case 'benchmarkjs':
      case 'benchmark-js':
      case 'benchmark_js':
        return benchmarkjs;
      case 'ndjson':
      case 'jsonl':
        return ndjson;
      default:
        throw ArgumentError.value(
          value,
          'BENCHMARK_OUTPUT',
          'Expected `human`, `benchmarkjs`, or `ndjson`.',
        );
    }
  }

  String format(_BenchmarkResult result) {
    switch (this) {
      case human:
        return [
          'Benchmark: ${result.name}',
          '  ${result.formattedOperationsPerSecond} ops/sec',
          '  ±${result.formattedRelativeMarginOfError}% margin of error',
          '  ${result.runs} runs sampled',
          '  ${result.averageDuration} average duration',
        ].join('\n');
      case benchmarkjs:
        return '${result.name} x ${result.formattedOperationsPerSecond} '
            'ops/sec ±${result.formattedRelativeMarginOfError}% '
            '(${result.runs} runs sampled)';
      case ndjson:
        return jsonEncode(result.toJson());
    }
  }
}

class _BenchmarkResult {
  final String name;
  final double operationsPerSecond;
  final double relativeMarginOfError;
  final int runs;
  final Duration averageDuration;

  _BenchmarkResult({
    required this.name,
    required this.operationsPerSecond,
    required this.relativeMarginOfError,
    required this.runs,
    required this.averageDuration,
  });

  String get formattedOperationsPerSecond {
    var precision = -(math.log(operationsPerSecond) / math.ln10).ceil() + 3;
    return operationsPerSecond.toStringAsFixed(math.max(precision, 0));
  }

  String get formattedRelativeMarginOfError =>
      relativeMarginOfError.toStringAsFixed(2);

  Map<String, Object> toJson() {
    return {
      'formatVersion': 1,
      'name': name,
      'throughput': {
        'value': operationsPerSecond,
        'unit': 'ops/sec',
      },
      'statistics': {
        'relativeMarginOfError': relativeMarginOfError,
        'samples': runs,
      },
      'latency': {
        'mean': averageDuration.inMicroseconds,
        'unit': 'microseconds',
      },
    };
  }
}

const _tTable = {
  '0': 12.706,
  '1': 12.706,
  '2': 4.303,
  '3': 3.182,
  '4': 2.776,
  '5': 2.571,
  '6': 2.447,
  '7': 2.365,
  '8': 2.306,
  '9': 2.262,
  '10': 2.228,
  '11': 2.201,
  '12': 2.179,
  '13': 2.16,
  '14': 2.145,
  '15': 2.131,
  '16': 2.12,
  '17': 2.11,
  '18': 2.101,
  '19': 2.093,
  '20': 2.086,
  '21': 2.08,
  '22': 2.074,
  '23': 2.069,
  '24': 2.064,
  '25': 2.06,
  '26': 2.056,
  '27': 2.052,
  '28': 2.048,
  '29': 2.045,
  '30': 2.042,
  'infinity': 1.96
};
