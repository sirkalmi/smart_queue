import 'dart:math';

abstract class RetryStrategy {
  const RetryStrategy();

  /// Return the delay before the next retry for this [attempt].
  /// Attempts are 1-based (1 = first retry after initial failure).
  Duration nextDelay(int attempt);

  factory RetryStrategy.fixed(Duration delay) => FixedRetryStrategy(delay);

  factory RetryStrategy.exponential({
    Duration initialDelay = const Duration(milliseconds: 500),
    double multiplier = 2.0,
    Duration maxDelay = const Duration(minutes: 5),
  }) => ExponentialRetryStrategy(
    initialDelay: initialDelay,
    multiplier: multiplier,
    maxDelay: maxDelay,
  );

  factory RetryStrategy.exponentialWithJitter({
    Duration initialDelay = const Duration(milliseconds: 500),
    double multiplier = 2.0,
    Duration maxDelay = const Duration(minutes: 5),
  }) => JitterRetryStrategy(
    ExponentialRetryStrategy(
      initialDelay: initialDelay,
      multiplier: multiplier,
      maxDelay: maxDelay,
    ),
  );
}

class FixedRetryStrategy extends RetryStrategy {
  const FixedRetryStrategy(this.delay);
  final Duration delay;

  @override
  Duration nextDelay(int attempt) => delay;
}

class ExponentialRetryStrategy extends RetryStrategy {
  const ExponentialRetryStrategy({
    required this.initialDelay,
    required this.multiplier,
    required this.maxDelay,
  });

  final Duration initialDelay;
  final double multiplier;
  final Duration maxDelay;

  @override
  Duration nextDelay(int attempt) {
    final double factor = pow(
      multiplier,
      (attempt - 1).clamp(0, 30),
    ).toDouble();
    final int millis = (initialDelay.inMilliseconds * factor).toInt();
    return Duration(milliseconds: min(millis, maxDelay.inMilliseconds));
  }
}

class JitterRetryStrategy extends RetryStrategy {
  const JitterRetryStrategy(this.inner);
  final RetryStrategy inner;

  @override
  Duration nextDelay(int attempt) {
    final Duration base = inner.nextDelay(attempt);
    if (base.inMilliseconds <= 1) return base;
    final int jitterMillis = Random().nextInt(base.inMilliseconds);
    return Duration(milliseconds: jitterMillis);
  }
}
