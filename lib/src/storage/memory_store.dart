import '../smart_job.dart';
import 'queue_store.dart';

class MemoryStore implements QueueStore {
  MemoryStore([List<SmartJob>? seed])
    : _jobs = List<SmartJob>.from(seed ?? const <SmartJob>[]);

  final List<SmartJob> _jobs;

  @override
  Future<void> clear() async {
    _jobs.clear();
  }

  @override
  Future<List<SmartJob>> loadJobs() async {
    return List<SmartJob>.from(_jobs);
  }

  @override
  Future<void> putJob(SmartJob job) async {
    final int index = _jobs.indexWhere((SmartJob j) => j.id == job.id);
    if (index >= 0) {
      _jobs[index] = job;
    } else {
      _jobs.add(job);
    }
  }

  @override
  Future<void> removeJob(String id) async {
    _jobs.removeWhere((SmartJob j) => j.id == id);
  }

  @override
  Future<SmartJob?> getJob(String id) async {
    final int index = _jobs.indexWhere((SmartJob j) => j.id == id);
    if (index < 0) {
      return null;
    }
    return _jobs[index];
  }

  @override
  Future<bool> existJob(String id) async {
    final int index = _jobs.indexWhere((SmartJob j) => j.id == id);
    return index >= 0;
  }

  @override
  Future<bool> tryAcquireLease(String id, String ownerId, Duration ttl) async {
    final int idx = _jobs.indexWhere((SmartJob j) => j.id == id);
    if (idx < 0) return false;
    final SmartJob job = _jobs[idx];
    final DateTime now = DateTime.now();
    if (job.metadata != null) {
      final String? currentOwner = job.metadata!['leaseOwnerId'] as String?;
      final DateTime? expiresAt = job.metadata!['leaseExpiresAt'] is String
          ? DateTime.tryParse(job.metadata!['leaseExpiresAt'] as String)
          : null;
      if (expiresAt != null &&
          expiresAt.isAfter(now) &&
          currentOwner != ownerId) {
        return false;
      }
    }
    (job.metadata ??= <String, dynamic>{})
      ..['leaseOwnerId'] = ownerId
      ..['leaseExpiresAt'] = now.add(ttl).toIso8601String();
    _jobs[idx] = job;
    return true;
  }

  @override
  Future<void> releaseLease(String id, String ownerId) async {
    final int idx = _jobs.indexWhere((SmartJob j) => j.id == id);
    if (idx < 0) return;
    final SmartJob job = _jobs[idx];
    if (job.metadata != null && job.metadata!['leaseOwnerId'] == ownerId) {
      job.metadata!.remove('leaseOwnerId');
      job.metadata!.remove('leaseExpiresAt');
      _jobs[idx] = job;
    }
  }
}
