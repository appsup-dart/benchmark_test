import 'benchmark_configuration.dart';

/// Whether benchmarks should pause for CPU profiling.
///
/// Controlled by [configureBenchmarkRunner].
bool get isProfileMode => benchmarkConfiguration.profileMode;
