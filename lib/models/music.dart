class Music {
  final int id;
  final String title;
  final String artist;
  final String cover;
  final String audio;
  final String genre;
  final String duration;
  final bool isActive;

  Music({
    required this.id,
    required this.title,
    required this.artist,
    required this.cover,
    required this.audio,
    required this.genre,
    required this.duration,
    required this.isActive,
  });

  factory Music.fromJson(Map<String, dynamic> json) {
    final idRaw = json['id'];
    final id = idRaw is int ? idRaw : int.tryParse('$idRaw') ?? 0;

    return Music(
      id: id,
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      // Match Nuxt normalizeTrack: cover || cover_url, audio || audio_url
      cover: (json['cover'] as String?)?.isNotEmpty == true
          ? json['cover'] as String
          : (json['cover_url'] as String? ?? ''),
      audio: (json['audio'] as String?)?.isNotEmpty == true
          ? json['audio'] as String
          : (json['audio_url'] as String? ?? ''),
      genre: json['genre'] as String? ?? '',
      duration: json['duration'] as String? ?? '00:00',
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'cover': cover,
      'audio': audio,
      'genre': genre,
      'duration': duration,
      'is_active': isActive,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Music && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
