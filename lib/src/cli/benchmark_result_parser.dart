import 'dart:convert';

import '../benchmark/benchmark_result.dart';

List<BenchmarkResult> parseBenchmarkJsonlOutput(String output) {
  final results = <BenchmarkResult>[];
  for (final line in output.split('\n')) {
    if (line.trim().isEmpty) continue;

    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      continue;
    }

    if (decoded is! Map) continue;
    final name = decoded['name'];
    if (name is! String) continue;

    final result = BenchmarkResult.fromJson(decoded, name: name);
    if (result != null) results.add(result);
  }
  return results;
}
