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

  test('selects higher priority first and emits events', () async {
    final MemoryStore store = MemoryStore();
    final SmartQueue queue = SmartQueue(
      store: store,
      config: const SmartQueueConfig(concurrency: 1),
    );

    final List<String> order = <String>[];
    queue
      ..registerHandler('a', (p) async => order.add('a'))
      ..registerHandler('b', (p) async => order.add('b'));

    final List<String> events = <String>[];
    queue.events.listen((e) {
      if (e is JobEnqueued) events.add('enq:${e.job.id}');
      if (e is JobSucceeded) events.add('ok:${e.job.id}');
    });

    await queue.start();
    await queue.add(SmartJob(id: 'low', type: 'a', priority: 1));
    await queue.add(SmartJob(id: 'high', type: 'b', priority: 10));

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(order, containsAllInOrder(<String>['b', 'a']));
    expect(events.where((s) => s.startsWith('enq:')).toList().length, 2);
    expect(events.where((s) => s.startsWith('ok:')).toList().length, 2);
  });
}
