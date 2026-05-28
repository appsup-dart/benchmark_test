abstract interface class IterationTimer {
  void start();

  int elapsedMicroseconds();
}

final class WebIterationTimer implements IterationTimer {
  final Stopwatch _stopwatch = Stopwatch();

  @override
  void start() => _stopwatch
    ..reset()
    ..start();

  @override
  int elapsedMicroseconds() {
    _stopwatch.stop();
    return _stopwatch.elapsedMicroseconds;
  }
}

IterationTimer createIterationTimer() => WebIterationTimer();
