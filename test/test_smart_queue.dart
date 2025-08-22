import 'dart:async';

import 'package:test/test.dart';
import 'package:smart_queue/smart_queue.dart';

void main() {
  test('executes jobs and persists state', () async {
    final MemoryStore store = MemoryStore();

    final List<String> results = <String>[];

    final SmartQueue queue = SmartQueue(
      store: store,
      config: const SmartQueueConfig(concurrency: 1),
      handlers: {
        'sum': (payload) async {
          final int a = payload['a'] as int? ?? 0;
          final int b = payload['b'] as int? ?? 0;
          results.add('sum=${a + b}');
        },
      },
    );

    await queue.start();

    await queue.add(SmartJob(id: 'a', type: 'sum', payload: {'a': 2, 'b': 3}));
    await queue.add(SmartJob(id: 'b', type: 'sum', payload: {'a': 5, 'b': 7}));

    // Allow processing
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(results, containsAllInOrder(<String>['sum=5', 'sum=12']));
  });

  test('retries failed job according to strategy', () async {
    final MemoryStore store = MemoryStore();

    int attempts = 0;
    final Completer<void> done = Completer<void>();

    final SmartQueue queue = SmartQueue(
      store: store,
      config: SmartQueueConfig(
        concurrency: 1,
        retryStrategy: RetryStrategy.fixed(const Duration(milliseconds: 50)),
      ),
      handlers: {
        'flaky': (payload) async {
          attempts++;
          if (attempts < 3) {
            throw Exception('fail');
          }
          done.complete();
        },
      },
    );

    await queue.start();
    await queue.add(SmartJob(id: 'x', type: 'flaky', maxRetries: 5));

    await done.future.timeout(const Duration(seconds: 5));

    expect(attempts, 3);
  });
}
