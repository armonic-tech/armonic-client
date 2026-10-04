import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crypto.dart';
import 'group.dart';
import '../util/log.dart';

/// Where a device keeps its MLS material. Everything here is secret: the
/// identity key, the private halves of unpublished key packages and every
/// group's tree keys and epoch secrets.
abstract interface class MlsStore {
  Future<DeviceIdentity?> loadDevice(String baseUrl);
  Future<void> saveDevice(String baseUrl, DeviceIdentity device);
  Future<Map<String, HpkeKeyPair>> loadPackageKeys(String baseUrl);
  Future<void> savePackageKeys(String baseUrl, Map<String, HpkeKeyPair> keys);
  Future<MlsGroup?> loadGroup(String baseUrl, String serverId);
  Future<void> saveGroup(String baseUrl, String serverId, MlsGroup? group);
}

class DeviceIdentity {
  final String deviceId;
  final SigningKeyPair signing;
  const DeviceIdentity(this.deviceId, this.signing);

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'signing': signing.toJson(),
  };

  factory DeviceIdentity.fromJson(Map<String, Object?> json) => DeviceIdentity(
    json['deviceId'] as String,
    SigningKeyPair.fromJson(Map<String, Object?>.from(json['signing'] as Map)),
  );
}

/// Backed by the platform keystore, like the instance list and settings.
/// A read that fails (no plugin under `flutter test`, a locked keystore)
/// reads as "nothing stored" and a failed write is logged: the chat must
/// keep working, it just will not remember its keys across restarts.
class SecureMlsStore implements MlsStore {
  final FlutterSecureStorage _storage;

  SecureMlsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  String _key(String kind, String baseUrl, [String suffix = '']) =>
      'armonic_mls:$kind:$baseUrl${suffix.isEmpty ? '' : ':$suffix'}';

  Future<Map<String, Object?>?> _read(String key) async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || raw.isEmpty) return null;
      final parsed = jsonDecode(raw);
      return parsed is Map ? Map<String, Object?>.from(parsed) : null;
    } catch (e, st) {
      Log.e('mls-store', 'read $key failed', e, st);
      return null;
    }
  }

  Future<void> _write(String key, Map<String, Object?>? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: jsonEncode(value));
      }
    } catch (e, st) {
      Log.e('mls-store', 'write $key failed', e, st);
    }
  }

  @override
  Future<DeviceIdentity?> loadDevice(String baseUrl) async {
    final json = await _read(_key('device', baseUrl));
    return json == null ? null : DeviceIdentity.fromJson(json);
  }

  @override
  Future<void> saveDevice(String baseUrl, DeviceIdentity device) =>
      _write(_key('device', baseUrl), device.toJson());

  @override
  Future<Map<String, HpkeKeyPair>> loadPackageKeys(String baseUrl) async {
    final json = await _read(_key('packages', baseUrl));
    if (json == null) return {};
    return {
      for (final e in json.entries)
        e.key: HpkeKeyPair.fromJson(Map<String, Object?>.from(e.value as Map)),
    };
  }

  @override
  Future<void> savePackageKeys(String baseUrl, Map<String, HpkeKeyPair> keys) =>
      _write(_key('packages', baseUrl), {
        for (final e in keys.entries) e.key: e.value.toJson(),
      });

  @override
  Future<MlsGroup?> loadGroup(String baseUrl, String serverId) async {
    final json = await _read(_key('group', baseUrl, serverId));
    if (json == null) return null;
    try {
      return MlsGroup.fromJson(json);
    } catch (e, st) {
      Log.e('mls-store', 'corrupt group state for $serverId', e, st);
      return null;
    }
  }

  @override
  Future<void> saveGroup(String baseUrl, String serverId, MlsGroup? group) =>
      _write(_key('group', baseUrl, serverId), group?.toJson());
}

/// Keeps everything in memory; for tests and as the fallback when no
/// keystore is available.
class MemoryMlsStore implements MlsStore {
  final Map<String, DeviceIdentity> devices = {};
  final Map<String, Map<String, HpkeKeyPair>> packages = {};
  final Map<String, MlsGroup> groups = {};

  @override
  Future<DeviceIdentity?> loadDevice(String baseUrl) async => devices[baseUrl];
  @override
  Future<void> saveDevice(String baseUrl, DeviceIdentity device) async =>
      devices[baseUrl] = device;
  @override
  Future<Map<String, HpkeKeyPair>> loadPackageKeys(String baseUrl) async =>
      Map.of(packages[baseUrl] ?? {});
  @override
  Future<void> savePackageKeys(
    String baseUrl,
    Map<String, HpkeKeyPair> keys,
  ) async => packages[baseUrl] = Map.of(keys);
  @override
  Future<MlsGroup?> loadGroup(String baseUrl, String serverId) async =>
      groups['$baseUrl/$serverId'];
  @override
  Future<void> saveGroup(
    String baseUrl,
    String serverId,
    MlsGroup? group,
  ) async {
    if (group == null) {
      groups.remove('$baseUrl/$serverId');
    } else {
      groups['$baseUrl/$serverId'] = group;
    }
  }
}
