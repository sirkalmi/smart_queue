import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:collection/collection.dart';

import 'dlq/dead_letter_store.dart';
import 'events/queue_events.dart';
import 'retry_strategy.dart';
import 'smart_job.dart';
import 'storage/queue_store.dart';

/// Runtime configuration for [SmartQueue]. Controls concurrency, retries,
/// persistence cadence, and multi-instance execution leases.
class SmartQueueConfig {
  /// Create a new [SmartQueueConfig].
  const SmartQueueConfig({
    this.concurrency = 1,
    this.retryStrategy = const FixedRetryStrategy(Duration(seconds: 1)),
    this.maxQueueSize,
    this.persistInterval = const Duration(seconds: 2),
    this.leaseTtl = const Duration(seconds: 30),
    this.ownerId,
  }) : assert(concurrency > 0, 'concurrency must be >= 1');

  /// Maximum number of jobs processed in parallel.
  final int concurrency;

  /// Backoff policy used when a job throws.
  final RetryStrategy retryStrategy;

  /// Optional hard cap for queued + inflight jobs.
  final int? maxQueueSize;

  /// Interval to persist in-memory queue state to the store.
  final Duration persistInterval;

  /// Time-to-live for execution lease to coordinate multiple workers.
  final Duration leaseTtl;

  /// Optional stable identifier of this worker/instance.
  final String? ownerId;
}

/// A lightweight, persistent job queue with retries, priorities and events.
class SmartQueue {
  /// Construct a [SmartQueue] using a [QueueStore] backend.
  SmartQueue({
    required QueueStore store,
    SmartQueueConfig config = const SmartQueueConfig(),
    Map<String, JobHandler>? handlers,
    DeadLetterStore? deadLetterStore,
  }) : _store = store,
       _config = config,
       _ownerId = config.ownerId ?? _generateOwnerId(),
       _dlq = deadLetterStore {
    if (handlers != null) {
      _handlers.addAll(handlers);
    }
  }

  static String _generateOwnerId() =>
      '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';

  final QueueStore _store;
  final SmartQueueConfig _config;

  final Map<String, JobHandler> _handlers = <String, JobHandler>{};
  final Map<String, JobHandlerWithContext> _ctxHandlers =
      <String, JobHandlerWithContext>{};
  final Queue<SmartJob> _pending = Queue<SmartJob>();
  final Map<String, SmartJob> _inFlight = <String, SmartJob>{};
  final Set<String> _executingJobIds = {};

  final String _ownerId;
  final DeadLetterStore? _dlq;

  final StreamController<QueueEvent> _events =
      StreamController<QueueEvent>.broadcast();

  /// Stream of lifecycle events for observability and UI.
  Stream<QueueEvent> get events => _events.stream;

  Timer? _persistTimer;
  bool _started = false;
  bool _disposed = false;

  Completer<void>? _processingDoneCompleter;

  /// True if the queue has started and is not disposed.
  bool get isRunning => _started && !_disposed;

  /// Register a simple handler for jobs of [type].
  void registerHandler(String type, JobHandler handler) {
    _handlers[type] = handler;
  }

  /// Register a context-aware handler for jobs of [type].
  void registerHandlerWithContext(String type, JobHandlerWithContext handler) {
    _ctxHandlers[type] = handler;
  }

  /// Load persisted jobs and begin processing according to config.
  Future<void> start({Completer<void>? processingDoneCompleter}) async {
    _processingDoneCompleter = processingDoneCompleter;
    if (_started) {
      _tryComplete();
      return;
    }
    _started = true;
    // Load persisted jobs
    final List<SmartJob> jobs = await _store.loadJobs();
    jobs.sortBy((SmartJob j) => j.createdAt);
    _pending.addAll(jobs);
    _tryComplete();

    // Kick off periodic persistence of in-memory queue state
    _persistTimer = Timer.periodic(_config.persistInterval, (_) async {
      await _persistAll();
    });

    _scheduleWork();
  }

  /// Stop timers and mark the queue as disposed.
  Future<void> dispose() async {
    _disposed = true;
    _persistTimer?.cancel();
    // No explicit close for store; user manages underlying resources
  }

  /// Enqueue [job], persist it, and schedule work.
  Future<void> add(SmartJob job) async {
    if (_config.maxQueueSize != null &&
        (_pending.length + _inFlight.length) >= _config.maxQueueSize!) {
      throw StateError('Queue is full (max ${_config.maxQueueSize})');
    }
    _pending.add(job);
    await _store.putJob(job);
    _events.add(JobEnqueued(job));
    _scheduleWork();
  }

