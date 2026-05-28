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

/// Returns a copy of [snapshot] with runtime wrapper frames collapsed so flame
/// charts focus on benchmark-relevant stacks.
Map<String, dynamic> postProcessDevToolsSnapshot(
  Map<String, dynamic> snapshot, {
  String? benchmarkName,
}) {
  final copy = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  final cpuProfiler = copy['cpu-profiler'];
  if (cpuProfiler is! Map<String, dynamic>) return copy;

  final stackFrames = cpuProfiler['stackFrames'];
  final traceEvents = cpuProfiler['traceEvents'];
  if (stackFrames is! Map || traceEvents is! List) return copy;

  final sourceFrames = <String, Map<String, Object?>>{};
  for (final entry in stackFrames.entries) {
    sourceFrames[entry.key.toString()] = Map<String, Object?>.from(
      entry.value as Map,
    );
  }

  final filteredFrameIdsByLeaf = <String, List<String>>{};
  List<String> filteredChainForLeaf(String leafId) {
    return filteredFrameIdsByLeaf.putIfAbsent(leafId, () {
      final original = <String>[];
      final seen = <String>{};
      String? currentId = leafId;
      while (currentId != null &&
          currentId != _cpuProfileRootId &&
          seen.add(currentId)) {
        final frame = sourceFrames[currentId];
        if (frame == null) break;
        original.add(currentId);
        currentId = frame['parent'] as String?;
      }
      final filtered = original
          .where(
            (id) => !_isRuntimeWrapperFrameWithContext(
              sourceFrames,
              id,
            ),
          )
          .toList();
      if (filtered.isNotEmpty) return filtered;
      // If everything is runtime scaffolding, drop this sample from the
      // postprocessed output rather than reintroducing wrapper-heavy stacks.
      if (benchmarkName != null && benchmarkName.isNotEmpty) return <String>[];
      return original;
    });
  }

  final rebuiltFrames = <String, Map<String, Object?>>{};
  final internedByKey = <String, String>{};
  var nextFrameId = 1;
  String internFrame(String oldId, String parentId) {
    final frame = sourceFrames[oldId]!;
    final displayName = _postProcessedFrameName(
      frame,
      sourceFrames: sourceFrames,
      frameId: oldId,
      benchmarkName: benchmarkName,
    );
    final parentName = parentId == _cpuProfileRootId
        ? null
        : rebuiltFrames[parentId]?['name'] as String?;
    if (parentName == displayName) {
      return parentId;
    }
    final normalizedParent = parentId == _cpuProfileRootId ? '' : parentId;
    final key =
        '$displayName|${frame['packageUri']}|${frame['resolvedUrl']}|${frame['sourceLine']}|$normalizedParent';
    final existing = internedByKey[key];
    if (existing != null) return existing;
    final newId = 'pp-$nextFrameId';
    nextFrameId++;
    rebuiltFrames[newId] = {
      'name': displayName,
      'category': frame['category'],
      'resolvedUrl': frame['resolvedUrl'],
      'packageUri': frame['packageUri'],
      if (frame['sourceLine'] != null) 'sourceLine': frame['sourceLine'],
      if (normalizedParent.isNotEmpty) 'parent': normalizedParent,
    };
    internedByKey[key] = newId;
    return newId;
  }

  final rebuiltTraceEvents = <Map<String, Object?>>[];
  for (final event in traceEvents) {
    if (event is! Map) continue;
    final oldLeafId = event['sf']?.toString();
    if (oldLeafId == null || oldLeafId.isEmpty) continue;
    final chainLeafToRoot = _collapseConsecutiveEquivalentFrames(
      filteredChainForLeaf(oldLeafId),
      sourceFrames,
      benchmarkName: benchmarkName,
    );
    if (chainLeafToRoot.isEmpty) continue;
    var parentId = _cpuProfileRootId;
    for (final frameId in chainLeafToRoot.reversed) {
      parentId = internFrame(frameId, parentId);
    }
    rebuiltTraceEvents
        .add({...Map<String, Object?>.from(event), 'sf': parentId});
  }

  cpuProfiler['stackFrames'] = rebuiltFrames;
  cpuProfiler['traceEvents'] = rebuiltTraceEvents;
  cpuProfiler['sampleCount'] = rebuiltTraceEvents.length;
  return copy;
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

bool _isRuntimeWrapperFrame(Map<String, Object?> frame) {
  final name = (frame['name'] as String?) ?? '';
  final packageUri = (frame['packageUri'] as String?) ?? '';

  if (name == 'BenchmarkSampler.sample' ||
      name.startsWith('_rootRun') ||
      name.startsWith('_CustomZone.') ||
      name == '_runPendingImmediateCallback' ||
      name == '_RawReceivePort._handleMessage' ||
      name == '_Timer._handleMessage' ||
      name == '_Timer._runTimers' ||
      name == 'handleValueCallback' ||
      name.startsWith('_Future.')) {
    return true;
  }

  if (packageUri.startsWith('dart:async') &&
      (name == '<anonymous closure>' ||
          name.startsWith('_') ||
          name.contains('Zone') ||
          name.contains('Future'))) {
    return true;
  }

  return false;
}

bool _isRuntimeWrapperFrameWithContext(
  Map<String, Map<String, Object?>> sourceFrames,
  String frameId,
) {
  final frame = sourceFrames[frameId];
  if (frame == null) return true;

  final name = (frame['name'] as String?) ?? '';
  final parentId = frame['parent'] as String?;
  final parentName = parentId == null ? null : sourceFrames[parentId]?['name'];

  // Keep the benchmark body closure even when it comes from async internals.
  if (name == '<anonymous closure>' && parentName == 'BenchmarkSampler.sample') {
    return false;
  }
  return _isRuntimeWrapperFrame(frame);
}

String _postProcessedFrameName(
  Map<String, Object?> frame, {
  required Map<String, Map<String, Object?>> sourceFrames,
  required String frameId,
  required String? benchmarkName,
}) {
  final name = (frame['name'] as String?) ?? '<unknown>';
  if (benchmarkName == null || benchmarkName.isEmpty) return name;
  if (name != '<anonymous closure>') return name;
  final parentId = frame['parent'] as String?;
  final parentName = parentId == null ? null : sourceFrames[parentId]?['name'];
  if (parentName == 'BenchmarkSampler.sample') {
    return '<benchmark body: $benchmarkName>';
  }
  return name;
}

List<String> _collapseConsecutiveEquivalentFrames(
  List<String> frameIdsLeafToRoot,
  Map<String, Map<String, Object?>> sourceFrames, {
  required String? benchmarkName,
}) {
  final collapsed = <String>[];
  String? previousName;
  for (final frameId in frameIdsLeafToRoot) {
    final frame = sourceFrames[frameId];
    if (frame == null) continue;
    final name = _postProcessedFrameName(
      frame,
      sourceFrames: sourceFrames,
      frameId: frameId,
      benchmarkName: benchmarkName,
    );
    if (previousName == name) continue;
    collapsed.add(frameId);
    previousName = name;
  }
  return collapsed;
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

  String stackFrameId(String isolateId) =>
      frameId == _kRootFrameId ? _cpuProfileRootId : '$isolateId-$frameId';

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
    if (functions == null ||
        functionIndex < 0 ||
        functionIndex >= functions.length) {
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
