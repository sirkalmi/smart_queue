[![Pub Version](https://img.shields.io/pub/v/smart_queue?logo=dart&logoColor=white)](https://pub.dev/packages/smart_queue)
[![Pub Likes](https://img.shields.io/pub/likes/smart_queue)](https://pub.dev/packages/smart_queue/score)
[![Pub Points](https://img.shields.io/pub/points/smart_queue)](https://pub.dev/packages/smart_queue/score)
[![Popularity](https://img.shields.io/pub/popularity/smart_queue)](https://pub.dev/packages/smart_queue/score)
[![Dart SDK](https://badgen.net/pub/sdk-version/smart_queue)](https://pub.dev/packages/smart_queue)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Smart Queue

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

### Quick start (Dart console)

```dart
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

### Quick start (Flutter)

```dart
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:smart_queue/smart_queue.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  final queue = SmartQueue(
    store: HiveStore(boxName: 'jobs'),
    handlers: {
      'sync': (payload) async {
        // call API
      },
    },
  );
  await queue.start();

  runApp(const Placeholder());
}
```

### Storage

- Use `MemoryStore` for ephemeral testing
- Use `HiveStore` for persistence across restarts. Initialize Hive before creating `HiveStore`.

### Retries

Choose a strategy:

```dart
final fixed = RetryStrategy.fixed(const Duration(seconds: 1));
final exp = RetryStrategy.exponential(
  initialDelay: const Duration(milliseconds: 300),
  multiplier: 2,
  maxDelay: const Duration(seconds: 10),
);
final jitter = RetryStrategy.exponentialWithJitter();
```

### API overview

- `SmartQueue.start()` loads persisted jobs and begins processing
- `SmartQueue.add(SmartJob)` enqueues a job and persists it
- `SmartJob` supports `maxRetries` plus optional callbacks: `onSuccess`, `onFailure`, `onRetry`
- Register handlers via `queue.registerHandler('type', handler)` or constructor `handlers`

### Roadmap

- Delayed/scheduled jobs and cron-like intervals
- Job priorities and cancellation
- Batch persistence and encryption
- Flutter helper for lifecycle binding / connectivity aware execution

### License

MIT License. See `LICENSE`.
