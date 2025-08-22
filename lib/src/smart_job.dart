import 'dart:convert';

typedef JobHandler = Future<void> Function(Map<String, dynamic> payload);
typedef JobSuccessCallback = void Function(SmartJob job);
typedef JobFailureCallback = void Function(
  SmartJob job,
  Object error,
  StackTrace stackTrace,
);
typedef JobRetryCallback = void Function(
  SmartJob job,
  int attempt,
  Duration nextDelay,
);

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
  })  : payload = payload ?? <String, dynamic>{},
        attempts = attempts ?? 0,
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final String type;
  final Map<String, dynamic> payload;

  /// Maximum number of retry attempts after the initial attempt.
  final int maxRetries;

  /// Number of attempts that have been made so far.
  int attempts;

  final DateTime createdAt;

  DateTime? lastRunAt;
  String? lastError;

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
    };
  }

  String toJson() => jsonEncode(toMap());

  static SmartJob fromMap(Map<dynamic, dynamic> map) {
    return SmartJob(
      id: map['id'] as String,
      type: map['type'] as String,
      payload: (map['payload'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      maxRetries: (map['maxRetries'] as int?) ?? 3,
      attempts: (map['attempts'] as int?) ?? 0,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
    )
      ..lastRunAt = (map['lastRunAt'] is String)
          ? DateTime.tryParse(map['lastRunAt'] as String)
          : null
      ..lastError = map['lastError'] as String?;
  }
}
