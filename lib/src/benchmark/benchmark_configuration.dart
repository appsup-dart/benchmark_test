/// Runtime configuration for benchmark execution.
class BenchmarkConfiguration {
  bool emitJsonlResults = false;
  bool profileMode = false;
  int timeoutMultiplier = 1;
}

final benchmarkConfiguration = BenchmarkConfiguration();

/// Configures benchmark behavior for the direct runner child process.
void configureBenchmarkRunner({
  bool emitJsonlResults = false,
  bool profileMode = false,
  int timeoutMultiplier = 1,
}) {
  benchmarkConfiguration.emitJsonlResults = emitJsonlResults;
  benchmarkConfiguration.profileMode = profileMode;
  benchmarkConfiguration.timeoutMultiplier = timeoutMultiplier;
}
