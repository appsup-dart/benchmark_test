import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'cpu_samples_devtools_export.dart';

/// Connects to a benchmark VM, records CPU samples between profile pauses, and
/// writes them to [outputDirectory].
class BenchmarkVmProfileSession {
  BenchmarkVmProfileSession({
    required this.serviceInfoFile,
    required this.outputDirectory,
    this.printStatus = _noop,
    this.launchDevTools = false,
  });

  final File serviceInfoFile;
  final Directory outputDirectory;
  final void Function(String line) printStatus;
  final bool launchDevTools;

  static final _profilingLine = RegExp(r'^Profiling: (.+)$');

  VmService? _service;
  String? _vmServiceHttpUri;
  String? _recordingIsolateId;
  int? _recordingStartMicros;
  String? _currentBenchmarkName;
  var _profileIndex = 0;
  var _handlingPause = false;

  Future<void> connect() async {
    await outputDirectory.create(recursive: true);

    final uri = await _waitForVmServiceUri(serviceInfoFile);
    _vmServiceHttpUri = uri;
    final wsUri = _toWebSocketUri(uri);
    printStatus('VM service available at $uri');

    _service = await vmServiceConnectUri(wsUri);
    await Future.wait([
      _service!.streamListen(EventStreams.kDebug),
      _service!.streamListen(EventStreams.kIsolate),
    ]);
    _service!.onDebugEvent.listen(_onDebugEvent);
    _service!.onIsolateEvent.listen((event) async {
      final isolateId = event.isolate?.id;
      if (isolateId == null) return;
      if (event.kind == EventKind.kIsolateStart ||
          event.kind == EventKind.kIsolateRunnable) {
        await _synchronizeIsolate(isolateId);
      }
    });

    await _enableProfiler();
    if (launchDevTools) {
      unawaited(_launchDevTools(uri));
    }
  }

  /// Resumes isolates that paused before the debug stream was listened to.
  Future<void> synchronizePausedIsolates() async {
    final vm = await _service!.getVM();
    for (final isolateRef in vm.isolates ?? const <IsolateRef>[]) {
      final isolateId = isolateRef.id;
      if (isolateId != null) {
        await _synchronizeIsolate(isolateId);
      }
    }
  }

  Future<void> _onDebugEvent(Event event) async {
    final isolateId = event.isolate?.id;
    if (isolateId == null) return;

    if (event.kind == EventKind.kPauseBreakpoint) {
      await _handleBreakpointPause(isolateId);
      return;
    }

    if (event.kind == EventKind.kPauseStart) {
      await _resumeIfNotRecording(isolateId);
    }
  }

  Future<void> _synchronizeIsolate(String isolateId) async {
    Isolate isolate;
    try {
      isolate = await _service!.getIsolate(isolateId);
    } on RPCError {
      return;
    }

    final pause = isolate.pauseEvent;
    final kind = pause?.kind;
    if (kind == null) return;

    if (kind == EventKind.kPauseBreakpoint) {
      await _handleBreakpointPause(isolateId);
    } else if (kind == EventKind.kPauseStart) {
      await _resumeIfNotRecording(isolateId);
    }
  }

  Future<void> _handleBreakpointPause(String isolateId) async {
    while (_handlingPause) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _handlingPause = true;
    try {
      if (_recordingIsolateId == null) {
        await _startRecording(isolateId);
      } else if (_recordingIsolateId == isolateId) {
        await _stopRecording(isolateId);
      }
      await _service!.resume(isolateId);
    } on RPCError catch (error) {
      printStatus('VM service error while profiling: ${error.message}');
      try {
        await _service!.resume(isolateId);
      } on RPCError {
        // Best-effort resume so the benchmark VM does not hang.
      }
    } finally {
      _handlingPause = false;
    }
  }

  Future<void> _resumeIfNotRecording(String isolateId) async {
    if (_recordingIsolateId == isolateId) return;
    try {
      await _service!.resume(isolateId);
    } on RPCError {
      // Isolate may have already resumed.
    }
  }

  Future<void> _startRecording(String isolateId) async {
    await _service!.clearCpuSamples(isolateId);
    _recordingStartMicros =
        (await _service!.getVMTimelineMicros()).timestamp ?? 0;
    _recordingIsolateId = isolateId;
    final name = _currentBenchmarkName ?? 'benchmark';
    printStatus('Recording CPU profile for $name...');
  }

  Future<void> _stopRecording(String isolateId) async {
    final startMicros = _recordingStartMicros;
    if (startMicros == null) return;

    final endMicros =
        (await _service!.getVMTimelineMicros()).timestamp ?? startMicros;
    final extentMicros = endMicros - startMicros;
    if (extentMicros <= 0) {
      printStatus('Skipped empty CPU profile window.');
      return;
    }

    final samples = await _service!.getCpuSamples(
      isolateId,
      startMicros,
      extentMicros,
    );

    final name = _sanitizeFileName(_currentBenchmarkName ?? 'benchmark');
    _profileIndex++;
    final baseName =
        '${outputDirectory.path}/${_profileIndex.toString().padLeft(3, '0')}_$name';

    final cpuFile = File('$baseName.cpu.json');
    await cpuFile.writeAsString(jsonEncode(samples.toJson()));
    printStatus('Wrote CPU profile to ${cpuFile.path}');

    final devtoolsFile = File('$baseName.devtools.json');
    final devtoolsSnapshot = await convertCpuSamplesToDevToolsSnapshot(
      samples,
      isolateId,
      vmService: _service,
    );
    await devtoolsFile.writeAsString(jsonEncode(devtoolsSnapshot));
    printStatus(
      'Wrote DevTools profile to ${devtoolsFile.path} (import in CPU Profiler)',
    );

    _recordingIsolateId = null;
    _recordingStartMicros = null;
  }

  Future<void> _enableProfiler() async {
    try {
      await _service!.setFlag('profiler', 'true');
    } on RPCError catch (error) {
      printStatus('Could not enable VM profiler: ${error.message}');
    }
  }

  Future<void> _launchDevTools(String httpUri) async {
    try {
      await Process.start(
        Platform.resolvedExecutable,
        ['devtools', httpUri, '--launch-browser'],
        mode: ProcessStartMode.detached,
      );
    } on Object catch (error) {
      printStatus('Could not launch DevTools: $error');
    }
  }

  void trackStdoutLine(String line) {
    final match = _profilingLine.firstMatch(line);
    if (match != null) {
      _currentBenchmarkName = match.group(1);
    }
  }

  Future<void> dispose() async {
    await _service?.dispose();
    _service = null;
  }

  String? get vmServiceHttpUri => _vmServiceHttpUri;
}

Future<String> _waitForVmServiceUri(
  File serviceInfoFile, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (serviceInfoFile.existsSync()) {
      final json =
          jsonDecode(serviceInfoFile.readAsStringSync()) as Map<String, dynamic>;
      final uri = json['uri'];
      if (uri is String && uri.isNotEmpty) {
        return uri;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(
    'Timed out waiting for VM service info at ${serviceInfoFile.path}.',
  );
}

String _toWebSocketUri(String httpUri) {
  final uri = Uri.parse(httpUri);
  final path = uri.path.endsWith('/')
      ? '${uri.path}ws'
      : '${uri.path}/ws';
  return uri.replace(scheme: 'ws', path: path).toString();
}

String _sanitizeFileName(String name) {
  return name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

void _noop(String _) {}
