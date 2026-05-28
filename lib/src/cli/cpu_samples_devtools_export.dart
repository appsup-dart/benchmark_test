import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:vm_service/vm_service.dart';

/// Converts VM service [CpuSamples] into a JSON snapshot importable by Dart
/// DevTools (CPU Profiler → Import).
///
/// The format matches DevTools export files: `devToolsSnapshot` plus a
/// `cpu-profiler` section with `_CpuProfileTimeline`, `stackFrames`, and
/// `traceEvents`. Logic is adapted from Flutter DevTools
/// `CpuProfileData.generateFromCpuSamples`.
Future<Map<String, dynamic>> convertCpuSamplesToDevToolsSnapshot(
  CpuSamples cpuSamples,
  String isolateId, {
  VmService? vmService,
  String? devToolsVersion,
}) async {
  final profile = await _buildCpuProfileTimeline(
    cpuSamples,
    isolateId,
    vmService: vmService,
  );
  return {
    'devToolsSnapshot': true,
    'devToolsVersion': devToolsVersion ?? _defaultDevToolsVersion,
    'connectedApp': {
      'isFlutterApp': false,
      'isProfileBuild': false,
      'isDartWebApp': false,
      'isRunningOnDartVM': true,
      'operatingSystem': Platform.operatingSystem,
    },
    'activeScreenId': 'cpu-profiler',
    'cpu-profiler': profile,
  };
}

/// Reads a VM service [CpuSamples] JSON file and writes a DevTools snapshot.
Future<void> convertCpuSamplesFileToDevToolsSnapshot({
  required File input,
  required File output,
  required String isolateId,
  String? devToolsVersion,
}) async {
  final json = jsonDecode(await input.readAsString()) as Map<String, dynamic>;
  final cpuSamples = CpuSamples.parse(json);
  if (cpuSamples == null) {
    throw FormatException('Not a VM service CpuSamples file: ${input.path}');
  }
  final snapshot = await convertCpuSamplesToDevToolsSnapshot(
    cpuSamples,
    isolateId,
    devToolsVersion: devToolsVersion,
  );
  await output.writeAsString(jsonEncode(snapshot));
}

String get _defaultDevToolsVersion {
  // Cached at first use; falls back if `dart devtools --version` fails.
  return _cachedDevToolsVersion ??= _readDevToolsVersion();
}

String? _cachedDevToolsVersion;

String _readDevToolsVersion() {
  try {
    final result = Process.runSync(
      Platform.resolvedExecutable,
      ['devtools', '--version'],
    );
    final output = '${result.stdout}${result.stderr}';
    final match = RegExp(
      r'Dart DevTools version (\S+)',
    ).firstMatch(output);
    return match?.group(1) ?? '0.0.0';
  } on Object {
    return '0.0.0';
  }
}

Future<Map<String, dynamic>> _buildCpuProfileTimeline(
  CpuSamples cpuSamples,
  String isolateId, {
  VmService? vmService,
}) async {
  final samplePeriod = _calculateSamplePeriod(cpuSamples);
  final treeRoot = _CpuProfileTimelineTree.fromCpuSamples(cpuSamples);
  final packageUriByResolvedUrl = await _resolvePackageUris(
    vmService: vmService,
    isolateId: isolateId,
    resolvedUrls: _collectResolvedUrls(treeRoot),
  );
  final stackFrames = _generateStackFrames(
    cpuSamples: cpuSamples,
    isolateId: isolateId,
    treeRoot: treeRoot,
    packageUriByResolvedUrl: packageUriByResolvedUrl,
  );
  final traceEvents = _convertSamplesToTraceEvents(
    cpuSamples: cpuSamples,
    isolateId: isolateId,
  );

  return {
    'type': '_CpuProfileTimeline',
    'samplePeriod': samplePeriod,
    'sampleCount': cpuSamples.sampleCount ?? 0,
    'stackDepth': cpuSamples.maxStackDepth ?? 0,
    'timeOriginMicros': cpuSamples.timeOriginMicros,
    'timeExtentMicros': cpuSamples.timeExtentMicros,
    'stackFrames': stackFrames,
    'traceEvents': traceEvents,
  };
}

int _calculateSamplePeriod(CpuSamples cpuSamples) {
  final samples = cpuSamples.samples;
  if (samples == null || samples.isEmpty) {
    return cpuSamples.samplePeriod ?? 0;
  }

  final timestamps = samples.map((s) => s.timestamp).nonNulls.toList()..sort();
  return _observedSamplePeriod(timestamps) ?? cpuSamples.samplePeriod ?? 0;
}

