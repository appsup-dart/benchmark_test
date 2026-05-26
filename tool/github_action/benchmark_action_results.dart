import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  try {
    final inputs = parseBenchmarkInputs(arguments);
    final results = convertBenchmarkActionResults(inputs);
    stdout.writeln(JsonEncoder.withIndent('  ').convert(results));
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln('${error.message}: ${error.path}');
    exitCode = 66;
  }
}

List<BenchmarkInput> parseBenchmarkInputs(List<String> arguments) {
  if (arguments.isEmpty || arguments.contains('--help')) {
    throw FormatException(_usage);
  }

  final inputs = <BenchmarkInput>[];
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--input') {
      if (i + 1 == arguments.length) {
        throw FormatException('Expected a value after --input.');
      }
      inputs.add(BenchmarkInput.parse(arguments[++i]));
      continue;
    }

    if (argument.startsWith('--input=')) {
      inputs.add(BenchmarkInput.parse(argument.substring('--input='.length)));
      continue;
    }

    throw FormatException('Unknown argument `$argument`.\n\n$_usage');
  }

  if (inputs.isEmpty) {
    throw FormatException('At least one --input value is required.');
  }
  return inputs;
}

List<Map<String, Object>> convertBenchmarkActionResults(
  Iterable<BenchmarkInput> inputs,
) {
  final results = <Map<String, Object>>[];

  for (final input in inputs) {
    for (final line in input.file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('{')) continue;

      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, Object?>) {
        throw FormatException(
          'Expected benchmark JSON objects in ${input.file.path}.',
        );
      }

      final result = _convertBenchmarkResult(input.compileType, decoded);
      if (result != null) results.add(result);
    }
  }

  if (results.isEmpty) {
    throw FormatException('No benchmark results found.');
  }
  return results;
}

Map<String, Object>? _convertBenchmarkResult(
  String compileType,
  Map<String, Object?> result,
) {
  final name = result['name'];
  final throughput = result['throughput'];
  if (name is! String || throughput is! Map) return null;

  final value = throughput['value'];
  final unit = throughput['unit'];
  if (value is! num || unit is! String) return null;

  final converted = <String, Object>{
    'name': '$name [$compileType]',
    'unit': unit,
    'value': value,
  };

  final range = _formatRange(result['statistics']);
  if (range != null) converted['range'] = range;

  final extra = _formatExtra(compileType, result);
  if (extra.isNotEmpty) converted['extra'] = extra;

  return converted;
}

String? _formatRange(Object? statistics) {
  if (statistics is! Map) return null;

  final relativeMarginOfError = statistics['relativeMarginOfError'];
  if (relativeMarginOfError is! num) return null;

  return '±${relativeMarginOfError.toStringAsFixed(2)}%';
}

String _formatExtra(String compileType, Map<String, Object?> result) {
  final lines = ['compile: $compileType'];

  final statistics = result['statistics'];
  if (statistics is Map) {
    final samples = statistics['samples'];
    if (samples is num) lines.add('samples: ${samples.toInt()}');
  }

  final latency = result['latency'];
  if (latency is Map) {
    final mean = latency['mean'];
    final unit = latency['unit'];
    if (mean is num && unit is String) {
      lines.add('mean latency: ${_formatNumber(mean)} $unit');
    }
  }

  return lines.join('\n');
}

String _formatNumber(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

class BenchmarkInput {
  final String compileType;
  final File file;

  BenchmarkInput(this.compileType, this.file);

  factory BenchmarkInput.parse(String value) {
    final separator = value.indexOf(':');
    if (separator == -1) {
      throw FormatException(
        'Expected --input values in the form <compile-type>:<jsonl-path>.',
      );
    }

    final compileType = value.substring(0, separator).trim();
    final path = value.substring(separator + 1).trim();
    if (compileType.isEmpty || path.isEmpty) {
      throw FormatException(
        'Expected --input values in the form <compile-type>:<jsonl-path>.',
      );
    }

    return BenchmarkInput(compileType, File(path));
  }
}

const _usage = '''
Usage:
  dart tool/github_action/benchmark_action_results.dart \\
    --input jit:path/to/jit.jsonl \\
    --input aot:path/to/aot.jsonl
''';
