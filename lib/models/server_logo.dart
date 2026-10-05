/// POST /server/{id}/logo: where the new logo can be read from.
class ServerLogo {
  final String? logoId;

  /// Public paths on that instance; the thumbnail is what the rail paints.
  final String? logoPath;
  final String? logoThumbPath;

  ServerLogo({this.logoId, this.logoPath, this.logoThumbPath});

  factory ServerLogo.fromJson(Map<String, dynamic> json) => ServerLogo(
    logoId: json['logoId'] as String?,
    logoPath: json['logoUrl'] as String?,
    logoThumbPath: json['logoThumbUrl'] as String?,
  );
}
