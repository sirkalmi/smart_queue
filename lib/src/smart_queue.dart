import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:collection/collection.dart';

import 'retry_strategy.dart';
import 'smart_job.dart';
import 'storage/queue_store.dart';

class SmartQueueConfig {
  const SmartQueueConfig({
    this.concurrency = 1,
    this.retryStrategy = const FixedRetryStrategy(Duration(seconds: 1)),
    this.maxQueueSize,
    this.persistInterval = const Duration(seconds: 2),
  }) : assert(concurrency > 0, 'concurrency must be >= 1');

  final int concurrency;
  final RetryStrategy retryStrategy;
  final int? maxQueueSize;
  final Duration persistInterval;
}

class SmartQueue {
  SmartQueue({
    required QueueStore store,
    SmartQueueConfig config = const SmartQueueConfig(),
    Map<String, JobHandler>? handlers,
  })  : _store = store,
        _config = config {
    if (handlers != null) {
      _handlers.addAll(handlers);
    }
  }

  final QueueStore _store;
  final SmartQueueConfig _config;

  final Map<String, JobHandler> _handlers = <String, JobHandler>{};
  final Queue<SmartJob> _pending = Queue<SmartJob>();
  final Map<String, SmartJob> _inFlight = <String, SmartJob>{};

  Timer? _persistTimer;
  bool _started = false;
  bool _disposed = false;

  bool get isRunning => _started && !_disposed;

  void registerHandler(String type, JobHandler handler) {
    _handlers[type] = handler;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    // Load persisted jobs
    final List<SmartJob> jobs = await _store.loadJobs();
    jobs.sortBy((SmartJob j) => j.createdAt);
    _pending.addAll(jobs);

    // Kick off periodic persistence of in-memory queue state
    _persistTimer = Timer.periodic(_config.persistInterval, (_) async {
      await _persistAll();
    });

    _scheduleWork();
  }

  Future<void> dispose() async {
    _disposed = true;
    _persistTimer?.cancel();
    // No explicit close for store; user manages underlying resources
  }

  Future<void> add(SmartJob job) async {
    if (_config.maxQueueSize != null &&
        (_pending.length + _inFlight.length) >= _config.maxQueueSize!) {
      throw StateError('Queue is full (max ${_config.maxQueueSize})');
    }
    _pending.add(job);
    await _store.putJob(job);
    _scheduleWork();
  }

  int get length => _pending.length + _inFlight.length;

  Future<void> _persistAll() async {
    // Persist current snapshot of pending + inflight jobs
    final List<SmartJob> snapshot = <SmartJob>[
      ..._pending,
      ..._inFlight.values,
    ];
    for (final SmartJob job in snapshot) {
      await _store.putJob(job);
    }
  }

  void _scheduleWork() {
    if (!_started || _disposed) return;
    // Run as many as allowed by concurrency
    while (_inFlight.length < _config.concurrency && _pending.isNotEmpty) {
      final SmartJob job = _pending.removeFirst();
      _runJob(job);
    }
  }

  Future<void> _runJob(SmartJob job) async {
    if (_disposed) return;
    if (!_handlers.containsKey(job.type)) {
      // No handler: treat as failure without retries
      job.lastError = 'No handler for type ${job.type}';
      await _store.removeJob(job.id);
      job.onFailure?.call(job, StateError(job.lastError!), StackTrace.current);
      _scheduleWork();
      return;
    }

    _inFlight[job.id] = job;
    job.lastRunAt = DateTime.now();

    try {
      final JobHandler handler = _handlers[job.type]!;
      await handler(job.payload);
      await _store.removeJob(job.id);
      _inFlight.remove(job.id);
      job.onSuccess?.call(job);
    } catch (err, st) {
      job.attempts += 1;
      job.lastError = err.toString();

      if (job.attempts <= job.maxRetries) {
        final Duration delay = _config.retryStrategy.nextDelay(job.attempts);
        job.onRetry?.call(job, job.attempts, delay);
        // Re-enqueue with delay
        Timer(delay, () async {
          if (_disposed) return;
          _inFlight.remove(job.id);
          _pending.addFirst(job);
          await _store.putJob(job);
          _scheduleWork();
        });
      } else {
        // Exhausted
        await _store.removeJob(job.id);
        _inFlight.remove(job.id);
        job.onFailure?.call(job, err, st);
      }
    } finally {
      // If success path did not schedule more, schedule now
      _scheduleWork();
    }
  }
}
