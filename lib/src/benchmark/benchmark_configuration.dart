/// Runtime configuration for benchmark execution.
class BenchmarkConfiguration {
  bool emitJsonlResults = false;
  bool profileMode = false;
  int timeoutMultiplier = 1;
  String compilerType = 'jit';
}

final benchmarkConfiguration = BenchmarkConfiguration();

/// Configures benchmark behavior for the direct runner child process.
void configureBenchmarkRunner({
  bool emitJsonlResults = false,
  bool profileMode = false,
  int timeoutMultiplier = 1,
  String compilerType = 'jit',
}) {
  benchmarkConfiguration.emitJsonlResults = emitJsonlResults;
  benchmarkConfiguration.profileMode = profileMode;
  benchmarkConfiguration.timeoutMultiplier = timeoutMultiplier;
  benchmarkConfiguration.compilerType = compilerType;
}
