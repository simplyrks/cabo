/// Converts a moment on this device into the same moment on the server's clock.
/// Device clocks can't be compared directly, so this measures the gap to the
/// server, trusting the fastest round trips because their timing is the most exact.
class ServerClock {
  static const _maxSamples = 8;

  final _watch = Stopwatch()..start();
  final List<({int roundTripUs, int offsetUs})> _samples = [];

  int get localNowUs => _watch.elapsedMicroseconds;

  void addSample(int sentAtUs, int serverAtUs) {
    final receivedAtUs = localNowUs;
    _samples.add((
      roundTripUs: receivedAtUs - sentAtUs,
      offsetUs: serverAtUs - (sentAtUs + receivedAtUs) ~/ 2,
    ));
    if (_samples.length > _maxSamples) _samples.removeAt(0);
  }

  /// Null until the gap has been measured.
  int? toServerUs(int localUs) {
    if (_samples.isEmpty) return null;
    final best = _samples.reduce(
        (a, b) => b.roundTripUs < a.roundTripUs ? b : a);
    return localUs + best.offsetUs;
  }

  void reset() => _samples.clear();
}