int? _observedSamplePeriod(List<int> timestamps) {
  if (timestamps.length < 100) return null;

  final mediansOfGroupsOf5 = <int>[];
  for (var i = 1; i + 5 < timestamps.length; i += 5) {
    int diff(int index) => timestamps[index] - timestamps[index - 1];
    mediansOfGroupsOf5.add(
      _median5(diff(i), diff(i + 1), diff(i + 2), diff(i + 3), diff(i + 4)),
    );
  }
  mediansOfGroupsOf5.sort();
  return mediansOfGroupsOf5[(mediansOfGroupsOf5.length / 2).floor()];
}

int _median5(int a, int b, int c, int d, int e) {
  while (true) {
    if (c < a) {
      final t = a;
      a = c;
      c = t;
    } else if (c < b) {
      final t = b;
      b = c;
      c = t;
    } else if (c > d) {
      final t = c;
      c = d;
      d = t;
    } else if (c > e) {
      final t = c;
      c = e;
      e = t;
    } else {
      return c;
    }
  }
}

Set<String> _collectResolvedUrls(_CpuProfileTimelineTree treeRoot) {
  final urls = <String>{};
  void visit(_CpuProfileTimelineTree node) {
    final url = node.resolvedUrl;
    if (url != null && url.isNotEmpty) {
      urls.add(url);
    }
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(treeRoot);
  return urls;
}

/// Resolves VM [resolvedUrl]s to [packageUri]s via `lookupPackageUris`, as
/// DevTools does. Flame chart colors use `packageUri` (`dart:` = SDK, empty =
/// native, `package:` / `file:` = app).
Future<Map<String, String>> _resolvePackageUris({
  required VmService? vmService,
  required String isolateId,
  required Set<String> resolvedUrls,
}) async {
  final result = <String, String>{};
  if (vmService != null && resolvedUrls.isNotEmpty) {
    const batchSize = 100;
    final urls = resolvedUrls.toList();
    for (var i = 0; i < urls.length; i += batchSize) {
      final batch = urls.sublist(i, min(i + batchSize, urls.length));
      final uriList = await vmService.lookupPackageUris(isolateId, batch);
      final packageUris = uriList.uris ?? const <String?>[];
      for (var j = 0; j < batch.length; j++) {
        final packageUri = j < packageUris.length ? packageUris[j] : null;
        if (packageUri != null && packageUri.isNotEmpty) {
          result[batch[j]] = packageUri;
        }
      }
    }
  }

  for (final url in resolvedUrls) {
    result.putIfAbsent(
      url,
      () => _heuristicPackageUri(url) ?? url,
    );
  }
  return result;
}

Map<String, Map<String, Object?>> _generateStackFrames({
  required CpuSamples cpuSamples,
  required String isolateId,
  required _CpuProfileTimelineTree treeRoot,
  required Map<String, String> packageUriByResolvedUrl,
}) {
  final frames = <String, Map<String, Object?>>{};
  var nextFrameId = _kRootFrameId;

  void processNode(
    _CpuProfileTimelineTree current,
    _CpuProfileTimelineTree? parent,
  ) {
    final frameId = nextFrameId++;
    current.frameId = frameId;

    if (parent != null) {
      final id = current.stackFrameId(isolateId);
      final verboseName = _verboseNameForNode(current);
      final resolvedUrl = current.resolvedUrl ?? '';
      frames[id] = {
        'name': verboseName,
        'category': 'Dart',
        'resolvedUrl': resolvedUrl,
        'packageUri': resolvedUrl.isEmpty
            ? ''
            : packageUriByResolvedUrl[resolvedUrl] ?? resolvedUrl,
        if (current.sourceLine != null) 'sourceLine': current.sourceLine,
        'parent': parent.stackFrameId(isolateId),
      };
    }

    for (final child in current.children) {
      processNode(child, current);
    }
  }

  processNode(treeRoot, null);
  return frames;
}

List<Map<String, Object?>> _convertSamplesToTraceEvents({
  required CpuSamples cpuSamples,
  required String isolateId,
}) {
  final events = <Map<String, Object?>>[];
  for (final sample in cpuSamples.samples ?? const <CpuSample>[]) {
    final node = _CpuProfileTimelineTree.nodeForSample(sample);
    if (node == null || node.frameId == _kRootFrameId) continue;

    final stackFrameId = node.stackFrameId(isolateId);
    events.add({
      'ph': 'P',
      'name': '',
      'pid': cpuSamples.pid,
      'tid': sample.tid,
      'ts': sample.timestamp,
      'cat': 'Dart',
      'sf': stackFrameId,
      'args': {
        if (sample.userTag != null) 'userTag': sample.userTag,
        if (sample.vmTag != null) 'vmTag': sample.vmTag,
      },
    });
  }
  return events;
}

/// Best-effort mapping when [VmService.lookupPackageUris] is unavailable (e.g.
/// converting a saved `.cpu.json` offline).
String? _heuristicPackageUri(String resolvedUrl) {
  const sdkPrefix = 'org-dartlang-sdk:///sdk/lib/';
  if (!resolvedUrl.startsWith(sdkPrefix)) {
    return null;
  }

  final path = resolvedUrl.substring(sdkPrefix.length);

  final vmPatch = RegExp(r'^_internal/vm/lib/(.+)_patch\.dart$');
  final vmPatchMatch = vmPatch.firstMatch(path);
  if (vmPatchMatch != null) {
    final base = vmPatchMatch.group(1)!;
    return 'dart:$base-patch/${base}_patch.dart';
  }

  final vmShared = RegExp(r'^_internal/vm_shared/lib/([^.]+)\.dart$');
  final vmSharedMatch = vmShared.firstMatch(path);
  if (vmSharedMatch != null) {
    return 'dart:_${vmSharedMatch.group(1)}';
  }

  if (path.startsWith('internal/')) {
    return 'dart:_internal/${path.substring('internal/'.length)}';
  }

  if (!path.startsWith('_internal/')) {
    return 'dart:$path';
  }

  return null;
}

String _verboseNameForNode(_CpuProfileTimelineTree node) {
  final className = node.className;
  final name = node.name;
  if (className != null && name != null) {
    return '$className.$name';
  }
  return name ?? '<unknown>';
}

const _kRootFrameId = 0;
const _cpuProfileRootId = 'cpuProfileRoot';

class _CpuProfileTimelineTree {
  _CpuProfileTimelineTree._(this.cpuSamples, this.functionIndex);

  factory _CpuProfileTimelineTree.fromCpuSamples(CpuSamples cpuSamples) {
    _sampleToLeafNode.clear();
    final root = _CpuProfileTimelineTree._(cpuSamples, _kRootFunctionIndex);
    for (final sample in cpuSamples.samples ?? const <CpuSample>[]) {
      var current = root;
      final stack = sample.stack;
      if (stack == null || stack.isEmpty) continue;
      for (final index in stack.reversed) {
        current = current._childForIndex(index);
      }
      _sampleToLeafNode[sample] = current;
    }
    return root;
  }

  static const _kRootFunctionIndex = -1;
  static final _sampleToLeafNode = <CpuSample, _CpuProfileTimelineTree>{};

  static _CpuProfileTimelineTree? nodeForSample(CpuSample sample) =>
      _sampleToLeafNode[sample];

  final CpuSamples cpuSamples;
  final int functionIndex;
  int frameId = _kRootFrameId;
  final children = <_CpuProfileTimelineTree>[];

  String stackFrameId(String isolateId) => frameId == _kRootFrameId
      ? _cpuProfileRootId
      : '$isolateId-$frameId';

  String? get name {
    final function = _profileFunction?.function;
    if (function is FuncRef) return function.name;
    if (function is NativeFunction) return function.name;
    return null;
  }

  String? get className {
    final function = _profileFunction?.function;
    if (function is FuncRef) {
      final owner = function.owner;
      if (owner is ClassRef) return owner.name;
    }
    return null;
  }

  String? get resolvedUrl {
    final url = _profileFunction?.resolvedUrl;
    if (url != null && url.isNotEmpty) return url;
    final function = _profileFunction?.function;
    if (function is FuncRef) {
      return function.location?.script?.uri;
    }
    return null;
  }

  int? get sourceLine {
    final function = _profileFunction?.function;
    if (function is FuncRef) return function.location?.line;
    return null;
  }

  ProfileFunction? get _profileFunction {
    if (functionIndex == _kRootFunctionIndex) return null;
    final functions = cpuSamples.functions;
    if (functions == null || functionIndex < 0 || functionIndex >= functions.length) {
      return null;
    }
    return functions[functionIndex];
  }

  _CpuProfileTimelineTree _childForIndex(int index) {
    for (final child in children) {
      if (child.functionIndex == index) return child;
    }
    final child = _CpuProfileTimelineTree._(cpuSamples, index);
    children.add(child);
    return child;
  }
}
