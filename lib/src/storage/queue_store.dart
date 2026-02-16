import '../smart_job.dart';

abstract class QueueStore {
  Future<List<SmartJob>> loadJobs();
  Future<void> putJob(SmartJob job);
  Future<void> removeJob(String id);
  Future<SmartJob?> getJob(String id);
  Future<void> clear();

  /// Try to acquire a short-lived lease for [id]. Returns true if acquired.
  Future<bool> tryAcquireLease(String id, String ownerId, Duration ttl) async =>
      false;

  /// Release a previously acquired lease if owned by [ownerId].
  Future<void> releaseLease(String id, String ownerId) async {}
}
