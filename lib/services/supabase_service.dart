import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/music.dart';

class SupabaseService {
  static const String _supabaseUrl = 'https://fdveybzxmfvhbznemfpr.supabase.co';
  static const String _supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZkdmV5Ynp4bWZ2aGJ6bmVtZnByIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzUyNDMzNTAsImV4cCI6MjA1MDgxOTM1MH0.7_RT9A9CeU42u_96c73ADg1KkpQFmGWkQPP1i48V2x4';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseKey,
    );
  }

  final SupabaseClient _client = Supabase.instance.client;

  /// Calls the `get_random_track` Postgres RPC function in Supabase
  Future<Music?> getRandomTrack(List<String> genreFilters) async {
    try {
      final List<String>? targetGenres = genreFilters.isNotEmpty ? genreFilters : null;
      
      final response = await _client.rpc('get_random_track', params: {
        'target_genres': targetGenres,
      });

      if (response == null) return null;

      if (response is List) {
        if (response.isEmpty) return null;
        return Music.fromJson(response.first as Map<String, dynamic>);
      } else if (response is Map) {
        return Music.fromJson(response as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      print('getRandomTrack Error: $e');
      return null;
    }
  }

  /// Picks one random active track, optionally avoiding `excludeTrack`
  Future<Music?> getRandomActiveMusic({
    required List<String> genreFilters,
    Music? excludeTrack,
  }) async {
    // Random SQL selection can legitimately return the excluded song more
    // than once. Retry a few times and never report that duplicate as a valid
    // replacement for the other player.
    for (var attempt = 0; attempt < 5; attempt++) {
      final selected = await getRandomTrack(genreFilters);
      if (selected == null) return null;
      if (excludeTrack == null || selected.id != excludeTrack.id) {
        return selected;
      }
    }

    return null;
  }

  /// Updates track details (e.g. marking it inactive on error)
  Future<bool> updateMusicById(int id, Map<String, dynamic> updates) async {
    try {
      await _client
          .from('musics')
          .update(updates)
          .eq('id', id);
      return true;
    } catch (e) {
      print('updateMusicById Error: $e');
      return false;
    }
  }
}
