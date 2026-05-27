import 'dart:io';

/// Whether benchmarks should pause for CPU profiling.
///
/// Controlled by the `PROFILE_MODE` environment variable.
final bool isProfileMode = Platform.environment['PROFILE_MODE'] == 'true';
