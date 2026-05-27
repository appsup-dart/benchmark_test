import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

typedef DartTestRunner = Future<int> Function(
  List<String> arguments, {
  Map<String, String>? environment,
});

Future<int> runBenchmarkCli(
  List<String> arguments, {
  DartTestRunner? runDartTest,
  void Function(String line) printStatus = _stderrWriteln,
  void Function(String line) printUsage = _stdoutWriteln,
  void Function(String line) printError = _stderrWriteln,
}) async {
  final parser = _createArgParser();
  final config = _parseArguments(parser, arguments);
  if (config.showHelp) {
    printUsage(_usage(parser));
    return 0;
  }

  if (config.error != null) {
    printError(config.error!);
    printError('');
    printError(_usage(parser));
    return 64;
  }

  final runner = runDartTest ?? _runDartTest;
  for (final compileType in config.compileTypes) {
    printStatus('Running benchmarks with ${compileType.label}...');

    final exitCode = await runner(
      [
        if (config.enableAsserts) _enableAssertsRunnerArgument,
        '--platform',
        'vm',
        '--compiler',
        compileType.testCompiler,
        ...config.paths,
        ...config.testRunnerArguments,
      ],
      environment: {
        'BENCHMARK_COMPILE_TYPE': compileType.label,
        if (config.outputFormat != null)
          'BENCHMARK_OUTPUT': config.outputFormat!,
      },
    );

    if (exitCode != 0) return exitCode;
  }

  return 0;
}

Future<int> _runDartTest(
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final invocation = _BenchmarkTestInvocation.parse(arguments);
  if (invocation.error != null) {
    stderr.writeln(invocation.error);
    return 64;
  }

  return _runBenchmarkTestInvocation(invocation, environment: environment);
}

ArgParser _createArgParser() {
  return ArgParser()
    ..addMultiOption(
      'compile',
      abbr: 'c',
      aliases: ['compiler'],
      help: 'Compile type to run. Repeat or comma-separate values.',
      valueHelp: 'type',
    )
    ..addOption(
      'output',
      abbr: 'o',
      aliases: ['format'],
      allowed: _benchmarkOutputFormats,
      allowedHelp: const {
        'human': 'Human-readable local development output.',
        'benchmarkjs': 'benchmark.js-compatible output.',
        'jsonl': 'One JSON object per benchmark result.',
      },
      help: 'Benchmark output format.',
      valueHelp: 'format',
    )
    ..addFlag(
      'enable-asserts',
      help: 'Run benchmark tests with Dart assertions enabled.',
      negatable: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this help.',
      negatable: false,
    );
}

_BenchmarkCliConfig _parseArguments(
  ArgParser parser,
  List<String> arguments,
) {
  final separatorIndex = arguments.indexOf('--');
  final cliArguments = separatorIndex == -1
      ? arguments
      : arguments.take(separatorIndex).toList(growable: false);
  final testRunnerArguments = separatorIndex == -1
      ? const <String>[]
      : arguments.skip(separatorIndex + 1).toList(growable: false);

  final ArgResults results;
  try {
    results = parser.parse(cliArguments);
  } on FormatException catch (error) {
    return _BenchmarkCliConfig.error(
      '${error.message}. Pass dart test options after `--`.',
    );
  }

  if (results.flag('help')) {
    return _BenchmarkCliConfig.help();
  }

  final compileTypes = <_BenchmarkCompileType>[];
  final error = _addCompileTypes(
    compileTypes,
    results.multiOption('compile'),
  );
  if (error != null) return _BenchmarkCliConfig.error(error);

  return _BenchmarkCliConfig(
    compileTypes: compileTypes.isEmpty
        ? _BenchmarkCompileType.values
        : List.unmodifiable(compileTypes),
    enableAsserts: results.flag('enable-asserts'),
    outputFormat: results.option('output'),
    paths: List.unmodifiable(results.rest),
    testRunnerArguments: testRunnerArguments,
  );
}

String? _addCompileTypes(
  List<_BenchmarkCompileType> compileTypes,
  List<String> rawValues,
) {
  for (final value in rawValues) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'Compile type cannot be empty.';
    }

    if (normalized == 'all') {
      for (final compileType in _BenchmarkCompileType.values) {
        if (!compileTypes.contains(compileType)) compileTypes.add(compileType);
      }
      continue;
    }

    final compileType = _BenchmarkCompileType.tryParse(normalized);
    if (compileType == null) {
      return 'Unsupported compile type `$value`. Supported values: jit, aot.';
    }

    if (!compileTypes.contains(compileType)) compileTypes.add(compileType);
  }

  return null;
}

const _benchmarkOutputFormats = ['human', 'benchmarkjs', 'jsonl'];
const _enableAssertsRunnerArgument = '--benchmark-test-enable-asserts';

