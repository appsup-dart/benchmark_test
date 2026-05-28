import 'dart:math' as math;

class BenchmarkResult {
  final String name;
  final String compiler;
  final double operationsPerSecond;
  final double relativeMarginOfError;
  final int runs;
  final Duration averageDuration;

  BenchmarkResult({
    required this.name,
    required this.compiler,
    required this.operationsPerSecond,
    required this.relativeMarginOfError,
    required this.runs,
    required this.averageDuration,
  });

  static BenchmarkResult? fromJson(
    Object? value, {
    required String name,
    String? compiler,
  }) {
    if (value is! Map) return null;

    var throughput = value['throughput'];
    var statistics = value['statistics'];
    var latency = value['latency'];
    if (throughput is! Map || statistics is! Map || latency is! Map) {
      return null;
    }

    var operationsPerSecond = throughput['value'];
    var relativeMarginOfError = statistics['relativeMarginOfError'];
    var samples = statistics['samples'];
    var meanLatency = latency['mean'];
    if (operationsPerSecond is! num ||
        relativeMarginOfError is! num ||
        samples is! num ||
        meanLatency is! num) {
      return null;
    }

    return BenchmarkResult(
      name: name,
      compiler: _compilerFromJson(value, compiler),
      operationsPerSecond: operationsPerSecond.toDouble(),
      relativeMarginOfError: relativeMarginOfError.toDouble(),
      runs: samples.toInt(),
      averageDuration: Duration(microseconds: meanLatency.toInt()),
    );
  }

  String get formattedOperationsPerSecond {
    var precision = -(math.log(operationsPerSecond) / math.ln10).ceil() + 3;
    return operationsPerSecond.toStringAsFixed(math.max(precision, 0));
  }

  String get formattedRelativeMarginOfError =>
      relativeMarginOfError.toStringAsFixed(2);

  Map<String, Object> toJson() {
    return {
      'formatVersion': 1,
      'name': name,
      'compiler': compiler,
      'throughput': {
        'value': operationsPerSecond,
        'unit': 'ops/sec',
      },
      'statistics': {
        'relativeMarginOfError': relativeMarginOfError,
        'samples': runs,
      },
      'latency': {
        'mean': averageDuration.inMicroseconds,
        'unit': 'microseconds',
      },
    };
  }

  static String _compilerFromJson(Map value, String? compiler) {
    if (compiler != null && compiler.isNotEmpty) return compiler;
    final fromJson = value['compiler'];
    if (fromJson is String && fromJson.isNotEmpty) return fromJson;
    return 'unknown';
  }
}
