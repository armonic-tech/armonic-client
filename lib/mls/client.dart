import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/http_api.dart';
import '../models/models.dart';
import 'crypto.dart';
import 'group.dart';
import 'key_package.dart';
import 'store.dart';

/// The decrypted body of a message: text plus, when there is an image,
/// the keys to fetch and open it.
class DecryptedBody {
  final String text;
  final EncryptedAttachmentRef? attachment;
  const DecryptedBody(this.text, this.attachment);
}

/// How the group looks from this device, for the UI.
enum E2eeStatus {
  /// No device registered yet or the server has no group: nothing to
  /// encrypt with, but nobody else can read anyway.
  starting,

  /// The group exists and this device has not been welcomed into it yet.
  waitingForKeys,

  /// In the group with a usable epoch secret.
  ready,
}

/// One instance's MLS client: the device identity, its key packages, and
/// one [MlsGroup] per server. The server is the delivery service; the
/// decisions (start the group, add the pending devices, evict the kicked
/// ones) are made here, by whichever online member the server nominates.
///
/// Every public method swallows transport errors after logging them: the
/// chat keeps working in the clear-text-history sense, and the next sync
/// retries.
class MlsClient {
  static const keyPackageTarget = 10;
  static const keyPackageLow = 4;

  final ArmonicHttpApi _api;
  final String Function() _token;
  final String baseUrl;
  final MlsStore _store;

  DeviceIdentity? _device;
  Map<String, HpkeKeyPair> _packageKeys = {};
  final Map<String, MlsGroup> _groups = {};
  final Map<String, Future<void>> _syncing = {};
  final Set<String> _resync = {};
  String? _userId;

  /// Fires after anything that changes what the UI can do (ready state,
  /// a new epoch).
  VoidCallback? onChanged;

  MlsClient(
    this._api,
    this._token, {
    required this.baseUrl,
    MlsStore? store,
    this.onChanged,
  }) : _store = store ?? SecureMlsStore();

  String? get deviceId => _device?.deviceId;

  MlsGroup? groupFor(String serverId) => _groups[serverId];

  E2eeStatus statusFor(String serverId) {
    final g = _groups[serverId];
    if (g != null && g.canSend) return E2eeStatus.ready;
    return _knownEpoch[serverId] == null || _knownEpoch[serverId] == 0
        ? E2eeStatus.starting
        : E2eeStatus.waitingForKeys;
  }

  final Map<String, int> _knownEpoch = {};
  final Set<String> _loaded = {};

  // ---- device ------------------------------------------------------------

  /// Loads or mints the device identity and makes sure the server knows
  /// it. Called once per session after auth; safe to call again.
  Future<void> ensureDevice(String userId) async {
    _userId = userId;
    try {
      _device ??= await _store.loadDevice(baseUrl);
      if (_device == null) {
        final signing = await MlsCrypto.newSigningKeyPair();
        _device = DeviceIdentity(_newId(), signing);
        await _store.saveDevice(baseUrl, _device!);
      }
      _packageKeys = await _store.loadPackageKeys(baseUrl);
      await _api.registerDevice(
        _token(),
        _device!.deviceId,
        b64(_device!.signing.publicKey),
      );
    } catch (e) {
      debugPrint('mls: device registration failed: $e');
    }
  }

  static String _newId() => b64(
    MlsCrypto.randomBytes(18),
  ).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');

  /// Publishes fresh key packages when the device is running low; true when
  /// it actually published, so the caller knows the server's view changed.
  Future<bool> _topUpKeyPackages(int left) async {
    final dev = _device;
    final user = _userId;
    if (dev == null || user == null || left >= keyPackageLow) return false;
    final fresh = <String, String>{};
    for (var i = left; i < keyPackageTarget; i++) {
      final key = await MlsCrypto.newHpkeKeyPair();
      final id = _newId();
      final kp = await KeyPackage.create(
        id: id,
        deviceId: dev.deviceId,
        userId: user,
        hpkeKey: key.publicKey,
        identity: dev.signing,
      );
      _packageKeys[id] = key;
      fresh[id] = jsonEncode(kp.toJson());
    }
    await _store.savePackageKeys(baseUrl, _packageKeys);
    await _api.publishKeyPackages(_token(), dev.deviceId, fresh);
    return true;
  }

  // ---- group sync ----------------------------------------------------------

