/// Runtime configuration for benchmark execution.
class BenchmarkConfiguration {
  bool emitJsonlResults = false;
}

final benchmarkConfiguration = BenchmarkConfiguration();

/// Configures benchmark behavior for the direct runner child process.
void configureBenchmarkRunner({bool emitJsonlResults = false}) {
  benchmarkConfiguration.emitJsonlResults = emitJsonlResults;
}
