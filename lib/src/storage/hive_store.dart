import 'dart:async';

import 'package:hive/hive.dart';

import '../smart_job.dart';
import 'queue_store.dart';

class HiveStore implements QueueStore {
  HiveStore({
    required String boxName,
    HiveInterface? hive,
  })  : _boxName = boxName,
        _hive = hive ?? Hive;

  final String _boxName;
  final HiveInterface _hive;
  Box<Map<dynamic, dynamic>>? _box;

  Future<Box<Map<dynamic, dynamic>>> _openBox() async {
    if (_box?.isOpen == true) {
      return _box!;
    }
    _box = await _hive.openBox<Map<dynamic, dynamic>>(_boxName);
    return _box!;
  }

  @override
  Future<void> clear() async {
    final Box<Map<dynamic, dynamic>> box = await _openBox();
    await box.clear();
  }

  @override
  Future<List<SmartJob>> loadJobs() async {
    final Box<Map<dynamic, dynamic>> box = await _openBox();
    return box.values.map((Map<dynamic, dynamic> m) => SmartJob.fromMap(m)).toList();
  }

  @override
  Future<void> putJob(SmartJob job) async {
    final Box<Map<dynamic, dynamic>> box = await _openBox();
    await box.put(job.id, job.toMap());
  }

  @override
  Future<void> removeJob(String id) async {
    final Box<Map<dynamic, dynamic>> box = await _openBox();
    await box.delete(id);
  }
}
