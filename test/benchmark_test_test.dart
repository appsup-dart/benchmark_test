import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('benchmark', () {
    test('iteration of 100ms should run about 20 times', () {
      var r = _runBenchmark('delay 100ms');

      expect(r[0], closeTo(10, 0.5));
      expect(r[2], closeTo(20, 1));
    });

    test(
        'iteration of 100ms should run about 40 times when minDuration 4 seconds',
        () {
      var r = _runBenchmark('delay 100ms, minDuration 4 seconds');

      expect(r[0], closeTo(10, 0.5));
      expect(r[2], closeTo(40, 1));
    });

    test('iteration of 100ms should run 30 times when minSamples 30', () {
      var r = _runBenchmark('delay 100ms, minSamples 30');

      expect(r[0], closeTo(10, 0.5));
      expect(r[2], 30);
    });
  });

  group('setUpEach', () {
    test('should be called before each iteration', () {
      _runBenchmark('setUpEach group 2 100ms');
    });
  });
  group('tearDownEach', () {
    test('should be called after each iteration', () {
      _runBenchmark('tearDownEach group 2 100ms');
    });
  });
}

List<num> _runBenchmark(String name) {
  var v = Process.runSync(
      'dart', ['test', 'test/src/benchmark.dart', '--no-color', '-n', name]);

  var o = _parseOutput(v.stdout);
  if (!o.containsKey(name)) {
    throw Exception('Benchmark failed: ${v.stdout}');
  }
  return o[name]!;
}

Map<String, List<num>> _parseOutput(String output) {
  var lines = output.split('\n');
  var results = <String, List<num>>{};
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    var m =
        RegExp(r'(.*) x ([0-9\.]+) ops/sec ±([0-9\.]+)% \((\d+) runs sampled\)')
            .firstMatch(line);

    if (m != null) {
      var ops = num.parse(m.group(2)!);
      var margin = num.parse(m.group(3)!);
      var runs = num.parse(m.group(4)!);
      results[m.group(1)!] = [ops, margin, runs];
    }
  }
  return results;
}
