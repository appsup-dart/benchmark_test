import 'dart:async';

import 'package:test/test.dart';

final _setUpsEach = <FutureOr<void> Function()>[];
final _tearDownsEach = <FutureOr<void> Function()>[];

/// Registers a function to be run before each iteration of a benchmark test.
///
/// If this is called within a test group, it applies only to benchmark tests
/// within that group.
void setUpEach(FutureOr<void> Function() callback) {
  setUp(() {
    _setUpsEach.add(callback);
  });
  tearDown(() => _setUpsEach.clear());
}

/// Registers a function to be run after each iteration of a benchmark test.
///
/// If this is called within a test group, it applies only to benchmark tests
/// within that group.
void tearDownEach(FutureOr<void> Function() callback) {
  setUp(() {
    _tearDownsEach.add(callback);
  });
  tearDown(() => _tearDownsEach.clear());
}

List<FutureOr<void> Function()> get benchmarkSetUpsEach => _setUpsEach;

List<FutureOr<void> Function()> get benchmarkTearDownsEach => _tearDownsEach;
