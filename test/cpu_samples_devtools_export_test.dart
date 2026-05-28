import 'dart:convert';
import 'dart:io';

import 'package:benchmark_test/src/cli/cpu_samples_devtools_export.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  group('convertCpuSamplesToDevToolsSnapshot', () {
    test('produces a DevTools-importable snapshot envelope', () async {
      final cpuSamples = _minimalCpuSamples();
      final snapshot = await convertCpuSamplesToDevToolsSnapshot(
        cpuSamples,
        'isolates/test',
        devToolsVersion: '2.54.2',
      );

      expect(snapshot['devToolsSnapshot'], isTrue);
      expect(snapshot['activeScreenId'], 'cpu-profiler');
      expect(snapshot['devToolsVersion'], '2.54.2');

      final cpuProfiler = snapshot['cpu-profiler'] as Map<String, dynamic>;
      expect(cpuProfiler['type'], '_CpuProfileTimeline');
      expect(cpuProfiler['sampleCount'], 2);
      expect(cpuProfiler['stackFrames'], isA<Map<String, dynamic>>());
      expect(cpuProfiler['traceEvents'], isA<List<dynamic>>());

      final stackFrames = cpuProfiler['stackFrames'] as Map<String, dynamic>;
      expect(stackFrames, isNotEmpty);

      final traceEvents = cpuProfiler['traceEvents'] as List<dynamic>;
      expect(traceEvents, hasLength(2));
      expect(traceEvents.first['ph'], 'P');
      expect(traceEvents.first['sf'], isA<String>());
    });

    test('maps SDK resolved URLs to dart: packageUri for flame chart',
        () async {
      final cpuSamples = _sdkCpuSamples();
      final snapshot = await convertCpuSamplesToDevToolsSnapshot(
        cpuSamples,
        'isolates/test',
        devToolsVersion: '2.54.2',
      );

      final stackFrames =
          (snapshot['cpu-profiler'] as Map)['stackFrames'] as Map;
      final sdkFrame = stackFrames.values.cast<Map>().firstWhere(
            (frame) => (frame['resolvedUrl'] as String).contains(
              'org-dartlang-sdk',
            ),
          );
      expect(sdkFrame['packageUri'], startsWith('dart:'));
    });

    test('converts a saved .cpu.json file', () async {
      final cpuPath = 'build/benchmark_test/profiles/001_100ms.cpu.json';
      if (!File(cpuPath).existsSync()) {
        markTestSkipped('Run --profile once to generate $cpuPath');
      }

      final cpuJson =
          jsonDecode(File(cpuPath).readAsStringSync()) as Map<String, dynamic>;
      final cpuSamples = CpuSamples.parse(cpuJson)!;

      final snapshot = await convertCpuSamplesToDevToolsSnapshot(
        cpuSamples,
        'isolates/benchmark',
        devToolsVersion: '2.54.2',
      );

      final cpuProfiler = snapshot['cpu-profiler'] as Map<String, dynamic>;
      expect(cpuProfiler['sampleCount'], cpuSamples.sampleCount);
      final traceEvents = cpuProfiler['traceEvents'] as List;
      expect(traceEvents, isNotEmpty);
      expect(traceEvents.length, lessThanOrEqualTo(cpuSamples.sampleCount!));
    });

    test('convertCpuSamplesFileToDevToolsSnapshot writes output', () async {
      final temp = await Directory.systemTemp.createTemp('benchmark_devtools_');
      addTearDown(() => temp.delete(recursive: true));

      final input = File('${temp.path}/in.cpu.json');
      await input.writeAsString(jsonEncode(_minimalCpuSamples().toJson()));

      final output = File('${temp.path}/out.devtools.json');
      await convertCpuSamplesFileToDevToolsSnapshot(
        input: input,
        output: output,
        isolateId: 'isolates/test',
        devToolsVersion: '2.54.2',
      );

      final written =
          jsonDecode(output.readAsStringSync()) as Map<String, dynamic>;
      expect(written['devToolsSnapshot'], isTrue);
      expect(written['cpu-profiler'], isNotNull);
    });

    test(
        'postProcessDevToolsSnapshot collapses wrappers and labels benchmark body',
        () {
      final snapshot = {
        'devToolsSnapshot': true,
        'activeScreenId': 'cpu-profiler',
        'cpu-profiler': {
          'type': '_CpuProfileTimeline',
          'sampleCount': 2,
          'stackDepth': 6,
          'stackFrames': {
            'a1': {
              'name': 'BenchmarkSampler.sample',
              'category': 'Dart',
              'resolvedUrl': 'file:///sampler.dart',
              'packageUri':
                  'package:benchmark_test/src/benchmark/benchmark_sampler.dart',
              'parent': 'a2',
            },
            'a2': {
              'name': '<anonymous closure>',
              'category': 'Dart',
              'resolvedUrl':
                  'org-dartlang-sdk:///sdk/lib/async/future_impl.dart',
              'packageUri': 'dart:async/future_impl.dart',
              'parent': 'a3',
            },
            'a3': {
              'name': '_runPendingImmediateCallback',
              'category': 'Dart',
              'resolvedUrl':
                  'org-dartlang-sdk:///sdk/lib/isolate/timer_impl.dart',
              'packageUri': 'dart:isolate-patch/timer_impl.dart',
              'parent': 'a4',
            },
            'a4': {
              'name': '_Timer._runTimers',
              'category': 'Dart',
              'resolvedUrl':
                  'org-dartlang-sdk:///sdk/lib/isolate/timer_impl.dart',
              'packageUri': 'dart:isolate-patch/timer_impl.dart',
              'parent': 'cpuProfileRoot',
            },
            'b1': {
              'name': 'BenchmarkSampler.sample',
              'category': 'Dart',
              'resolvedUrl': 'file:///sampler.dart',
              'packageUri':
                  'package:benchmark_test/src/benchmark/benchmark_sampler.dart',
              'parent': 'b3',
            },
            'b2': {
              'name': '<anonymous closure>',
              'category': 'Dart',
              'resolvedUrl': 'file:///benchmark.dart',
              'packageUri':
                  'package:benchmark_test/src/benchmark/benchmark.dart',
              'parent': 'b1',
            },
            'b3': {
              'name': '_RawReceivePort._handleMessage',
              'category': 'Dart',
              'resolvedUrl':
                  'org-dartlang-sdk:///sdk/lib/isolate-patch/isolate_patch.dart',
              'packageUri': 'dart:isolate-patch/isolate_patch.dart',
              'parent': 'cpuProfileRoot',
            },
          },
          'traceEvents': [
            {'ph': 'P', 'sf': 'a1'},
            {'ph': 'P', 'sf': 'b2'},
          ],
        },
      };

      final processed = postProcessDevToolsSnapshot(
        snapshot,
        benchmarkName: 'delay 100ms',
      );
      final cpuProfiler = processed['cpu-profiler'] as Map<String, dynamic>;
      final stackFrames = cpuProfiler['stackFrames'] as Map<String, dynamic>;

      final byName = {
        for (final frame in stackFrames.values.cast<Map<String, dynamic>>())
          frame['name'] as String: frame,
      };
      expect(stackFrames.length, greaterThanOrEqualTo(1));
      expect(byName['BenchmarkSampler.sample'], isNull);
      expect(byName['<benchmark body: delay 100ms>'], isNotNull);
      expect(
        byName.keys,
        isNot(contains('_runPendingImmediateCallback')),
      );
      expect(
        byName.keys,
        isNot(contains('_Timer._runTimers')),
      );
      expect(
        byName.keys,
        isNot(contains('_RawReceivePort._handleMessage')),
      );
    });
  });
}

