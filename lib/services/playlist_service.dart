import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/music.dart';
import '../models/playlist.dart';
import 'auth_service.dart';

/// Mirrors Nuxt `composables/usePlaylistsAPI.js`.
class PlaylistService {
  final AuthService authService;

  PlaylistService(this.authService);

  SupabaseClient get _client => Supabase.instance.client;

  String? get _userId => authService.currentUser?.id;

  Future<({List<Playlist> data, String? error})> getUserPlaylists() async {
    if (_userId == null) {
      return (data: <Playlist>[], error: 'Not authenticated');
    }

    try {
      final response = await _client
          .from('playlists')
          .select('*, playlist_tracks(count)')
          .eq('user_id', _userId!)
          .order('created_at', ascending: false);

      final list = (response as List)
          .map((row) => Playlist.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
      return (data: list, error: null);
    } catch (e) {
      try {
        final response = await _client
            .from('playlists')
            .select('*')
            .eq('user_id', _userId!)
            .order('created_at', ascending: false);

        final list = (response as List)
            .map((row) => Playlist.fromJson(Map<String, dynamic>.from(row as Map)))
            .toList();
        return (data: list, error: null);
      } catch (fallbackError) {
        return (data: <Playlist>[], error: fallbackError.toString());
      }
    }
  }

  Future<({Playlist? data, String? error})> createPlaylist({
    required String name,
    bool isPublic = false,
  }) async {
    if (_userId == null) {
      return (data: null, error: 'Not authenticated');
    }

    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return (data: null, error: 'Playlist name is required.');
    }

    try {
      final row = await _client
          .from('playlists')
          .insert({
            'name': trimmed,
            'is_public': isPublic,
            'user_id': _userId,
          })
          .select()
          .single();

      return (
        data: Playlist.fromJson(Map<String, dynamic>.from(row)).copyWith(trackCount: 0),
        error: null,
      );
    } catch (e) {
      return (data: null, error: e.toString());
    }
  }

  Future<({bool success, String? error})> deletePlaylist(String playlistId) async {
    try {
      await _client.from('playlist_tracks').delete().eq('playlist_id', playlistId);
      await _client
          .from('playlists')
          .delete()
          .eq('id', playlistId)
          .eq('user_id', _userId ?? '');
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: e.toString());
    }
  }

  Future<({List<Music> data, String? error})> getPlaylistTracks(String playlistId) async {
    // Match Nuxt select exactly (no cover_url / audio_url — those columns
    // break the join on some schemas and returned empty track lists).
    try {
      final response = await _client.from('playlist_tracks').select('''
            id,
            created_at,
            music_id,
            playlist_id,
            musics (
              id,
              title,
              artist,
              cover,
              audio,
              genre,
              duration
            )
          ''').eq('playlist_id', playlistId).order('created_at', ascending: true);

      final tracks = <Music>[];
      for (final row in response as List) {
        final map = Map<String, dynamic>.from(row as Map);
        if (map['music_id'] == null) continue;

        final musics = map['musics'];
        if (musics is Map) {
          tracks.add(Music.fromJson(Map<String, dynamic>.from(musics)));
        } else {
          // Nested join missing — still keep the music id for fallback fill.
          tracks.add(Music.fromJson({'id': map['music_id']}));
        }
      }

      // If join returned only bare ids, hydrate from musics table.
      final needsHydration = tracks.any((t) => t.audio.isEmpty && t.title == 'Unknown Title');
      if (needsHydration) {
        return _fetchTracksManual(playlistId);
      }

      return (data: tracks, error: null);
    } catch (_) {
      return _fetchTracksManual(playlistId);
    }
  }

  Future<({List<Music> data, String? error})> _fetchTracksManual(String playlistId) async {
    try {
      final rows = await _client
          .from('playlist_tracks')
          .select('*')
          .eq('playlist_id', playlistId)
          .order('created_at', ascending: true);

      final musicIds = <dynamic>[];
      for (final r in rows as List) {
        final id = (r as Map)['music_id'];
        if (id != null && !musicIds.contains(id)) {
          musicIds.add(id);
        }
      }

      if (musicIds.isEmpty) {
        return (data: <Music>[], error: null);
      }

      final musics = await _client
          .from('musics')
          .select('id, title, artist, cover, audio, genre, duration')
          .inFilter('id', musicIds);

      // String keys avoid int/num identity mismatches from JSON decoding.
      final musicMap = <String, Music>{};
      for (final m in musics as List) {
        final map = Map<String, dynamic>.from(m as Map);
        musicMap['${map['id']}'] = Music.fromJson(map);
      }

      final tracks = <Music>[];
      for (final row in rows) {
        final id = (row as Map)['music_id'];
        final music = musicMap['$id'];
        if (music != null) {
          tracks.add(music);
        }
      }
      return (data: tracks, error: null);
    } catch (e) {
      return (data: <Music>[], error: e.toString());
    }
  }

  Future<({bool success, String? error})> addTrackToPlaylist(
    String playlistId,
    int musicId,
  ) async {
    try {
      await _client.from('playlist_tracks').insert({
        'playlist_id': playlistId,
        'music_id': musicId,
      });
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: e.toString());
    }
  }

  Future<({bool success, String? error})> removeTrackFromPlaylist(
    String playlistId,
    int musicId,
  ) async {
    try {
      await _client
          .from('playlist_tracks')
          .delete()
          .eq('playlist_id', playlistId)
          .eq('music_id', musicId);
      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: e.toString());
    }
  }

  Future<({List<String> data, String? error})> getTrackPlaylistIds(int musicId) async {
    if (_userId == null) {
      return (data: <String>[], error: null);
    }

    try {
      final userPlaylists = await _client
          .from('playlists')
          .select('id')
          .eq('user_id', _userId!);

      final playlistIds = (userPlaylists as List)
          .map((p) => (p as Map)['id']?.toString())
          .whereType<String>()
          .toList();

      if (playlistIds.isEmpty) {
        return (data: <String>[], error: null);
      }

      final rows = await _client
          .from('playlist_tracks')
          .select('playlist_id')
          .eq('music_id', musicId)
          .inFilter('playlist_id', playlistIds);

      final ids = (rows as List)
          .map((r) => (r as Map)['playlist_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      return (data: ids, error: null);
    } catch (e) {
      return (data: <String>[], error: e.toString());
    }
  }
}
