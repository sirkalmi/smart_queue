import '../smart_job.dart';

sealed class QueueEvent {}

class JobEnqueued extends QueueEvent {
  JobEnqueued(this.job);
  final SmartJob job;
}

class JobStarted extends QueueEvent {
  JobStarted(this.job);
  final SmartJob job;
}

class JobProgress extends QueueEvent {
  JobProgress(this.job, this.progress);
  final SmartJob job;
  final double progress;
}

class JobRetryScheduled extends QueueEvent {
  JobRetryScheduled(this.job, this.attempt, this.delay);
  final SmartJob job;
  final int attempt;
  final Duration delay;
}

class JobSucceeded extends QueueEvent {
  JobSucceeded(this.job);
  final SmartJob job;
}

class JobFailed extends QueueEvent {
  JobFailed(this.job, this.error, this.stackTrace);
  final SmartJob job;
  final Object error;
  final StackTrace stackTrace;
}

class JobDeadLettered extends QueueEvent {
  JobDeadLettered(this.job, this.error, this.stackTrace);
  final SmartJob job;
  final Object error;
  final StackTrace stackTrace;
}
