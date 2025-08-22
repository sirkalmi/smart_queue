## smart_queue

Lightweight job queue for Dart/Flutter. Handles offline tasks, retries, persistence. Ideal for background sync and guaranteed execution.

### Features

- **Offline-first**: Persist jobs to disk (Hive) and resume on app restart
- **Retry strategies**: Fixed, exponential backoff, and jitter
- **Concurrency control**: Run multiple jobs in parallel
- **Pluggable storage**: In-memory (`MemoryStore`) or Hive-based (`HiveStore`)
- **Typed handlers**: Register handlers per job `type`

### Install

Add to `pubspec.yaml`:

```yaml
dependencies:
  smart_queue: ^0.0.1
```

### Quick start

```dart
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:smart_queue/smart_queue.dart';

Future<void> main() async {
  Hive.init('.smart_queue_hive');

  final queue = SmartQueue(
    store: HiveStore(boxName: 'jobs'),
    config: SmartQueueConfig(
      concurrency: 2,
      retryStrategy: RetryStrategy.exponentialWithJitter(),
    ),
    handlers: {
      'upload': (payload) async {
        // do work here
      },
    },
  );

  await queue.start();
  await queue.add(SmartJob(id: '1', type: 'upload', payload: {'path': '/tmp/file'}));
}
```

### API overview

- **`SmartQueue`**: Queue manager; `start()`, `add(job)`, and concurrency control
- **`SmartJob`**: Job model (`id`, `type`, `payload`, `maxRetries`, callbacks)
- **`RetryStrategy`**: `fixed`, `exponential`, `exponentialWithJitter`
- **Storage**: `MemoryStore` (volatile) and `HiveStore` (persistent)

### Roadmap

- Delayed/scheduled jobs and cron-like intervals
- Job priorities and cancellation
- Batch persistence and encryption
- Flutter helper for lifecycle binding / connectivity aware execution
