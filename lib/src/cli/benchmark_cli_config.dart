import '../direct_runner/benchmark_test_name_filter.dart';
import 'benchmark_compile_type.dart';

class BenchmarkCliConfig {
  final List<BenchmarkCompileType> compileTypes;
  final bool enableAsserts;
  final bool runSkipped;
  final bool profile;
  final bool updateBaseline;
  final String? outputFormat;
  final List<String> paths;
  final BenchmarkNameFilter? nameFilter;
  final bool showHelp;
  final String? error;

  BenchmarkCliConfig({
    required this.compileTypes,
    required this.enableAsserts,
    required this.runSkipped,
    required this.profile,
    required this.updateBaseline,
    required this.outputFormat,
    required this.paths,
    required this.nameFilter,
  })  : showHelp = false,
        error = null;

  BenchmarkCliConfig.help()
      : compileTypes = const [],
        enableAsserts = false,
        runSkipped = false,
        profile = false,
        updateBaseline = false,
        outputFormat = null,
        paths = const [],
        nameFilter = null,
        showHelp = true,
        error = null;

  BenchmarkCliConfig.error(this.error)
      : compileTypes = const [],
        enableAsserts = false,
        runSkipped = false,
        profile = false,
        updateBaseline = false,
        outputFormat = null,
        paths = const [],
        nameFilter = null,
        showHelp = false;
}
