import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/http_api.dart';
import '../models/models.dart';

/// Whether the stored credential still gets us into an instance. [unknown]
/// covers "not asked yet" *and* "asked and the network failed" — both must
/// look the same to the UI, which is why this isn't a bool.
enum Membership { unknown, member, notMember }

class InstanceStore extends ChangeNotifier {
  static const _storageKey = 'armonic_instances';

  final FlutterSecureStorage _storage;
  final ArmonicHttpApi Function(String baseUrl) _apiFor;
  List<StoredInstance> _instances = [];
  bool loaded = false;

  /// Deliberately not persisted: it's a fact about the *server* re-derived on
  /// every launch. Writing it to disk would let a stale "kicked" outlive a
  /// re-invite.
  final Map<String, Membership> _membership = {};

  InstanceStore({
    FlutterSecureStorage? storage,
    ArmonicHttpApi Function(String baseUrl)? apiFor,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _apiFor = apiFor ?? ArmonicHttpApi.new;

  List<StoredInstance> get instances => List.unmodifiable(_instances);

  Membership membershipOf(String baseUrl) =>
      _membership[baseUrl] ?? Membership.unknown;

  /// A redeemed invite restores the membership; recording it here saves a
  /// second probe and un-dims the rail tile right away.
  void markMember(String baseUrl) {
    if (_membership[baseUrl] == Membership.member) return;
    _membership[baseUrl] = Membership.member;
    notifyListeners();
  }

  StoredInstance? byUrl(String baseUrl) =>
      _instances.where((i) => i.baseUrl == baseUrl).firstOrNull;

  /// What main() calls at launch: restore the rail, then check every stored
  /// credential against its instance.
  Future<void> bootstrap() async {
    await load();
    await refreshMemberships();
  }

  /// Ask each instance whether we're still a member, in parallel.
  ///
  /// `GET /server` is the only endpoint that can answer this — `/info` is
  /// public and returns the same body to everyone, so it cannot tell a member
  /// from a stranger. An empty list means we were removed; a 401 means the JWT
  /// died and is handled as such; anything else (instance down, no network)
  /// leaves the entry [Membership.unknown] rather than accusing the server of
  /// a kick it never performed.
  Future<void> refreshMemberships() async {
    await Future.wait(_instances.map((instance) async {
      final token = instance.token;
      if (token == null) return;
      // One catch-all around the whole probe, storage write included: this
      // runs fire-and-forget from main(), where an escaping error would
      // surface as an unhandled exception at launch.
      try {
        try {
          final servers = await _apiFor(instance.baseUrl).myServers(token);
          _membership[instance.baseUrl] =
              servers.isEmpty ? Membership.notMember : Membership.member;
        } on ApiException catch (e) {
          if (e.statusCode != 401) rethrow;
          // Expired/invalid credential, not a kick. Clearing the token is what
          // routes the rail entry to the sign-in pane.
          _membership.remove(instance.baseUrl);
          await clearToken(instance.baseUrl);
        }
      } catch (e) {
        debugPrint('instance store: membership check for '
            '${instance.baseUrl} failed: $e');
      }
    }));
    notifyListeners();
  }

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
    // A fresh credential (re-login, redeemed invite) invalidates whatever we
    // knew: re-derive it instead of leaving a stale "kicked" on the tile.
    _membership.remove(instance.baseUrl);
    await _persist();
  }

  Future<void> clearToken(String baseUrl) async {
    final idx = _instances.indexWhere((i) => i.baseUrl == baseUrl);
    if (idx < 0 || _instances[idx].token == null) return;
    _instances[idx] = _instances[idx].clearToken();
    _membership.remove(baseUrl);
    await _persist();
  }

  Future<void> remove(String baseUrl) async {
    _instances.removeWhere((i) => i.baseUrl == baseUrl);
    _membership.remove(baseUrl);
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
