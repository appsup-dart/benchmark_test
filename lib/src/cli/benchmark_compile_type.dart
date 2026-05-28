enum BenchmarkCompileType {
  jit('jit', 'kernel'),
  aot('aot', 'exe'),
  js('js', 'js');

  const BenchmarkCompileType(this.label, this.testCompiler);

  final String label;
  final String testCompiler;

  static BenchmarkCompileType? tryParse(String value) {
    for (final compileType in values) {
      if (compileType.label == value) return compileType;
    }
    return null;
  }
}

const defaultBenchmarkCompileTypes = [
  BenchmarkCompileType.jit,
];

String? addBenchmarkCompileTypes(
  List<BenchmarkCompileType> compileTypes,
  List<String> rawValues,
) {
  for (final value in rawValues) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'Compile type cannot be empty.';
    }

    if (normalized == 'all') {
      for (final compileType in BenchmarkCompileType.values) {
        if (!compileTypes.contains(compileType)) compileTypes.add(compileType);
      }
      continue;
    }

    final compileType = BenchmarkCompileType.tryParse(normalized);
    if (compileType == null) {
      return 'Unsupported compile type `$value`. Supported values: jit, aot, js.';
    }

    if (!compileTypes.contains(compileType)) compileTypes.add(compileType);
  }

  return null;
}
