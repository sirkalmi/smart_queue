## 0.1.0

- New: smart_request integration (external)
  - Added `queueRequestHandler` and `createRequestJob(...)` helper
  - Added dependencies: `dio`, `smart_request`
- New: Event stream for observability
  - Events: `JobEnqueued`, `JobStarted`, `JobProgress`, `JobRetryScheduled`, `JobSucceeded`, `JobFailed`, `JobDeadLettered`
- New: Dead letter queue (DLQ)
  - Interface `DeadLetterStore` with `MemoryDeadLetterStore` implementation
- New: Priority & scheduling
  - `SmartJob` now supports `priority` and `scheduledAt`
- New: Multi-instance/isolate safety via leases
  - `SmartQueueConfig` adds `leaseTtl`, `ownerId`
  - `QueueStore` gains default `tryAcquireLease` and `releaseLease`
  - `HiveStore` and `MemoryStore` implement lease behavior
- New: Encryption-ready payload persistence
  - `PayloadCipher` abstraction (default `NoopCipher`)
- Concurrency & scheduling fixes
  - Stricter adherence to `concurrency`
  - Fixed idle/stall when `concurrency=1`

Notes:
- No breaking changes to existing basic usage; advanced features are opt-in
- `lib/smart_queue.dart` now exports events, DLQ, crypto, and request integration modules

## 0.0.1

- Initial release of **smart_queue**
- Added:
    - Job queue core (`SmartQueue`)
    - Persistent storage with `HiveStore`
    - Ephemeral storage with `MemoryStore`
    - Retry strategies (fixed, exponential, jitter)
    - Concurrency configuration
    - Typed job handlers