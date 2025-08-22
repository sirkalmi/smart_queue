import '../smart_job.dart';
import 'queue_store.dart';

class MemoryStore implements QueueStore {
  MemoryStore([List<SmartJob>? seed]) : _jobs = List<SmartJob>.from(seed ?? const <SmartJob>[]);

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
}
