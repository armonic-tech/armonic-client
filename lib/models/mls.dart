/// Wire types of the MLS delivery service (GET /server/{id}/mls and
/// friends). Payload strings are opaque here; lib/mls owns them.
class MlsMember {
  final String deviceId;
  final String userId;
  const MlsMember(this.deviceId, this.userId);

  factory MlsMember.fromJson(Map<String, dynamic> json) => MlsMember(
    json['deviceId'] as String? ?? '',
    json['userId'] as String? ?? '',
  );
}

class MlsPendingAdd {
  final String deviceId;
  final String userId;
  final String keyPackageId;
  final String keyPackage;
  const MlsPendingAdd({
    required this.deviceId,
    required this.userId,
    required this.keyPackageId,
    required this.keyPackage,
  });

  factory MlsPendingAdd.fromJson(Map<String, dynamic> json) => MlsPendingAdd(
    deviceId: json['deviceId'] as String? ?? '',
    userId: json['userId'] as String? ?? '',
    keyPackageId: json['keyPackageId'] as String? ?? '',
    keyPackage: json['keyPackage'] as String? ?? '',
  );
}

class MlsWelcome {
  final String id;
  final int epoch;
  final String payload;
  const MlsWelcome({
    required this.id,
    required this.epoch,
    required this.payload,
  });

  factory MlsWelcome.fromJson(Map<String, dynamic> json) => MlsWelcome(
    id: json['id'] as String? ?? '',
    epoch: (json['epoch'] as num?)?.toInt() ?? 0,
    payload: json['payload'] as String? ?? '',
  );
}

class MlsCommit {
  final int epoch;
  final String senderDeviceId;
  final String payload;
  const MlsCommit({
    required this.epoch,
    required this.senderDeviceId,
    required this.payload,
  });

  factory MlsCommit.fromJson(Map<String, dynamic> json) => MlsCommit(
    epoch: (json['epoch'] as num?)?.toInt() ?? 0,
    senderDeviceId: json['senderDeviceId'] as String? ?? '',
    payload: json['payload'] as String? ?? '',
  );
}

class MlsGroupState {
  final int epoch;
  final List<MlsMember> members;
  final List<MlsPendingAdd> pendingAdds;
  final List<MlsMember> pendingRemoves;
  final String? coordinatorUserId;
  final MlsWelcome? welcome;
  final int keyPackagesLeft;

  const MlsGroupState({
    required this.epoch,
    required this.members,
    required this.pendingAdds,
    required this.pendingRemoves,
    required this.coordinatorUserId,
    required this.welcome,
    required this.keyPackagesLeft,
  });

  bool get exists => epoch > 0;

  factory MlsGroupState.fromJson(Map<String, dynamic> json) => MlsGroupState(
    epoch: (json['epoch'] as num?)?.toInt() ?? 0,
    members: [
      for (final m in json['members'] as List? ?? const [])
        MlsMember.fromJson(m as Map<String, dynamic>),
    ],
    pendingAdds: [
      for (final a in json['pendingAdds'] as List? ?? const [])
        MlsPendingAdd.fromJson(a as Map<String, dynamic>),
    ],
    pendingRemoves: [
      for (final m in json['pendingRemoves'] as List? ?? const [])
        MlsMember.fromJson(m as Map<String, dynamic>),
    ],
    coordinatorUserId: json['coordinatorUserId'] as String?,
    welcome: json['welcome'] == null
        ? null
        : MlsWelcome.fromJson(json['welcome'] as Map<String, dynamic>),
    keyPackagesLeft: (json['keyPackagesLeft'] as num?)?.toInt() ?? 0,
  );
}

class StorageUsage {
  final int usedBytes;
  final int limitBytes;
  const StorageUsage(this.usedBytes, this.limitBytes);

  factory StorageUsage.fromJson(Map<String, dynamic> json) => StorageUsage(
    (json['usedBytes'] as num?)?.toInt() ?? 0,
    (json['limitBytes'] as num?)?.toInt() ?? 0,
  );
}