CpuSamples _sdkCpuSamples() {
  return CpuSamples.parse({
    'type': 'CpuSamples',
    'samplePeriod': 1000,
    'maxStackDepth': 8,
    'sampleCount': 1,
    'timeOriginMicros': 100,
    'timeExtentMicros': 1000,
    'pid': 42,
    'functions': [
      {
        'kind': 'Dart',
        'resolvedUrl': 'org-dartlang-sdk:///sdk/lib/core/object.dart',
        'function': {
          'type': '@Function',
          'name': 'hashCode',
          'owner': {'type': '@Class', 'name': 'Object'},
        },
      },
    ],
    'samples': [
      {
        'tid': 1,
        'timestamp': 100,
        'stack': [0]
      },
    ],
  })!;
}

CpuSamples _minimalCpuSamples() {
  return CpuSamples.parse({
    'type': 'CpuSamples',
    'samplePeriod': 1000,
    'maxStackDepth': 8,
    'sampleCount': 2,
    'timeOriginMicros': 100,
    'timeExtentMicros': 2000,
    'pid': 42,
    'functions': [
      {
        'kind': 'Dart',
        'resolvedUrl': 'file:///main.dart',
        'function': {
          'type': '@Function',
          'name': 'main',
          'owner': {
            'type': '@Library',
            'name': 'main',
            'uri': 'file:///main.dart',
          },
          'location': {
            'type': 'SourceLocation',
            'line': 1,
            'script': {'type': '@Script', 'uri': 'file:///main.dart'},
          },
        },
      },
      {
        'kind': 'Dart',
        'resolvedUrl': 'file:///main.dart',
        'function': {
          'type': '@Function',
          'name': 'work',
          'owner': {'type': '@Class', 'name': 'Bench'},
          'location': {
            'type': 'SourceLocation',
            'line': 2,
            'script': {'type': '@Script', 'uri': 'file:///main.dart'},
          },
        },
      },
    ],
    'samples': [
      {
        'tid': 1,
        'timestamp': 100,
        'stack': [1, 0]
      },
      {
        'tid': 1,
        'timestamp': 1100,
        'stack': [1, 0]
      },
    ],
  })!;
}
