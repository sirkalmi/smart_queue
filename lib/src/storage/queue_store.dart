import '../smart_job.dart';

abstract class QueueStore {
  Future<List<SmartJob>> loadJobs();
  Future<void> putJob(SmartJob job);
  Future<void> removeJob(String id);
  Future<void> clear();
}
