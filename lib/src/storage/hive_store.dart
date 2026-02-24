import 'dart:async';

import 'package:hive/hive.dart';

import '../smart_job.dart';
import 'queue_store.dart';

class HiveStore implements QueueStore {
  HiveStore({required String boxName, HiveInterface? hive})
    : _boxName = boxName,
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
    return box.values
        .map((Map<dynamic, dynamic> m) => SmartJob.fromMap(m))
        .toList();
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

  @override
  Future<SmartJob?> getJob(String id) async {
    final Box<Map<dynamic, dynamic>> box = await _openBox();
    final Map<dynamic, dynamic>? data = box.get(id);

    if (data == null) {
      return null;
    }

    return SmartJob.fromMap(data);
  }

  @override
  Future<bool> existJob(String id) async {
    final Box<Map<dynamic, dynamic>> box = await _openBox();
    final Map<dynamic, dynamic>? data = box.get(id);

    return data != null;
  }

  @override
  Future<bool> tryAcquireLease(String id, String ownerId, Duration ttl) async {
    final Box<Map<dynamic, dynamic>> box = await _openBox();
    final Map<dynamic, dynamic>? existing = box.get(id);
    if (existing == null) return false;
    final DateTime now = DateTime.now();
    final Map metadata = (existing['metadata'] as Map?) ?? <String, dynamic>{};
    final String? currentOwner = metadata['leaseOwnerId'] as String?;
    final DateTime? expiresAt = metadata['leaseExpiresAt'] is String
        ? DateTime.tryParse(metadata['leaseExpiresAt'] as String)
        : null;
    if (expiresAt != null &&
        expiresAt.isAfter(now) &&
        currentOwner != ownerId) {
      return false;
    }
    metadata['leaseOwnerId'] = ownerId;
    metadata['leaseExpiresAt'] = now.add(ttl).toIso8601String();
    existing['metadata'] = metadata;
    await box.put(id, existing.cast<String, dynamic>());
    return true;
  }

  @override
  Future<void> releaseLease(String id, String ownerId) async {
    final Box<Map<dynamic, dynamic>> box = await _openBox();
    final Map<dynamic, dynamic>? existing = box.get(id);
    if (existing == null) return;
    final Map metadata = (existing['metadata'] as Map?) ?? <String, dynamic>{};
    if (metadata['leaseOwnerId'] == ownerId) {
      metadata.remove('leaseOwnerId');
      metadata.remove('leaseExpiresAt');
      existing['metadata'] = metadata;
      await box.put(id, existing.cast<String, dynamic>());
    }
  }

  @override
  Future<void> close() async {
    if (_box?.isOpen == true) {
      await _box?.flush();
      await _box?.close();
    }
  }
}
