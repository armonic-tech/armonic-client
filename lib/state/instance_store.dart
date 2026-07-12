import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';

class InstanceStore extends ChangeNotifier {
  static const _storageKey = 'armonic_instances';

  final FlutterSecureStorage _storage;
  List<StoredInstance> _instances = [];
  bool loaded = false;

  InstanceStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  List<StoredInstance> get instances => List.unmodifiable(_instances);

  StoredInstance? byUrl(String baseUrl) =>
      _instances.where((i) => i.baseUrl == baseUrl).firstOrNull;

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        _instances = [
          for (final item in jsonDecode(raw) as List)
            StoredInstance.fromJson(item as Map<String, dynamic>)
        ];
      }
    } catch (e) {
      debugPrint('instance store: error loading, starting empty: $e');
      _instances = [];
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> upsert(StoredInstance instance) async {
    final idx = _instances.indexWhere((i) => i.baseUrl == instance.baseUrl);
    if (idx >= 0) {
      _instances[idx] = instance;
    } else {
      _instances.add(instance);
    }
    await _persist();
  }

  Future<void> remove(String baseUrl) async {
    _instances.removeWhere((i) => i.baseUrl == baseUrl);
    await _persist();
  }

  Future<void> _persist() async {
    await _storage.write(
      key: _storageKey,
      value: jsonEncode([for (final i in _instances) i.toJson()]),
    );
    notifyListeners();
  }
}
