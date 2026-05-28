import 'package:benchmark_test/src/cli/benchmark_vm_profile_session.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  group('filterCpuSamplesByUserTag', () {
    test('keeps only samples tagged benchmark-body', () {
      final samples = CpuSamples.parse({
        'type': 'CpuSamples',
        'samplePeriod': 1000,
        'maxStackDepth': 8,
        'sampleCount': 3,
        'timeOriginMicros': 100,
        'timeExtentMicros': 3000,
        'pid': 42,
        'functions': [
          {
            'kind': 'Dart',
            'resolvedUrl': 'file:///main.dart',
            'function': {
              'type': '@Function',
              'name': 'main',
              'owner': {'type': '@Library', 'name': 'main'},
            },
          },
        ],
        'samples': [
          {
            'tid': 1,
            'timestamp': 100,
            'stack': [0],
            'userTag': 'setup',
          },
          {
            'tid': 1,
            'timestamp': 200,
            'stack': [0],
            'userTag': 'benchmark-body',
          },
          {
            'tid': 1,
            'timestamp': 300,
            'stack': [0],
            'userTag': 'teardown',
          },
        ],
      })!;

      final filtered = filterCpuSamplesByUserTag(samples, 'benchmark-body');
      expect(filtered.sampleCount, 1);
      expect(filtered.samples, hasLength(1));
      expect(filtered.samples!.single.userTag, 'benchmark-body');
      expect(filtered.timeOriginMicros, 200);
      expect(filtered.timeExtentMicros, 0);
    });

    test('falls back to original profile when tag is missing', () {
      final samples = CpuSamples.parse({
        'type': 'CpuSamples',
        'samplePeriod': 1000,
        'maxStackDepth': 8,
        'sampleCount': 2,
        'timeOriginMicros': 100,
        'timeExtentMicros': 2000,
        'pid': 42,
        'functions': [],
        'samples': [
          {'tid': 1, 'timestamp': 100, 'stack': const <int>[]},
          {'tid': 1, 'timestamp': 200, 'stack': const <int>[]},
        ],
      })!;

      final filtered = filterCpuSamplesByUserTag(samples, 'benchmark-body');
      expect(filtered.sampleCount, samples.sampleCount);
      expect(filtered.samples, hasLength(samples.samples!.length));
    });
  });
}