  /// Brings this device's view of [serverId]'s group up to date: joins via
  /// a pending welcome, applies missed commits, and — when the server
  /// nominates us — starts the group or commits the pending adds/removes.
  /// Concurrent calls for the same server collapse into one.
  Future<void> sync(String serverId) {
    final existing = _syncing[serverId];
    if (existing != null) {
      // Collapsing is not enough: a nudge that lands mid-pass usually
      // invalidates state the pass has *already* read (our own key packages
      // are published from inside it), so dropping it leaves the group one
      // step behind with nothing left to wake it. Remember it and run once
      // more when this pass ends.
      _resync.add(serverId);
      return existing;
    }
    // Block body on purpose: `Map.remove` returns the removed future, and a
    // whenComplete callback that returns a future is awaited — the sync
    // would wait on itself forever.
    final f = _sync(serverId).whenComplete(() {
      _syncing.remove(serverId);
      if (_resync.remove(serverId)) sync(serverId);
    });
    _syncing[serverId] = f;
    return f;
  }

  Future<void> _sync(String serverId) async {
    final dev = _device;
    final user = _userId;
    if (dev == null || user == null) return;
    try {
      if (_loaded.add(serverId)) {
        final stored = await _store.loadGroup(baseUrl, serverId);
        if (stored != null) _groups[serverId] = stored;
      }
      var state = await _api.mlsState(_token(), serverId, dev.deviceId);
      // Publishing key packages is what makes this device addable, so the
      // state read before it cannot see us in pendingAdds — and with an
      // empty group that also means the server can nominate nobody to
      // commit. Re-read once when we just published.
      if (await _topUpKeyPackages(state.keyPackagesLeft)) {
        state = await _api.mlsState(_token(), serverId, dev.deviceId);
      }
      _knownEpoch[serverId] = state.epoch;

      var group = _groups[serverId];
      final inGroup = state.members.any((m) => m.deviceId == dev.deviceId);
      if (group != null && !inGroup && state.exists) {
        // The server says we are out (a removal we never saw, or a stale
        // state after a reinstall): drop it and wait to be re-added.
        group = null;
        _groups.remove(serverId);
        await _store.saveGroup(baseUrl, serverId, null);
      }

      final welcome = state.welcome;
      if (welcome != null && (group == null || group.epoch < welcome.epoch)) {
        group = await _join(serverId, welcome);
      }

      if (group != null && group.epoch < state.epoch) {
        group = await _catchUp(serverId, group);
      }

      final coordinating = state.coordinatorUserId == user;
      if (!state.exists && coordinating && group == null) {
        group = await _startGroup(serverId, state);
      } else if (group != null && coordinating && group.epoch == state.epoch) {
        final needed =
            state.pendingAdds.isNotEmpty || state.pendingRemoves.isNotEmpty;
        if (needed) await _commit(serverId, group, state);
      }
    } catch (e) {
      debugPrint('mls: sync $serverId failed: $e');
    }
    onChanged?.call();
  }

  Future<MlsGroup?> _join(String serverId, MlsWelcome welcome) async {
    final dev = _device!;
    final payload = Map<String, Object?>.from(
      jsonDecode(welcome.payload) as Map,
    );
    final kpId = payload['keyPackageId'] as String?;
    final key = kpId == null ? null : _packageKeys[kpId];
    if (key == null) {
      // A welcome for a key package this install no longer has (reinstall,
      // cleared storage): it can never be opened. Ack it so the server
      // stops offering it and re-publish fresh packages.
      debugPrint('mls: welcome for unknown key package $kpId, discarding');
      await _api.mlsAckWelcome(_token(), serverId, welcome.id, dev.deviceId);
      return _groups[serverId];
    }
    try {
      final group = await MlsGroup.fromWelcome(
        payload,
        deviceId: dev.deviceId,
        identity: dev.signing,
        keyPackageKey: key,
      );
      _packageKeys.remove(kpId);
      await _store.savePackageKeys(baseUrl, _packageKeys);
      _groups[serverId] = group;
      await _store.saveGroup(baseUrl, serverId, group);
      await _api.mlsAckWelcome(_token(), serverId, welcome.id, dev.deviceId);
      return group;
    } on MlsException catch (e) {
      debugPrint('mls: welcome rejected: $e');
      await _api.mlsAckWelcome(_token(), serverId, welcome.id, dev.deviceId);
      return _groups[serverId];
    }
  }

  Future<MlsGroup?> _catchUp(String serverId, MlsGroup group) async {
    final commits = await _api.mlsCommits(_token(), serverId, group.epoch);
    for (final c in commits) {
      if (c.epoch != group.epoch + 1) break;
      final stillIn = await _apply(serverId, group, c.payload);
      if (!stillIn) return null;
    }
    return group;
  }

