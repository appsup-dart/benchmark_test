import 'benchmark_test_name_filter.dart';

const enableAssertsRunnerArgument = '--benchmark-test-enable-asserts';

class BenchmarkTestInvocation {
  final String compiler;
  final bool enableAsserts;
  final List<String> paths;
  final BenchmarkNameFilter? nameFilter;
  final String? error;

  BenchmarkTestInvocation({
    required this.compiler,
    required this.enableAsserts,
    required this.paths,
    required this.nameFilter,
  }) : error = null;

  BenchmarkTestInvocation.error(this.error)
      : compiler = 'kernel',
        enableAsserts = false,
        paths = const [],
        nameFilter = null;

  static BenchmarkTestInvocation parse(List<String> arguments) {
    var enableAsserts = false;
    String? platform;
    String? compiler;
    final paths = <String>[];
    BenchmarkNameFilter? nameFilter;

    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];

      String? readValue() {
        if (i + 1 == arguments.length) return null;
        return arguments[++i];
      }

      if (argument == enableAssertsRunnerArgument) {
        enableAsserts = true;
      } else if (argument == '--platform') {
        platform = readValue();
        if (platform == null) {
          return BenchmarkTestInvocation.error(
            'Expected a value after --platform.',
          );
        }
      } else if (argument.startsWith('--platform=')) {
        platform = argument.substring('--platform='.length);
      } else if (argument == '--compiler') {
        compiler = readValue();
        if (compiler == null) {
          return BenchmarkTestInvocation.error(
            'Expected a value after --compiler.',
          );
        }
      } else if (argument.startsWith('--compiler=')) {
        compiler = argument.substring('--compiler='.length);
      } else if (argument == '-n' || argument == '--name') {
        final value = readValue();
        if (value == null) {
          return BenchmarkTestInvocation.error(
            'Expected a value after $argument.',
          );
        }
        nameFilter = BenchmarkPatternNameFilter(value);
      } else if (argument.startsWith('--name=')) {
        nameFilter = BenchmarkPatternNameFilter(
          argument.substring('--name='.length),
        );
      } else if (argument == '-N' || argument == '--plain-name') {
        final value = readValue();
        if (value == null) {
          return BenchmarkTestInvocation.error(
            'Expected a value after $argument.',
          );
        }
        nameFilter = BenchmarkPlainNameFilter(value);
      } else if (argument.startsWith('--plain-name=')) {
        nameFilter = BenchmarkPlainNameFilter(
          argument.substring('--plain-name='.length),
        );
      } else if (argument == '-r' || argument == '--reporter') {
        final value = readValue();
        if (value == null) {
          return BenchmarkTestInvocation.error(
            'Expected a value after $argument.',
          );
        }
        final error = validateBenchmarkReporter(value);
        if (error != null) return BenchmarkTestInvocation.error(error);
      } else if (argument.startsWith('--reporter=')) {
        final error = validateBenchmarkReporter(
          argument.substring('--reporter='.length),
        );
        if (error != null) return BenchmarkTestInvocation.error(error);
      } else if (argument == '--color' || argument == '--no-color') {
        // The direct runner currently uses the expanded reporter. These flags
        // are accepted for compatibility with common `dart test` invocations.
      } else if (argument == '--run-skipped') {
      } else if (argument.startsWith('-')) {
        return BenchmarkTestInvocation.error(
          'Unsupported dart test argument `$argument` for assert-free benchmarks.',
        );
      } else {
        paths.add(argument);
      }
    }

    if (platform != null && platform != 'vm') {
      return BenchmarkTestInvocation.error(
        'Unsupported platform `$platform`. Only `vm` is supported.',
      );
    }

    compiler ??= 'kernel';
    if (compiler != 'kernel' && compiler != 'exe') {
      return BenchmarkTestInvocation.error(
        'Unsupported compiler `$compiler`. Supported values: kernel, exe.',
      );
    }

    return BenchmarkTestInvocation(
      compiler: compiler,
      enableAsserts: enableAsserts,
      paths: List.unmodifiable(paths),
      nameFilter: nameFilter,
    );
  }
}

String? validateBenchmarkReporter(String value) {
  const supportedReporters = {'expanded'};
  if (supportedReporters.contains(value)) return null;
  return 'Unsupported reporter `$value` for assert-free benchmarks. '
      'Supported reporters: expanded.';
}
