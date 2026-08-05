class Playlist {
  final String id;
  final String name;
  final bool isPublic;
  final String userId;
  final DateTime? createdAt;
  final int trackCount;

  Playlist({
    required this.id,
    required this.name,
    required this.isPublic,
    required this.userId,
    this.createdAt,
    this.trackCount = 0,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final trackCountRaw = json['playlist_tracks'];
    int count = 0;
    if (trackCountRaw is List && trackCountRaw.isNotEmpty) {
      final first = trackCountRaw.first;
      if (first is Map && first['count'] != null) {
        final raw = first['count'];
        count = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
      }
    } else if (json['trackCount'] is num) {
      count = (json['trackCount'] as num).toInt();
    }

    return Playlist(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Untitled',
      isPublic: json['is_public'] as bool? ?? false,
      userId: json['user_id']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      trackCount: count,
    );
  }

  Playlist copyWith({
    String? id,
    String? name,
    bool? isPublic,
    String? userId,
    DateTime? createdAt,
    int? trackCount,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      isPublic: isPublic ?? this.isPublic,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      trackCount: trackCount ?? this.trackCount,
    );
  }
}