  /// Applies one commit payload; false when it evicted this device.
  Future<bool> _apply(String serverId, MlsGroup group, String payload) async {
    final decoded = Map<String, Object?>.from(jsonDecode(payload) as Map);
    final stillIn = await group.applyCommit(decoded);
    if (!stillIn) {
      _groups.remove(serverId);
      await _store.saveGroup(baseUrl, serverId, null);
      return false;
    }
    await _store.saveGroup(baseUrl, serverId, group);
    return true;
  }

  Future<MlsGroup?> _startGroup(String serverId, MlsGroupState state) async {
    final dev = _device!;
    final group = await MlsGroup.create(
      groupId: serverId,
      deviceId: dev.deviceId,
      userId: _userId!,
      identity: dev.signing,
    );
    return await _commit(serverId, group, state) ? group : null;
  }

  /// Builds and posts a commit for the pending changes. On a stale-epoch
  /// answer the state is left as is: the next sync applies whatever won.
  Future<bool> _commit(
    String serverId,
    MlsGroup group,
    MlsGroupState state,
  ) async {
    final dev = _device!;
    final adds = <KeyPackage>[];
    for (final a in state.pendingAdds) {
      if (a.deviceId == dev.deviceId) continue;
      try {
        adds.add(
          KeyPackage.fromJson(
            Map<String, Object?>.from(jsonDecode(a.keyPackage) as Map),
          ),
        );
      } catch (e) {
        debugPrint('mls: skipping unreadable key package of ${a.deviceId}');
      }
    }
    final removes = [
      for (final r in state.pendingRemoves)
        if (r.deviceId != dev.deviceId) r.deviceId,
    ];
    if (adds.isEmpty && removes.isEmpty && group.epoch != 0) return false;

    final bundle = await group.createCommit(adds: adds, removeDevices: removes);
    try {
      await _api.mlsCommit(_token(), serverId, {
        'deviceId': dev.deviceId,
        'epoch': group.epoch,
        'payload': jsonEncode(bundle.payload),
        'adds': [
          for (final a in bundle.adds)
            {'deviceId': a.deviceId, 'keyPackageId': a.keyPackageId},
        ],
        'removes': bundle.removes,
        'welcomes': {
          for (final e in bundle.welcomes.entries) e.key: jsonEncode(e.value),
        },
      });
    } on ApiException catch (e) {
      debugPrint('mls: commit rejected (${e.statusCode}): ${e.message}');
      return false;
    }
    _groups[serverId] = bundle.next;
    _knownEpoch[serverId] = bundle.next.epoch;
    await _store.saveGroup(baseUrl, serverId, bundle.next);
    return true;
  }

  /// A `mls-commit` frame: apply it in place when it is exactly the next
  /// epoch, otherwise fall back to a full sync.
  Future<void> onCommitFrame(
    String serverId,
    int epoch,
    String senderDeviceId,
    String payload,
  ) async {
    final group = _groups[serverId];
    _knownEpoch[serverId] = epoch;
    if (group == null ||
        senderDeviceId == _device?.deviceId ||
        epoch != group.epoch + 1) {
      await sync(serverId);
      return;
    }
    try {
      await _apply(serverId, group, payload);
    } catch (e) {
      debugPrint('mls: could not apply commit $epoch: $e');
      await sync(serverId);
      return;
    }
    onChanged?.call();
  }

  // ---- messages ------------------------------------------------------------

  /// Encrypts [text] (and the attachment keys) for [channelId]; null when
  /// this device cannot encrypt for the server's group right now.
  Future<String?> encryptBody(
    String serverId,
    String channelId,
    String text, {
    EncryptedAttachmentRef? attachment,
  }) async {
    final group = _groups[serverId];
    if (group == null || !group.canSend) return null;
    final body = utf8.encode(
      jsonEncode({'t': text, if (attachment != null) 'a': attachment.toJson()}),
    );
    final env = await group.encrypt(channelId, body);
    return env.encode();
  }

  /// Opens an encrypted message body; null when the device has no key for
  /// its epoch (sent before this device joined, or after it was removed).
  Future<DecryptedBody?> decryptBody(
    String serverId,
    String channelId,
    String content,
  ) async {
    final group = _groups[serverId];
    final env = Envelope.tryDecode(content);
    if (group == null || env == null) return null;
    try {
      final plain = jsonDecode(
        utf8.decode(await group.decrypt(channelId, env)),
      );
      if (plain is! Map) return null;
      return DecryptedBody(
        plain['t'] as String? ?? '',
        EncryptedAttachmentRef.tryParse(plain['a']),
      );
    } catch (_) {
      return null;
    }
  }
}
