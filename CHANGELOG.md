## 0.0.1

- Initial release of **smart_queue**
- Added:
    - Job queue core (`SmartQueue`)
    - Persistent storage with `HiveStore`
    - Ephemeral storage with `MemoryStore`
    - Retry strategies (fixed, exponential, jitter)
    - Concurrency configuration
    - Typed job handlers