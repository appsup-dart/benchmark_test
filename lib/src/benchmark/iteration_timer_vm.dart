import 'dart:developer';

abstract interface class IterationTimer {
  void start();

  int elapsedMicroseconds();
}

final class VmIterationTimer implements IterationTimer {
  int _startMicros = 0;

  @override
  void start() => _startMicros = Timeline.now;

  @override
  int elapsedMicroseconds() => Timeline.now - _startMicros;
}

IterationTimer createIterationTimer() => VmIterationTimer();
