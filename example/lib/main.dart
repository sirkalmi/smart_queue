import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smart_queue/smart_queue.dart';

Future<void> main() async {
  // Get app-specific documents directory
  WidgetsFlutterBinding.ensureInitialized();
  Directory appDocDir = await getApplicationDocumentsDirectory();
  final hiveDir = Directory('${appDocDir.path}/smart_queue_hive');

  if (!hiveDir.existsSync()) {
    hiveDir.createSync(recursive: true);
  }

  Hive.init(hiveDir.path);

  final SmartQueue queue = SmartQueue(
    store: HiveStore(boxName: 'jobs'),
    config: SmartQueueConfig(
      concurrency: 1,
      retryStrategy: RetryStrategy.exponentialWithJitter(
        initialDelay: const Duration(milliseconds: 200),
        maxDelay: const Duration(seconds: 2),
      ),
    ),
    handlers: {
      'print': (payload) async {
        log('JOB Started: ${payload['message']}');
        await Future<void>.delayed(const Duration(seconds: 5));
        log('JOB Ended: ${payload['message']}');
      },
      'flaky': (payload) async {
        final int n = (payload['n'] as int? ?? 0);
        if (n % 2 == 0) {
          throw Exception('Simulated failure for even n=$n');
        }
        log('FLAKY OK: $n');
      },
    },
  );

  await queue.start();

  await queue.add(
    SmartJob(id: '1', type: 'print', payload: {'message': 'Hello'}),
  );
  await queue.add(
    SmartJob(id: '2', type: 'print', payload: {'message': 'Hello1'}),
  );
  await queue.add(
    SmartJob(id: '3', type: 'print', payload: {'message': 'Hello2'}),
  );
  await queue.add(
    SmartJob(id: '4', type: 'print', payload: {'message': 'Hello3'}),
  );
  await queue.add(
    SmartJob(id: '2', type: 'flaky', payload: {'n': 2}, maxRetries: 2),
  );
  await queue.add(
    SmartJob(id: '3', type: 'flaky', payload: {'n': 3}, maxRetries: 2),
  );

  // Keep the example alive briefly to observe retries
  await Future<void>.delayed(const Duration(seconds: 5));

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
