import 'dart:convert';

/// Signature for a simple job handler that receives only the payload.
typedef JobHandler = Future<void> Function(Map<String, dynamic> payload);

/// Signature for a context-aware handler that can report progress.
typedef JobHandlerWithContext =
    Future<void> Function(Map<String, dynamic> payload, JobContext context);
typedef JobSuccessCallback = void Function(SmartJob job);
typedef JobFailureCallback =
    void Function(SmartJob job, Object error, StackTrace stackTrace);
typedef JobRetryCallback =
    void Function(SmartJob job, int attempt, Duration nextDelay);

/// A unit of work to be processed by [SmartQueue].
class SmartJob {
  SmartJob({
    required this.id,
    required this.type,
    Map<String, dynamic>? payload,
    this.maxRetries = 3,
    int? attempts,
    DateTime? createdAt,
    this.onSuccess,
    this.onFailure,
    this.onRetry,
    // Enterprise additions
    int? priority,
    this.scheduledAt,
    this.metadata,
  }) : payload = payload ?? <String, dynamic>{},
       attempts = attempts ?? 0,
       createdAt = createdAt ?? DateTime.now(),
       priority = priority ?? 0;

  /// Unique identifier for the job.
  final String id;

  /// Handler type to match against registered handlers.
  final String type;

  /// JSON-like map passed to the handler.
  final Map<String, dynamic> payload;

  /// Maximum number of retry attempts after the initial attempt.
  final int maxRetries;

  /// Number of attempts that have been made so far.
  int attempts;

  /// Creation timestamp.
  final DateTime createdAt;

  DateTime? lastRunAt;
  String? lastError;

  // Priority and scheduling
  /// Higher number runs earlier.
  int priority; // higher runs first
  /// Earliest time the job is eligible to run.
  DateTime? scheduledAt; // earliest time the job can run

  // Progress (not persisted)
  double? progress;

  // Arbitrary metadata (persisted)
  Map<String, dynamic>? metadata;

  // Transient callbacks, not persisted
  JobSuccessCallback? onSuccess;
  JobFailureCallback? onFailure;
  JobRetryCallback? onRetry;

  bool get hasRemainingRetries => attempts < (maxRetries + 1);

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'type': type,
      'payload': payload,
      'maxRetries': maxRetries,
      'attempts': attempts,
      'createdAt': createdAt.toIso8601String(),
      'lastRunAt': lastRunAt?.toIso8601String(),
      'lastError': lastError,
      'priority': priority,
      'scheduledAt': scheduledAt?.toIso8601String(),
      'metadata': metadata,
    };
  }

  String toJson() => jsonEncode(toMap());

  static SmartJob fromMap(Map<dynamic, dynamic> map) {
    return SmartJob(
        id: map['id'] as String,
        type: map['type'] as String,
        payload:
            (map['payload'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
        maxRetries: (map['maxRetries'] as int?) ?? 3,
        attempts: (map['attempts'] as int?) ?? 0,
        createdAt:
            DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
        priority: (map['priority'] as int?) ?? 0,
        scheduledAt: (map['scheduledAt'] is String)
            ? DateTime.tryParse(map['scheduledAt'] as String)
            : null,
        metadata: (map['metadata'] as Map?)?.cast<String, dynamic>(),
      )
      ..lastRunAt = (map['lastRunAt'] is String)
          ? DateTime.tryParse(map['lastRunAt'] as String)
          : null
      ..lastError = map['lastError'] as String?;
  }
}

// Lightweight job execution context for handlers with progress reporting
class JobContext {
  JobContext({required this.job, required void Function(double p) onProgress})
    : _onProgress = onProgress;

  final SmartJob job;
  final void Function(double) _onProgress;

  void reportProgress(double value) {
    if (value.isNaN) return;
    final double clamped = value.clamp(0.0, 1.0);
    _onProgress(clamped);
  }
}
