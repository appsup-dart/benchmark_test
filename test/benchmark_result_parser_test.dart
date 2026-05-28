import 'package:benchmark_test/src/cli/benchmark_result_parser.dart';
import 'package:test/test.dart';

void main() {
  test('parseBenchmarkJsonlOutput reads benchmark result lines', () {
    const output = '''
noise from test runner
{"formatVersion":1,"name":"bench a","throughput":{"value":10,"unit":"ops/sec"},"statistics":{"relativeMarginOfError":1,"samples":5},"latency":{"mean":100,"unit":"microseconds"}}
{"formatVersion":1,"name":"bench b","compiler":"aot","throughput":{"value":20,"unit":"ops/sec"},"statistics":{"relativeMarginOfError":2,"samples":6},"latency":{"mean":200,"unit":"microseconds"}}
''';

    final results = parseBenchmarkJsonlOutput(output);

    expect(results, hasLength(2));
    expect(results[0].name, 'bench a');
    expect(results[0].compiler, 'unknown');
    expect(results[0].operationsPerSecond, 10);
    expect(results[1].name, 'bench b');
    expect(results[1].compiler, 'aot');
  });
}