  /// Total number of jobs (queued + inflight).
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
    // Run as many as allowed by concurrency with basic scheduling
    while (_inFlight.length < _config.concurrency && _pending.isNotEmpty) {
      final SmartJob? next = _selectNextJob();
      if (next == null) break;
      // Start immediately so _inFlight updates before next iteration
      _runJob(next);
    }
  }

  SmartJob? _selectNextJob() {
    if (_pending.isEmpty) return null;
    final DateTime now = DateTime.now();
    final Iterable<SmartJob> runnable = _pending.where(
      (SmartJob j) => j.scheduledAt == null || !j.scheduledAt!.isAfter(now),
    );
    if (runnable.isEmpty) return null;
    SmartJob? best;
    for (final SmartJob j in runnable) {
      if (best == null || j.priority > best.priority) {
        best = j;
      }
    }
    if (best == null) return null;
    _pending.remove(best);
    return best;
  }

  Future<void> _runJob(SmartJob job) async {
    if (_disposed || _isExecutingJob(job.id)) return;

    _executingJobIds.add(job.id);

    final bool hasSimple = _handlers.containsKey(job.type);
    final bool hasCtx = _ctxHandlers.containsKey(job.type);
    if (!hasSimple && !hasCtx) {
      // No handler: treat as failure without retries
      job.lastError = 'No handler for type ${job.type}';
      await _store.removeJob(job.id);
      _inFlight.remove(job.id);
      _executingJobIds.remove(job.id);
      job.onFailure?.call(job, StateError(job.lastError!), StackTrace.current);
      _scheduleWork();
      _tryComplete();
      return;
    }

    _inFlight[job.id] = job;
    job.lastRunAt = DateTime.now();

    try {
      // Acquire lease for multi-instance safety
      final bool leased = await _store.tryAcquireLease(
        job.id,
        _ownerId,
        _config.leaseTtl,
      );
      if (!leased) {
        _inFlight.remove(job.id);
        // Put at tail to avoid tight retry loop under contention
        _pending.add(job);
        _scheduleWork();
        return;
      }

      _executingJobIds.add(job.id);

      final JobHandler? handler = _handlers[job.type];
      final JobHandlerWithContext? ctx = _ctxHandlers[job.type];
      if (ctx != null) {
        final JobContext ctxObj = JobContext(
          job: job,
          onProgress: (double p) {
            job.progress = p;
            _events.add(JobProgress(job, p));
          },
        );
        await ctx(job.payload, ctxObj);
      } else if (handler != null) {
        await handler(job.payload);
      }
      await _store.removeJob(job.id);
      _inFlight.remove(job.id);
      await _store.releaseLease(job.id, _ownerId);
      _events.add(JobSucceeded(job));
      job.onSuccess?.call(job);
    } catch (err, st) {
      job.attempts += 1;
      job.lastError = err.toString();

      if (job.attempts <= job.maxRetries) {
        final Duration delay = _config.retryStrategy.nextDelay(job.attempts);
        job.onRetry?.call(job, job.attempts, delay);
        _events.add(JobRetryScheduled(job, job.attempts, delay));
        // Re-enqueue with delay
        Timer(delay, () async {
          if (_disposed) return;
          _inFlight.remove(job.id);
          _pending.addLast(job);
          await _store.putJob(job);
          // Immediately attempt to run next available job (prevents idle at concurrency=1)
          _scheduleWork();
        });
      } else {
        // Exhausted
        await _store.removeJob(job.id);
        _inFlight.remove(job.id);
        await _store.releaseLease(job.id, _ownerId);
        if (_dlq != null) {
          await _dlq.put(job, error: err, stackTrace: st);
          _events.add(JobDeadLettered(job, err, st));
        } else {
          _events.add(JobFailed(job, err, st));
        }
        job.onFailure?.call(job, err, st);
      }
    } finally {
      _executingJobIds.remove(job.id);
      // If success path did not schedule more, schedule now
      _scheduleWork();
      _tryComplete();
    }
  }

  Future<void> forceRetry(String jobId) async {
    if (!_started || _disposed || _isExecutingJob(jobId)) return;
    final SmartJob? job =
        _inFlight[jobId] ?? _pending.firstWhereOrNull((e) => e.id == jobId);
    if (job != null) {
      _pending.remove(job);
      await _runJob(job);
    }
  }
  
  bool _isExecutingJob(String jobId) {
    return _executingJobIds.contains(jobId);
  }

  void _tryComplete() {
    if (_processingDoneCompleter != null &&
        !_processingDoneCompleter!.isCompleted &&
        _inFlight.isEmpty && _pending.isEmpty) {
      _processingDoneCompleter!.complete();
    }
  }
}
