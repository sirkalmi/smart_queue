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

  MemoryDeadLetterStore memoryDeadLetterStore = MemoryDeadLetterStore();

  if (!hiveDir.existsSync()) {
    hiveDir.createSync(recursive: true);
  }

  Hive.init(hiveDir.path);

  final SmartQueue queue =
      SmartQueue(
          store: HiveStore(boxName: 'jobs'),
          config: SmartQueueConfig(
            concurrency: 1,
            retryStrategy: RetryStrategy.exponentialWithJitter(
              initialDelay: const Duration(milliseconds: 200),
              maxDelay: const Duration(seconds: 2),
            ),
          ),
          deadLetterStore: memoryDeadLetterStore,
        )
        ..registerHandler('print', (payload) async {
          await Future<void>.delayed(const Duration(seconds: 5));
        })
        ..registerHandler('smart_request', queueRequestHandler);

  await queue.start();

  // Observe queue events for UI/diagnostics
  queue.events.listen((event) {
    if (event is JobEnqueued) {
      log('Enqueued ${event.job.id}');
    } else if (event is JobEnqueued) {
      log('Started ${event.job.id}');
    } else if (event is JobProgress) {
      log('Progress ${event.job.id}: ${event.progress}');
    } else if (event is JobRetryScheduled) {
      log('Retry ${event.job.id} in ${event.delay}');
    } else if (event is JobDeadLettered) {
      log('DLQ: ${event.job.id} error=${event.error}');
    } else if (event is JobSucceeded) {
      log('Success: ${event.job.id}');
    } else if (event is JobFailed) {
      log('Failed: ${event.job.id}:  error=${event.error}');
    } else {
      log('Un-Known: $event');
    }
  });

  for (int i = 0; i < 10; i++) {
    await queue.add(
      SmartJob(
        id: (i).toString(),
        type: 'print',
        payload: {'message': 'Hello$i'},
      ),
    );
  }

  await queue.add(
    createRequestJob(
      id: 'req-1',
      url: 'https://app.mobddvers.com/',
      method: 'GET',
    ),
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Placeholder();
  }
}
