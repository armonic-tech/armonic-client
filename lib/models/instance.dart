/// GET /info: public status of an Armonic instance.
class InstanceInfo {
  final String id;
  final String name;
  final String description;
  final int memberCount;
  final String host;
  final bool claimed;

  /// Logo of the instance, served without a token (the rail paints a tile
  /// for an instance the user may not be a member of). Empty when unset.
  final String logoThumbPath;

  InstanceInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.memberCount,
    required this.host,
    required this.claimed,
    this.logoThumbPath = '',
  });

  factory InstanceInfo.fromJson(Map<String, dynamic> json) => InstanceInfo(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
    host: json['host'] as String? ?? '',
    claimed: json['claimed'] as bool? ?? false,
    logoThumbPath: json['logoThumbUrl'] as String? ?? '',
  );
}

/// An instance the user added, persisted locally by InstanceStore.
class StoredInstance {
  final String baseUrl;
  final String name;
  final String description;
  final String? token;
  final String? displayName;

  StoredInstance({
    required this.baseUrl,
    this.name = '',
    this.description = '',
    this.token,
    this.displayName,
  });

  StoredInstance copyWith({
    String? name,
    String? description,
    String? token,
    String? displayName,
  }) => StoredInstance(
    baseUrl: baseUrl,
    name: name ?? this.name,
    description: description ?? this.description,
    token: token ?? this.token,
    displayName: displayName ?? this.displayName,
  );

  StoredInstance clearToken() => StoredInstance(
    baseUrl: baseUrl,
    name: name,
    description: description,
    displayName: displayName,
  );

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'name': name,
    'description': description,
    'token': token,
    'displayName': displayName,
  };

  factory StoredInstance.fromJson(Map<String, dynamic> json) => StoredInstance(
    baseUrl: json['baseUrl'] as String,
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    token: json['token'] as String?,
    displayName: json['displayName'] as String?,
  );
}
