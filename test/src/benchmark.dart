import 'package:benchmark_test/benchmark_test.dart';
import 'package:test/test.dart';

void main() {
  group('delay', () {
    benchmark('10ms baseline fixture', () async {
      await Future.delayed(Duration(milliseconds: 10));
    }, minDuration: Duration(milliseconds: 50));

    benchmark('100ms', () async {
      await Future.delayed(Duration(milliseconds: 100));
    });

    benchmark('100ms, minDuration 4 seconds', () async {
      await Future.delayed(Duration(milliseconds: 100));
    }, minDuration: Duration(seconds: 4));

    benchmark('100ms, minSamples 30', () async {
      await Future.delayed(Duration(milliseconds: 100));
    }, minSamples: 30);

    benchmark('1ms, minSamples 3', () async {
      await Future.delayed(Duration(milliseconds: 1));
    },
        minDuration: Duration.zero,
        minSamples: 3,
        timeout: Timeout(Duration(seconds: 1)));
  });

  group('setUpEach', () {
    var called1 = false;
    var called2 = false;
    var called3 = false;
    setUpEach(() {
      called1 = true;
    });

    group('group 1', () {
      setUpEach(() {
        called2 = true;
      });

      benchmark('100ms', () async {
        expect(called1, isTrue);
        expect(called2, isTrue);
        expect(called3, isFalse);
        await Future.delayed(Duration(milliseconds: 100));
        called1 = false;
        called2 = false;
        called3 = false;
      });
    });

    group('group 2', () {
      setUpEach(() {
        called3 = true;
      });

      benchmark('100ms', () async {
        expect(called1, isTrue);
        expect(called2, isFalse);
        expect(called3, isTrue);
        await Future.delayed(Duration(milliseconds: 100));
        called1 = false;
        called2 = false;
        called3 = false;
      });
    });
  });

  group('tearDownEach', () {
    var called1 = true;
    var called2 = false;
    var called3 = true;
    tearDownEach(() {
      called1 = true;
    });

    group('group 1', () {
      tearDownEach(() {
        called2 = true;
      });
    });

    group('group 2', () {
      tearDownEach(() {
        called3 = true;
      });

      benchmark('100ms', () async {
        expect(called1, isTrue);
        expect(called2, isFalse);
        expect(called3, isTrue);
        await Future.delayed(Duration(milliseconds: 100));
        called1 = false;
        called2 = false;
        called3 = false;
      });
    });
  });
}
