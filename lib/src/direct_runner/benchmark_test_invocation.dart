import 'benchmark_test_name_filter.dart';

/// Parameters for a single direct benchmark run.
class BenchmarkTestInvocation {
  final String compiler;
  final bool enableAsserts;
  final bool runSkipped;
  final bool profile;
  final List<String> paths;
  final BenchmarkNameFilter? nameFilter;

  const BenchmarkTestInvocation({
    required this.compiler,
    required this.enableAsserts,
    required this.runSkipped,
    this.profile = false,
    required this.paths,
    required this.nameFilter,
  });
}
