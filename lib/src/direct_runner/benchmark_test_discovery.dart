import 'dart:io';

class BenchmarkTestDiscovery {
  const BenchmarkTestDiscovery();

  List<File> collect(List<String> paths) {
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
}
