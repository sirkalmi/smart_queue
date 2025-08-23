import '../smart_job.dart';

/// Storage for permanently failed (poison) jobs.
abstract class DeadLetterStore {
  /// Store [job] with optional failure [error] and [stackTrace].
  Future<void> put(SmartJob job, {Object? error, StackTrace? stackTrace});

  /// List DLQ jobs, optionally limited by [limit].
  Future<List<SmartJob>> list({int? limit});

  /// Remove a DLQ entry by id.
  Future<void> remove(String id);

  /// Clear all DLQ entries.
  Future<void> clear();
}

/// In-memory dead letter store (non-durable).
class MemoryDeadLetterStore implements DeadLetterStore {
  final List<SmartJob> _jobs = <SmartJob>[];

  @override
  Future<void> clear() async {
    _jobs.clear();
  }

  @override
  Future<List<SmartJob>> list({int? limit}) async {
    final List<SmartJob> copy = List<SmartJob>.from(_jobs);
    return limit == null ? copy : copy.take(limit).toList();
  }

  @override
  Future<void> put(
    SmartJob job, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    _jobs.removeWhere((SmartJob j) => j.id == job.id);
    _jobs.add(job);
  }

  @override
  Future<void> remove(String id) async {
    _jobs.removeWhere((SmartJob j) => j.id == id);
  }
}
