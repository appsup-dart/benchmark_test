/// Runtime configuration for benchmark execution.
class BenchmarkConfiguration {
  bool emitJsonlResults = false;
  bool profileMode = false;
}

final benchmarkConfiguration = BenchmarkConfiguration();

/// Configures benchmark behavior for the direct runner child process.
void configureBenchmarkRunner({
  bool emitJsonlResults = false,
  bool profileMode = false,
}) {
  benchmarkConfiguration.emitJsonlResults = emitJsonlResults;
  benchmarkConfiguration.profileMode = profileMode;
}
