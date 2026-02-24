import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:hive/hive.dart';
import 'package:smart_queue/smart_queue.dart';
import 'package:test/test.dart';

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

  test('same job cannot execute concurrently', () async {
    final store = MemoryStore();

    final queue = SmartQueue(
      store: store,
      config: const SmartQueueConfig(concurrency: 2),
    );

    int concurrentExecutions = 0;
    int maxConcurrentExecutions = 0;

    final completer = Completer<void>();

    queue.registerHandler('test', (_) async {
      concurrentExecutions++;
      maxConcurrentExecutions = concurrentExecutions > maxConcurrentExecutions
          ? concurrentExecutions
          : maxConcurrentExecutions;

      await Future<void>.delayed(const Duration(milliseconds: 100));

      concurrentExecutions--;
    });

    queue.events.listen((event) {
      if (event is JobSucceeded) {
        completer.complete();
      }
    });

    final job = SmartJob(
      id: 'job-1',
      type: 'test',
      payload: null,
      maxRetries: 0,
    );

    await queue.start();
    await queue.add(job);

    queue.forceRetry(job.id);
    queue.forceRetry(job.id);

    await completer.future;

    expect(
      maxConcurrentExecutions,
      1,
      reason: 'The same job must never be executed concurrently',
    );
  });

  test('forceRetry can duplicate execution with async store', () async {
    final store = MemoryStore();

    final queue = SmartQueue(
      store: store,
      config: const SmartQueueConfig(
        concurrency: 1,
        retryStrategy: FixedRetryStrategy(Duration(milliseconds: 50)),
      ),
    );

    int attempt = 0;
    int succeededJobs = 0;

    final retryScheduled = Completer<void>();

    queue.registerHandler('test', (_) async {
      attempt++;
      if (attempt == 1) {
        throw Exception('fail first attempt');
      }
      await Future.delayed(const Duration(milliseconds: 5));
    });

    queue.events.listen((event) {
      if (event is JobRetryScheduled) {
        retryScheduled.complete();
      }
      if (event is JobSucceeded) {
        succeededJobs++;
      }
    });

    final job = SmartJob(id: 'job-1', type: 'test', maxRetries: 2);

    await queue.start();
    await queue.add(job);

    await retryScheduled.future;

    await queue.forceRetry(job.id);

    await Future.delayed(const Duration(milliseconds: 100));

    expect(
      succeededJobs,
      1,
      reason:
          'Job must succeed exactly once even if forceRetry is called while retry timer is pending',
    );
  });

  Future<SmartQueue> initSmartQueue(Map<String, dynamic> args) async {
    final String ownerId = args['ownerId'];
    final SendPort sendPort = args['sendPort'];
    final DateTime startTime = args['startTime'];
    final HiveStore store = args['store'];

    print('init [$ownerId] store size: ${(await store.loadJobs()).length}');

    final queue = SmartQueue(
      store: store,
      config: SmartQueueConfig(
        concurrency: 1,
        ownerId: ownerId,
        retryStrategy: FixedRetryStrategy(Duration(milliseconds: 100)),
      ),
    );

    queue.registerHandler('job', (payload) async {
      int difference = DateTime.now().difference(startTime).inMilliseconds;
      if (ownerId == 'A' && difference <= 1000) {
        throw Exception('Planed exception $difference');
      }
      await Future.delayed(const Duration(milliseconds: 90));
      sendPort.send(payload['id'] as String);
    });

    queue.events.listen((event) {
      switch (event) {
        case JobEnqueued(:final job) ||
            JobStarted(:final job) ||
            JobProgress(:final job) ||
            JobRetryScheduled(:final job) ||
            JobSucceeded(:final job) ||
            JobFailed(:final job) ||
            JobDeadLettered(:final job):
          print(
            '[SmartQueue] ${event.runtimeType} '
            'jobId: ${job.id}, '
            'queue size: ${queue.length}',
          );
      }
    });

    await queue.start();

    return queue;
  }

  Future<void> queueAIsolateEntry(Map<String, dynamic> args) async {
    final String ownerId = args['ownerId'];
    final SendPort sendPort = args['sendPort'];
    final List<SmartJob>? jobs = args['jobs'];
    final String dbPath = args['dbPath'];
    final store = HiveStore(boxName: 'jobs');
    Directory(dbPath).createSync(recursive: true);
    Hive.init(dbPath);
    args['store'] = store;

    SmartQueue? queue;

    final commandPort = ReceivePort();
    sendPort.send(commandPort.sendPort);

    commandPort.listen((message) async {
      print('lifecycle $ownerId is $message');

      if (message == 'pause' && queue != null) {
        print('dispose $ownerId SmartQueue');
        await queue?.dispose();
        await store.close();
      }
      if (message == 'resume') {
        queue = await initSmartQueue(args);
      }
      if (message == 'addjobs') {
        print('add jobs');
        if (jobs != null) {
          for (final job in jobs) {
            await queue?.add(job);
          }
        }
      }
    });
  }

  Future<void> queueBIsolateEntry(Map<String, dynamic> args) async {
    final String ownerId = args['ownerId'];
    final SendPort sendPort = args['sendPort'];
    final String dbPath = args['dbPath'];
    final store = HiveStore(boxName: 'jobs');
    Directory(dbPath).createSync(recursive: true);
    Hive.init(dbPath);
    args['store'] = store;

    SmartQueue? queue;

    final commandPort = ReceivePort();
    sendPort.send(commandPort.sendPort);

    commandPort.listen((message) async {
      print('lifecycle $ownerId is $message');

      if (message == 'pause' && queue != null) {
        print('dispose $ownerId SmartQueue');
        await queue?.dispose();
        await store.close();
      }
      if (message == 'resume') {
        queue = await initSmartQueue(args);
      }
    });
  }

  test('race condition with two isolates', () async {
    final String dbPath = './hive_test/hive';

    final List<SmartJob> jobs = List.generate(
      10,
      (i) => SmartJob(
        id: 'job-$i',
        type: 'job',
        payload: {'id': 'job-$i'},
        maxRetries: 100,
      ),
    );

    final receivePortA = ReceivePort();
    final receivePortB = ReceivePort();
    SendPort? commandPortA;
    SendPort? commandPortB;
    final processedJobs = <String>[];

    receivePortA.listen((message) {
      if (message is String) processedJobs.add(message);
      if (message is SendPort) commandPortA = message;
    });
    receivePortB.listen((message) {
      if (message is String) processedJobs.add(message);
      if (message is SendPort) commandPortB = message;
    });

    final isolateA = await Isolate.spawn(queueAIsolateEntry, {
      'ownerId': 'A',
      'sendPort': receivePortA.sendPort,
      'jobs': jobs,
      'dbPath': dbPath,
      'startTime': DateTime.now(),
    });
    await Future.delayed(const Duration(milliseconds: 100));
    commandPortA?.send('resume');
    await Future.delayed(const Duration(milliseconds: 100));
    commandPortA?.send('addjobs');
    await Future.delayed(const Duration(milliseconds: 1000));
    commandPortA?.send('pause');
    await Future.delayed(const Duration(milliseconds: 500));

    final isolateB = await Isolate.spawn(queueBIsolateEntry, {
      'ownerId': 'B',
      'sendPort': receivePortB.sendPort,
      'dbPath': dbPath,
      'producer': false,
      'startTime': DateTime.now(),
    });
    await Future.delayed(const Duration(milliseconds: 100));
    commandPortB?.send('resume');
    await Future.delayed(const Duration(milliseconds: 500));
    commandPortB?.send('pause');
    await Future.delayed(const Duration(milliseconds: 500));
    print('kill B isolate');
    isolateB.kill(priority: Isolate.immediate);

    await Future.delayed(const Duration(milliseconds: 100));
    commandPortA?.send('resume');

    await Future<void>.delayed(const Duration(seconds: 5));

    receivePortA.close();
    receivePortB.close();
    isolateA.kill(priority: Isolate.immediate);

    expect(
      processedJobs.length,
      10,
      reason:
          'Race condition detected: some jobs may have been processed by both queues',
    );

    print('Processed jobs: $processedJobs');
  });
}
