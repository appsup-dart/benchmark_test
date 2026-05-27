import 'benchmark_compile_type.dart';

class BenchmarkCliConfig {
  final List<BenchmarkCompileType> compileTypes;
  final bool enableAsserts;
  final String? outputFormat;
  final List<String> paths;
  final List<String> testRunnerArguments;
  final bool showHelp;
  final String? error;

  BenchmarkCliConfig({
    required this.compileTypes,
    required this.enableAsserts,
    required this.outputFormat,
    required this.paths,
    required this.testRunnerArguments,
  })  : showHelp = false,
        error = null;

  BenchmarkCliConfig.help()
      : compileTypes = const [],
        enableAsserts = false,
        outputFormat = null,
        paths = const [],
        testRunnerArguments = const [],
        showHelp = true,
        error = null;

  BenchmarkCliConfig.error(this.error)
      : compileTypes = const [],
        enableAsserts = false,
        outputFormat = null,
        paths = const [],
        testRunnerArguments = const [],
        showHelp = false;
}
