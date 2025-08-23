[![Pub Version](https://img.shields.io/pub/v/smart_queue?logo=dart&logoColor=white)](https://pub.dev/packages/smart_queue)
[![Pub Likes](https://img.shields.io/pub/likes/smart_queue)](https://pub.dev/packages/smart_queue/score)
[![Pub Points](https://img.shields.io/pub/points/smart_queue)](https://pub.dev/packages/smart_queue/score)
[![Popularity](https://img.shields.io/pub/popularity/smart_queue)](https://pub.dev/packages/smart_queue/score)
[![Dart SDK](https://badgen.net/pub/sdk-version/smart_queue)](https://pub.dev/packages/smart_queue)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Smart Queue

Offline-first, secure, and observable job queue for Dart/Flutter. Handles retries, persistence, priorities, scheduling, multi-instance safety, and integrates with the `smart_request` package for resilient HTTP.

### Features

- Offline-first persistence via `HiveStore`; `MemoryStore` for tests
- Retry strategies: fixed, exponential backoff, jitter
- Concurrency control and fair scheduling with priorities and `scheduledAt`
- Multi-instance safety via short-lived execution leases
- Event stream for progress, retries, successes, failures, DLQ
- Request queue integration with `smart_request` + Dio
- Encryption-ready `PayloadCipher` interface for payload-at-rest

### Why it matters

- Built-in QueueRequestHandler: Easy developer experience
- Typed RequestJob: Safe, clear APIs
- Shared SmartRequestConfig: Consistency across requests
- Retry scheduling in queue: Resilience against network failures
- Progress and error tracking: UI-friendly development
- Poison job handling (DLQ): Safer, predictable job execution
- Scheduling support: Enables time-based job workflows

---

## Install

Add to your `pubspec.yaml`:

```yaml
dependencies:
  smart_queue: ^0.0.1
```

Then fetch packages:

```bash
dart pub get
```

---

## Quick start

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
  )
    ..registerHandler('sum', (p) async {
      final int a = p['a'] ?? 0; final int b = p['b'] ?? 0;
      print('sum=${a + b}');
    });

  await queue.start();
  await queue.add(SmartJob(id: '1', type: 'sum', payload: {'a': 2, 'b': 3}));
}
```

---

## Request queue with smart_request

Use the external `smart_request` package and the built-in adapter in this package to queue resilient HTTP calls.

1) Ensure your app depends on `smart_request` (this package already brings it transitively, but adding explicitly is fine):

```yaml
dependencies:
  smart_request: ^0.1.0
```

2) Register the handler and enqueue a typed request job:

```dart
import 'package:smart_queue/smart_queue.dart';

void setup(SmartQueue queue) {
  queue.registerHandler('smart_request', queueRequestHandler);
}

Future<void> enqueue(SmartQueue queue) async {
  await queue.add(createRequestJob(
    id: 'req-1',
    url: 'https://jsonplaceholder.typicode.com/posts/1',
    method: 'GET',
    config: const SmartRequestConfigSerializable(
      maxRetries: 3,
      initialDelayMs: 500,
      maxDelayMs: 8000,
      backoffFactor: 2.0,
      jitter: true,
      timeoutMs: 5000,
    ),
    priority: 5,
  ));
}
```

---

## Events: progress, retry, DLQ

```dart
queue.events.listen((event) {
if (event is JobProgress) {
print('Progress ${event.job.id}: ${event.progress}');
} else if (event is JobRetryScheduled) {
print('Retry ${event.job.id} in ${event.delay}');
} else if (event is JobDeadLettered) {
print('DLQ: ${event.job.id}');
}
});
```

Handlers can report progress with `JobContext` when registered via `registerHandlerWithContext`.

---

## Priority and scheduling

```dart
await queue.add(SmartJob(
id: 'c',
type: 'sync',
priority: 10,
scheduledAt: DateTime.now().add(const Duration(minutes: 5)),
));
```

---

## API guide (with tables)

### SmartQueueConfig

| Field | Type | Default | Description |
|---|---|---|---|
| concurrency | int | 1 | Maximum number of jobs processed in parallel. |
| retryStrategy | RetryStrategy | Fixed(1s) | Backoff policy for retries (fixed, exponential, jitter). |
| maxQueueSize | int? | null | Optional hard cap for queued + inflight jobs. |
| persistInterval | Duration | 2s | Snapshot frequency to persist job state. |
| leaseTtl | Duration | 30s | Short-lived execution lease to avoid duplicates across instances. |
| ownerId | String? | generated | Optional stable worker identifier (for multi-instance deployments). |

Create with:

```dart
final config = SmartQueueConfig(
  concurrency: 2,
  retryStrategy: RetryStrategy.exponentialWithJitter(
    initialDelay: const Duration(milliseconds: 300),
    maxDelay: const Duration(seconds: 15),
  ),
  leaseTtl: const Duration(seconds: 30),
);
```

### SmartJob

| Field | Type | Persisted | Description |
|---|---|---:|---|
| id | String | Yes | Unique job identifier. |
| type | String | Yes | Handler key registered in the queue. |
| payload | Map<String, dynamic> | Yes | Arbitrary JSON-like job data. |
| maxRetries | int | Yes | Number of retries after first failure. |
| attempts | int | Yes | Attempts so far (auto-managed). |
| createdAt | DateTime | Yes | Creation timestamp. |
| lastRunAt | DateTime? | Yes | Last execution timestamp. |
| lastError | String? | Yes | Last error string. |
| priority | int | Yes | Higher value runs earlier. |
| scheduledAt | DateTime? | Yes | Earliest time job can run. |
| metadata | Map<String, dynamic>? | Yes | Custom application metadata. |
| progress | double? | No | 0.0..1.0 progress (runtime only). |
| onSuccess | void Function(SmartJob)? | No | Callback on success (runtime only). |
| onFailure | void Function(SmartJob, Object, StackTrace)? | No | Callback on failure (runtime only). |
| onRetry | void Function(SmartJob, int, Duration)? | No | Callback before a retry (runtime only). |

Construct and enqueue:

```dart
await queue.add(SmartJob(
  id: 'job-1',
  type: 'sync',
  payload: {'foo': 'bar'},
  maxRetries: 5,
  priority: 10,
  scheduledAt: DateTime.now().add(const Duration(minutes: 2)),
));
```

### Queue methods

| Method | Signature | Notes |
|---|---|---|
| start | Future<void> start() | Loads persisted jobs and begins processing. |
| dispose | Future<void> dispose() | Stops timers; caller manages backend lifecycle. |
| add | Future<void> add(SmartJob job) | Enqueue and persist a job. Respects `maxQueueSize`. |
| registerHandler | void registerHandler(String type, JobHandler handler) | Simple handler: `(Map payload) -> Future<void>`. |
| registerHandlerWithContext | void registerHandlerWithContext(String type, JobHandlerWithContext handler) | Context-aware handler with `JobContext` for progress. |

### Events

| Event | Payload |
|---|---|
| JobEnqueued | job |
| JobStarted | job |
| JobProgress | job, progress |
| JobRetryScheduled | job, attempt, delay |
| JobSucceeded | job |
| JobFailed | job, error, stackTrace |
| JobDeadLettered | job, error, stackTrace |

Subscribe:

```dart
queue.events.listen((e) {
  // update UI / logs
});
```

### Storage backends

| Backend | Package | Persistence | Notes |
|---|---|---|---|
| MemoryStore | built-in | No | Best for tests/dev. |
| HiveStore | hive | Yes | Initialize Hive first; supports metadata for leases. |

### Dead letter queue

| Store | Persistence | Notes |
|---|---|---|
| MemoryDeadLetterStore | No | Keeps failed jobs in-memory; implement your own durable DLQ as needed. |

Enable DLQ:

```dart
final queue = SmartQueue(
  store: HiveStore(boxName: 'jobs'),
  deadLetterStore: MemoryDeadLetterStore(),
);
```

### smart_request integration

Use helper APIs from this package to enqueue network requests powered by `smart_request` and Dio.

| API | Description |
|---|---|
| createRequestJob | Builds a `SmartJob` with URL/method/headers/body and serialized config. |
| queueRequestHandler | Handler to register under `'smart_request'`. |
| SmartRequestConfigSerializable | Serializable config embedded in job payload. |

Config fields:

| Field | Type | Default |
|---|---|---|
| maxRetries | int | 3 |
| initialDelayMs | int | 500 |
| maxDelayMs | int | 8000 |
| backoffFactor | double | 2.0 |
| jitter | bool | true |
| timeoutMs | int | 5000 |

Usage:

```dart
queue.registerHandler('smart_request', queueRequestHandler);

await queue.add(createRequestJob(
  id: 'req-1',
  url: 'https://jsonplaceholder.typicode.com/posts/1',
  method: 'GET',
  config: const SmartRequestConfigSerializable(
    maxRetries: 3,
    initialDelayMs: 500,
    maxDelayMs: 8000,
    backoffFactor: 2.0,
    jitter: true,
    timeoutMs: 5000,
  ),
));
```

### JobContext

| Member | Type | Description |
|---|---|---|
| job | SmartJob | The currently running job. |
| reportProgress | void Function(double) | Report 0.0..1.0 progress for UI/metrics. |

Register and use:

```dart
queue.registerHandlerWithContext('upload', (payload, ctx) async {
  ctx.reportProgress(0.1);
  // ... work ...
  ctx.reportProgress(1.0);
});
```

---

## Storage backends

- `MemoryStore` for tests/dev
- `HiveStore` for production persistence (call `Hive.init(...)` or `Hive.initFlutter()` first)

---

## Encryption (payload-at-rest)

Provide a custom `PayloadCipher` to `HiveStore` to encrypt job payloads when persisted.

---

## Testing

Use `MemoryStore` and simple handlers. See `test/test_smart_queue.dart` for more examples.

---

## License

MIT License. See `LICENSE`.
