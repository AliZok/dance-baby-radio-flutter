import 'music.dart';

/// A row from the shared `live-music` Supabase table (the live radio station).
///
/// This mirrors the Nuxt frontend's live station payload (see
/// `composables/useLiveRadio.js`): both the web app and this Android app read
/// and write the SAME station row (id = 1), which is what keeps the two
/// clients in sync — the "connection" between the live web project and the app.
class LiveStation {
  final int id;
  final String title;
  final String artist;
  final String cover;
  final String audio;
  final String genre;
  final String duration;
  final double? star;

  /// When the DJ started this track (ISO string from the DB). Elapsed seconds
  /// since this timestamp drive seek-to-position and expiry.
  final String? startedAt;

  const LiveStation({
    required this.id,
    required this.title,
    required this.artist,
    required this.cover,
    required this.audio,
    required this.genre,
    required this.duration,
    this.star,
    this.startedAt,
  });

  bool get hasAudio => audio.isNotEmpty;

  factory LiveStation.fromJson(Map<String, dynamic> json) {
    final idRaw = json['id'];
    final id = idRaw is int ? idRaw : int.tryParse('$idRaw') ?? 0;

    // Normalize to a single canonical UTC string. See [_normalizeStartedAt]:
    // without this the live loop mistakes a fresh track for an expired one and
    // advances forever.
    final startedAt = _normalizeStartedAt(json['startedAt'] ?? json['started_at']);

    final starRaw = json['star'] ?? json['score'];
    double? star;
    if (starRaw is num) {
      star = starRaw.toDouble();
    } else if (starRaw != null) {
      star = double.tryParse(starRaw.toString());
    }

    return LiveStation(
      id: id,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      cover: (json['cover'] as String?)?.isNotEmpty == true
          ? json['cover'] as String
          : (json['cover_url'] as String? ?? ''),
      audio: (json['audio'] as String?)?.isNotEmpty == true
          ? json['audio'] as String
          : (json['audio_url'] as String? ?? ''),
      genre: json['genre'] as String? ?? '',
      duration: json['duration'] as String? ?? '',
      star: star,
      startedAt: startedAt,
    );
  }

  /// Payload written back to the `live-music` table (matches trackToLivePayload).
  /// A fresh [startedAt] is stamped when the station is claimed/published.
  Map<String, dynamic> toPayload({String? startedAt}) {
    return {
      'title': title,
      'artist': artist,
      'cover': cover,
      'audio': audio,
      'genre': genre,
      'duration': duration,
      'star': star,
      'startedAt': startedAt ?? DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Identity used to detect whether a station row actually changed — the audio
  /// url plus a canonical started-at stamp. We key off the parsed epoch instead
  /// of the raw string so the SAME row delivered by REST (poll) and by realtime
  /// (different text format) compares equal — otherwise every poll would look
  /// like a new track and re-trigger the live logic.
  String get identity {
    if (audio.isEmpty) return '';
    final dt = startedAt == null ? null : DateTime.tryParse(startedAt!);
    final stamp = dt == null
        ? (startedAt ?? '')
        : dt.toUtc().microsecondsSinceEpoch.toString();
    return '$audio|$stamp';
  }

  /// Convert to a [Music] so the existing player/preload code can play it.
  Music toMusic() {
    return Music(
      id: id,
      title: title.isEmpty ? 'Live Radio' : title,
      artist: artist,
      cover: cover,
      audio: audio,
      genre: genre,
      duration: duration.isEmpty ? '00:00' : duration,
      isActive: true,
    );
  }

  /// Build a station row from a randomly-picked [Music], stamping the moment it
  /// begins broadcasting (used when claiming/publishing the station).
  factory LiveStation.fromMusic(Music music, {String? startedAt}) {
    return LiveStation(
      id: 1,
      title: music.title,
      artist: music.artist,
      cover: music.cover,
      audio: music.audio,
      genre: music.genre,
      duration: music.duration,
      star: null,
      startedAt: startedAt ?? DateTime.now().toUtc().toIso8601String(),
    );
  }

  // ---- Static helpers mirroring useLiveRadio.js ----

  /// Canonicalizes a `startedAt` value coming from Supabase to a single UTC ISO
  /// string.
  ///
  /// The catch this fixes: PostgREST (poll) returns `startedAt` with a `+00:00`
  /// offset, but Supabase **realtime** returns it offset-less
  /// (`2026-10-20 12:00:00.123456`). Dart's `DateTime.parse` treats an
  /// offset-less string as LOCAL time, so on a non-UTC device every realtime
  /// echo looks hours in the past → `isTrackExpired` says "expired" → the live
  /// loop advances → publishes → gets echoed back → advances again (the reported
  /// "changes music in a loop"). Since the DB session timezone is UTC and every
  /// writer stamps UTC, an offset-less value really is UTC wall-clock — so we
  /// re-interpret it as UTC and store one canonical form.
  static String? _normalizeStartedAt(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toUtc().toIso8601String();
    final text = raw.toString();
    if (text.isEmpty) return text;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return text;
    if (parsed.isUtc) return parsed.toIso8601String();
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    ).toIso8601String();
  }

  /// Parses "mm:ss", "hh:mm:ss" or a plain number of seconds into seconds.
  /// Returns null when the value is empty/unparseable/non-positive.
  static int? parseDurationToSeconds(Object? value) {
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty) return null;

    final asNumber = num.tryParse(str);
    if (asNumber != null && asNumber.isFinite) {
      return asNumber > 0 ? asNumber.toInt() : null;
    }

    final parts = str.split(':').map((p) => int.tryParse(p.trim())).toList();
    if (parts.isEmpty || parts.any((p) => p == null)) return null;

    if (parts.length == 3) {
      return (parts[0]! * 3600) + (parts[1]! * 60) + parts[2]!;
    }
    if (parts.length == 2) {
      return (parts[0]! * 60) + parts[1]!;
    }
    return parts[0]! > 0 ? parts[0] : null;
  }

  /// Seconds elapsed since [startedAt] (0 when missing/invalid/future).
  static double getElapsedSeconds(String? startedAt) {
    if (startedAt == null || startedAt.isEmpty) return 0;
    final parsed = DateTime.tryParse(startedAt);
    if (parsed == null) return 0;
    // Rows are already normalized to UTC in [fromJson], but guard anyway: an
    // offset-less timestamp here is UTC wall-clock, never the device's local
    // zone. Mis-reading it as local is what produced the huge false "elapsed".
    final start = parsed.isUtc
        ? parsed
        : DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
            parsed.millisecond,
            parsed.microsecond,
          );
    final elapsed = DateTime.now().toUtc().difference(start).inMilliseconds / 1000.0;
    return elapsed > 0 ? elapsed : 0;
  }

  /// Whether the station's current track should be considered finished/stale,
  /// so the live loop can advance to the next song.
  static bool isTrackExpired(LiveStation? row, {double graceSeconds = 1.25}) {
    if (row == null || row.audio.isEmpty) return true;
    if (row.startedAt == null || row.startedAt!.isEmpty) return true;

    final elapsed = getElapsedSeconds(row.startedAt);
    final duration = parseDurationToSeconds(row.duration);

    if (duration == null) {
      // Unknown length: treat as stale after 15 minutes so a dead station recovers.
      return elapsed > 15 * 60;
    }
    return elapsed >= duration + graceSeconds;
  }
}