Future<int> _runBenchmarkTestInvocation(
  _BenchmarkTestInvocation invocation, {
  Map<String, String>? environment,
}) async {
  try {
    final testFiles = _collectTestFiles(invocation.paths);
    final workDir = await Directory(
      '.dart_tool/benchmark_test',
    ).create(recursive: true);
    final runDir = await workDir.createTemp('run_');

    try {
      final bootstrap = File('${runDir.path}/benchmark_direct_runner.dart');
      await bootstrap.writeAsString(_benchmarkDirectRunnerSource(
        testFiles,
        invocation.nameFilter,
      ));

      if (invocation.compiler == 'exe') {
        final executable = File(
          '${runDir.path}/benchmark_direct_runner${Platform.isWindows ? '.exe' : ''}',
        );
        final compileExitCode = await _runProcess(
          Platform.resolvedExecutable,
          [
            'compile',
            'exe',
            if (invocation.enableAsserts) '--enable-asserts',
            bootstrap.path,
            '--output',
            executable.path,
          ],
          environment: environment,
        );
        if (compileExitCode != 0) return compileExitCode;

        return await _runProcess(
          executable.path,
          const [],
          environment: environment,
        );
      }

      return await _runProcess(
        Platform.resolvedExecutable,
        [
          if (invocation.enableAsserts) '--enable-asserts',
          bootstrap.path,
        ],
        environment: environment,
      );
    } finally {
      await runDir.delete(recursive: true);
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    return 64;
  } on FileSystemException catch (error) {
    stderr.writeln('${error.message}: ${error.path}');
    return 66;
  }
}

Future<int> _runProcess(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

List<File> _collectTestFiles(List<String> paths) {
  final roots = paths.isEmpty ? const ['test'] : paths;
  final files = <File>[];

  for (final path in roots) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.file) {
      files.add(File(path).absolute);
      continue;
    }

    if (type == FileSystemEntityType.directory) {
      final directory = Directory(path);
      final discovered = directory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('_test.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      files.addAll(discovered.map((file) => file.absolute));
      continue;
    }

    throw FileSystemException('Benchmark test path does not exist', path);
  }

  if (files.isEmpty) {
    throw const FormatException('No benchmark test files found.');
  }
  return List.unmodifiable(files);
}

String _benchmarkDirectRunnerSource(
  List<File> testFiles,
  _BenchmarkNameFilter? nameFilter,
) {
  final buffer = StringBuffer()
    ..writeln('// Generated by package:benchmark_test. Do not edit.')
    ..writeln("import 'dart:async';")
    ..writeln("import 'dart:io';")
    ..writeln()
    ..writeln("import 'package:test_api/backend.dart';")
    ..writeln(
      "import 'package:test_api/src/backend/declarer.dart'; // ignore: implementation_imports",
    )
    ..writeln(
      "import 'package:test_api/src/backend/group.dart'; // ignore: implementation_imports",
    )
    ..writeln(
      "import 'package:test_api/src/backend/invoker.dart'; // ignore: implementation_imports",
    )
    ..writeln(
      "import 'package:test_api/src/backend/test.dart'; // ignore: implementation_imports",
    )
    ..writeln(
      "import 'package:test_core/src/runner/engine.dart'; // ignore: implementation_imports",
    )
    ..writeln(
      "import 'package:test_core/src/runner/plugin/environment.dart'; // ignore: implementation_imports",
    )
    ..writeln(
      "import 'package:test_core/src/runner/reporter/expanded.dart'; // ignore: implementation_imports",
    )
    ..writeln(
      "import 'package:test_core/src/runner/runner_suite.dart'; // ignore: implementation_imports",
    )
    ..writeln(
      "import 'package:test_core/src/runner/suite.dart'; // ignore: implementation_imports",
    )
    ..writeln(
      "import 'package:test_core/src/util/os.dart'; // ignore: implementation_imports",
    )
    ..writeln(
      "import 'package:test_core/src/util/print_sink.dart'; // ignore: implementation_imports",
    )
    ..writeln();

  for (var i = 0; i < testFiles.length; i++) {
    buffer.writeln("import '${testFiles[i].absolute.uri}' as test_$i;");
  }

  buffer
    ..writeln()
    ..writeln('final RegExp? _namePattern = ${_namePatternSource(nameFilter)};')
    ..writeln('const String? _plainName = ${_plainNameSource(nameFilter)};')
    ..writeln()
    ..writeln('Future<void> main() async {')
    ..writeln('  final success = await _runBenchmarkTests(() async {');
  for (var i = 0; i < testFiles.length; i++) {
    buffer.writeln('    await Future.sync(test_$i.main);');
  }
  buffer
    ..writeln('  });')
    ..writeln('  if (!success) exitCode = 1;')
    ..writeln('}')
    ..writeln()
    ..writeln(
      'Future<bool> _runBenchmarkTests(FutureOr<void> Function() testMain) async {',
    )
    ..writeln('  final declarer = Declarer(allowDuplicateTestNames: true);')
    ..writeln('  await declarer.declare(testMain);')
    ..writeln('  var root = declarer.build();')
    ..writeln('  if (_namePattern != null || _plainName != null) {')
    ..writeln('    final filtered = root.filter(_matchesName);')
    ..writeln('    if (filtered == null) {')
    ..writeln("      stderr.writeln('No benchmark tests matched the filter.');")
    ..writeln('      return false;')
    ..writeln('    }')
    ..writeln('    root = filtered;')
    ..writeln('  }')
    ..writeln()
    ..writeln('  final suite = RunnerSuite(')
    ..writeln('    const PluginEnvironment(),')
    ..writeln('    SuiteConfiguration.empty,')
    ..writeln('    root,')
    ..writeln(
        '    SuitePlatform(Runtime.vm, compiler: null, os: currentOSGuess),')
    ..writeln("    path: Uri.base.toString(),")
    ..writeln('  );')
    ..writeln()
    ..writeln('  final engine = Engine()')
    ..writeln('    ..suiteSink.add(suite)')
    ..writeln('    ..suiteSink.close();')
    ..writeln('  ExpandedReporter.watch(')
    ..writeln('    engine,')
    ..writeln('    PrintSink(),')
    ..writeln('    color: true,')
    ..writeln('    printPath: false,')
    ..writeln('    printPlatform: false,')
    ..writeln('  );')
    ..writeln()
    ..writeln('  final success = await runZoned<Future<bool?>>(')
    ..writeln(
      '        () => Invoker.guard(engine.run) ?? Future<bool?>.value(false),',
    )
    ..writeln('        zoneValues: {#test.declarer: declarer},')
    ..writeln('      ) ??')
    ..writeln('      false;')
    ..writeln('  return success;')
    ..writeln('}')
    ..writeln()
    ..writeln('bool _matchesName(Test test) {')
    ..writeln('  final plainName = _plainName;')
    ..writeln('  if (plainName != null) return test.name == plainName;')
    ..writeln('  final namePattern = _namePattern;')
    ..writeln(
        '  if (namePattern != null) return namePattern.hasMatch(test.name);')
    ..writeln('  return true;')
    ..writeln('}');

  return buffer.toString();
}

String _namePatternSource(_BenchmarkNameFilter? nameFilter) {
  if (nameFilter is _BenchmarkPatternNameFilter) {
    return 'RegExp(${jsonEncode(nameFilter.pattern)})';
  }
  return 'null';
}

String _plainNameSource(_BenchmarkNameFilter? nameFilter) {
  if (nameFilter is _BenchmarkPlainNameFilter) {
    return jsonEncode(nameFilter.name);
  }
  return 'null';
}

class _BenchmarkTestInvocation {
  final String compiler;
  final bool enableAsserts;
  final List<String> paths;
  final _BenchmarkNameFilter? nameFilter;
  final String? error;

  _BenchmarkTestInvocation({
    required this.compiler,
    required this.enableAsserts,
    required this.paths,
    required this.nameFilter,
  }) : error = null;

  _BenchmarkTestInvocation.error(this.error)
      : compiler = 'kernel',
        enableAsserts = false,
        paths = const [],
        nameFilter = null;

  static _BenchmarkTestInvocation parse(List<String> arguments) {
    var enableAsserts = false;
    String? platform;
    String? compiler;
    final paths = <String>[];
    _BenchmarkNameFilter? nameFilter;

    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];

      String? readValue() {
        if (i + 1 == arguments.length) return null;
        return arguments[++i];
      }

      if (argument == _enableAssertsRunnerArgument) {
        enableAsserts = true;
      } else if (argument == '--platform') {
        platform = readValue();
        if (platform == null) {
          return _BenchmarkTestInvocation.error(
              'Expected a value after --platform.');
        }
      } else if (argument.startsWith('--platform=')) {
        platform = argument.substring('--platform='.length);
      } else if (argument == '--compiler') {
        compiler = readValue();
        if (compiler == null) {
          return _BenchmarkTestInvocation.error(
              'Expected a value after --compiler.');
        }
      } else if (argument.startsWith('--compiler=')) {
        compiler = argument.substring('--compiler='.length);
      } else if (argument == '-n' || argument == '--name') {
        final value = readValue();
        if (value == null) {
          return _BenchmarkTestInvocation.error(
              'Expected a value after $argument.');
        }
        nameFilter = _BenchmarkPatternNameFilter(value);
      } else if (argument.startsWith('--name=')) {
        nameFilter = _BenchmarkPatternNameFilter(
          argument.substring('--name='.length),
        );
      } else if (argument == '-N' || argument == '--plain-name') {
        final value = readValue();
        if (value == null) {
          return _BenchmarkTestInvocation.error(
              'Expected a value after $argument.');
        }
        nameFilter = _BenchmarkPlainNameFilter(value);
      } else if (argument.startsWith('--plain-name=')) {
        nameFilter = _BenchmarkPlainNameFilter(
          argument.substring('--plain-name='.length),
        );
      } else if (argument == '-r' || argument == '--reporter') {
        final value = readValue();
        if (value == null) {
          return _BenchmarkTestInvocation.error(
              'Expected a value after $argument.');
        }
        final error = _validateReporter(value);
        if (error != null) return _BenchmarkTestInvocation.error(error);
      } else if (argument.startsWith('--reporter=')) {
        final error =
            _validateReporter(argument.substring('--reporter='.length));
        if (error != null) return _BenchmarkTestInvocation.error(error);
      } else if (argument == '--color' || argument == '--no-color') {
        // The direct runner currently uses the expanded reporter. These flags
        // are accepted for compatibility with common `dart test` invocations.
      } else if (argument.startsWith('-')) {
        return _BenchmarkTestInvocation.error(
          'Unsupported dart test argument `$argument` for assert-free benchmarks.',
        );
      } else {
        paths.add(argument);
      }
    }

    if (platform != null && platform != 'vm') {
      return _BenchmarkTestInvocation.error(
        'Unsupported platform `$platform`. Only `vm` is supported.',
      );
    }

    compiler ??= 'kernel';
    if (compiler != 'kernel' && compiler != 'exe') {
      return _BenchmarkTestInvocation.error(
        'Unsupported compiler `$compiler`. Supported values: kernel, exe.',
      );
    }

    return _BenchmarkTestInvocation(
      compiler: compiler,
      enableAsserts: enableAsserts,
      paths: List.unmodifiable(paths),
      nameFilter: nameFilter,
    );
  }
}

