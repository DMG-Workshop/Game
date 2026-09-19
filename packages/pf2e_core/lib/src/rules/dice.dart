/// A seeded, deterministic dice roller.
///
/// Rolls must be reproducible: an asynchronous multiplayer turn is replayed
/// from a log, and every device that replays it has to arrive at the same
/// numbers. `dart:math`'s [Random] is unsuitable because its algorithm is not
/// a documented, stable contract across Dart versions or platforms.
///
/// This uses an explicit linear congruential generator so the sequence is
/// fixed forever by the seed. The constants are the well-known Numerical
/// Recipes pair, chosen here because the largest intermediate product stays
/// below 2^53:
///
///     (2^32 - 1) * 1664525 + 1013904223  ~=  7.15e15  <  9.01e15  ==  2^53
///
/// That bound is what keeps rolls identical between native builds, where Dart
/// integers are 64-bit, and the web build, where they are doubles with exact
/// integer behaviour only up to 2^53. A generator relying on 64-bit wraparound
/// would silently produce different results in a browser and break replay
/// between a phone and a PC.
class DiceRoller {
  /// Creates a roller from a seed. Seeds are reduced modulo 2^32.
  DiceRoller(int seed) : _state = seed % modulus;

  /// Resumes a roller from a previously captured [state].
  ///
  /// Persisting [state] alongside a turn log is what lets a session be
  /// suspended, synced, and continued without changing any future roll.
  DiceRoller.fromState(int state) : _state = state % modulus;

  /// LCG constants. These are part of the determinism contract: changing any
  /// of them changes every future roll for every existing seed, and must keep
  /// the worst-case product below 2^53 so the web build agrees with native.
  static const int multiplier = 1664525;
  static const int increment = 1013904223;
  static const int modulus = 0x100000000; // 2^32

  /// Largest die this roller supports, bounded by its 16-bit output window.
  static const int maxSides = 0x10000;

  int _state;

  /// The generator's current position, for snapshot and resume.
  int get state => _state;

  int _next() {
    _state = (_state * multiplier + increment) % modulus;
    return _state;
  }

  /// The high 16 bits of the next value.
  ///
  /// An LCG's low-order bits cycle with very short periods — the lowest bit
  /// alternates — so they are never used for a roll.
  int _next16() => _next() ~/ 0x10000;

  /// Rolls one die with [sides] faces, returning 1..[sides].
  ///
  /// Uses rejection sampling rather than a plain modulo, which would bias
  /// results toward low faces whenever the output range is not an exact
  /// multiple of [sides].
  int rollDie(int sides) {
    if (sides < 1) {
      throw ArgumentError.value(sides, 'sides', 'must be at least 1');
    }
    if (sides > maxSides) {
      throw ArgumentError.value(sides, 'sides', 'must be at most $maxSides');
    }
    final limit = maxSides - (maxSides % sides);
    int value;
    do {
      value = _next16();
    } while (value >= limit);
    return value % sides + 1;
  }

  /// Rolls [count] dice of [sides] faces and returns the individual results.
  List<int> rollDice(int count, int sides) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must not be negative');
    }
    return [for (var i = 0; i < count; i++) rollDie(sides)];
  }

  /// Rolls [count] dice of [sides] faces and returns their sum.
  int rollSum(int count, int sides) =>
      rollDice(count, sides).fold(0, (a, b) => a + b);

  /// Rolls a d20.
  int d20() => rollDie(20);
}