String? _validateReporter(String value) {
  const supportedReporters = {'expanded'};
  if (supportedReporters.contains(value)) return null;
  return 'Unsupported reporter `$value` for assert-free benchmarks. '
      'Supported reporters: expanded.';
}

sealed class _BenchmarkNameFilter {}

class _BenchmarkPatternNameFilter extends _BenchmarkNameFilter {
  final String pattern;

  _BenchmarkPatternNameFilter(this.pattern);
}

class _BenchmarkPlainNameFilter extends _BenchmarkNameFilter {
  final String name;

  _BenchmarkPlainNameFilter(this.name);
}

enum _BenchmarkCompileType {
  jit('jit', 'kernel'),
  aot('aot', 'exe');

  const _BenchmarkCompileType(this.label, this.testCompiler);

  final String label;
  final String testCompiler;

  static _BenchmarkCompileType? tryParse(String value) {
    for (final compileType in values) {
      if (compileType.label == value) return compileType;
    }
    return null;
  }
}

class _BenchmarkCliConfig {
  final List<_BenchmarkCompileType> compileTypes;
  final bool enableAsserts;
  final String? outputFormat;
  final List<String> paths;
  final List<String> testRunnerArguments;
  final bool showHelp;
  final String? error;

  _BenchmarkCliConfig({
    required this.compileTypes,
    required this.enableAsserts,
    required this.outputFormat,
    required this.paths,
    required this.testRunnerArguments,
  })  : showHelp = false,
        error = null;

  _BenchmarkCliConfig.help()
      : compileTypes = const [],
        enableAsserts = false,
        outputFormat = null,
        paths = const [],
        testRunnerArguments = const [],
        showHelp = true,
        error = null;

  _BenchmarkCliConfig.error(this.error)
      : compileTypes = const [],
        enableAsserts = false,
        outputFormat = null,
        paths = const [],
        testRunnerArguments = const [],
        showHelp = false;
}

void _stdoutWriteln(String line) => stdout.writeln(line);

void _stderrWriteln(String line) => stderr.writeln(line);

String _usage(ArgParser parser) {
  return '''
Run benchmark tests for one or more Dart compile types.

Usage:
  dart run benchmark_test [options] [test-path ...] [-- <dart test args>]

Options:
${parser.usage}

Supported compile types: jit, aot. Default: jit,aot.
Default output format: human.

Examples:
  dart run benchmark_test test/benchmarks_test.dart
  dart run benchmark_test --compile jit -- -n parse
  dart run benchmark_test --output jsonl test/benchmarks_test.dart
  dart run benchmark_test --enable-asserts test/benchmarks_test.dart
  dart run benchmark_test -c jit,aot test/benchmarks_test.dart -- --reporter expanded
''';
}
