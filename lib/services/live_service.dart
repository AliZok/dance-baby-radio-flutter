import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/live_station.dart';
import '../models/music.dart';
import 'supabase_service.dart';

/// Mirrors the Nuxt `composables/useLiveRadio.js`: it drives the shared
/// `live-music` station row so the web player and this Android app broadcast /
/// listen to the very same live feed.
///
/// The station is a single row (id = [LIVE_STATION_ID]). A listener who is the
/// first to "claim" it stamps a new track + `startedAt`; everyone else reads
/// the same row and seeks to the elapsed time, so all clients stay in sync.
class LiveService {
  static const int liveStationId = 1;
  static const Duration pollInterval = Duration(seconds: 5);

  /// Live draws from this fixed genre pool (hidden GENRE button in live mode).
  static const List<String> liveGenreFilters = ['electronic', 'pop'];

  final SupabaseClient _client = Supabase.instance.client;
  final SupabaseService _musicApi = SupabaseService();

  /// The most recently seen station row (kept so the resync watchdog can read
  /// it between realtime/poll updates).
  LiveStation? _currentStation;
  LiveStation? get currentStation => _currentStation;

  /// Cache of `musics.id` resolved from a station audio url. The shared
  /// `live-music` row only stores its own fixed id (= [liveStationId]), never
  /// the catalogue id of the song that is on air, so saving the live track to a
  /// playlist needs the real id looked up once per track (then reused for
  /// membership checks / removes without re-hitting Supabase every sync tick).
  final Map<String, int> _musicIdByAudio = {};

  /// Resolves the real `musics.id` for the track currently on air, keyed by its
  /// audio url. Returns null when no catalogue row matches (e.g. a station
  /// stamped with a url that is not in `musics`).
  Future<int?> resolveMusicIdByAudio(String audioUrl) async {
    if (audioUrl.isEmpty) return null;
    final cached = _musicIdByAudio[audioUrl];
    if (cached != null) return cached;
    try {
      final row = await _client
          .from('musics')
          .select('id')
          .eq('audio', audioUrl)
          .maybeSingle();
      final raw = row?['id'];
      final id = raw is int ? raw : int.tryParse('${raw ?? ''}');
      if (id != null && id > 0) {
        _musicIdByAudio[audioUrl] = id;
        return id;
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('resolveMusicIdByAudio Error: $e');
      return null;
    }
  }

  Future<LiveStation?> fetchLiveStation() async {
    try {
      final data = await _client
          .from('live-music')
          .select('*')
          .eq('id', liveStationId)
          .maybeSingle();

      if (data == null) return null;
      final row = LiveStation.fromJson(data);
      _currentStation = row;
      return row;
    } catch (e) {
      // ignore: avoid_print
      print('fetchLiveStation Error: $e');
      return null;
    }
  }

  Future<LiveStation?> publishLiveStation(Music track) async {
    try {
      final station = LiveStation.fromMusic(track);
      final data = await _client
          .from('live-music')
          .update(station.toPayload())
          .eq('id', liveStationId)
          .select()
          .maybeSingle();

      if (data == null) return null;
      final row = LiveStation.fromJson(data);
      _currentStation = row;
      return row;
    } catch (e) {
      // ignore: avoid_print
      print('publishLiveStation Error: $e');
      return null;
    }
  }

  /// Atomically takes over the station only if `startedAt` still matches
  /// [expectedStartedAt] (compare-and-swap so two claimers don't clobber each
  /// other). Returns `claimed: false` when someone else moved first.
  ///
  /// [expectedStartedAt] MUST be the raw text Postgres gave us
  /// ([LiveStation.startedAtForCas]): the database compares its own `timestamptz`
  /// rendering, so a re-formatted/normalized string never matches and every
  /// claim silently falls through to the unconditional publish below.
  Future<({LiveStation? data, bool claimed})> claimLiveStation(
    String? expectedStartedAt,
    Music track,
  ) async {
    try {
      final station = LiveStation.fromMusic(track);
      var query =
          _client.from('live-music').update(station.toPayload()).eq('id', liveStationId);

      if (expectedStartedAt != null && expectedStartedAt.isNotEmpty) {
        query = query.eq('startedAt', expectedStartedAt);
      } else {
        query = query.isFilter('startedAt', null);
      }

      final data = await query.select();
      if (data.isNotEmpty) {
        final row = LiveStation.fromJson(data.first);
        _currentStation = row;
        return (data: row, claimed: true);
      }
      return (data: null, claimed: false);
    } catch (e) {
      // ignore: avoid_print
      print('claimLiveStation Error: $e');
      return (data: null, claimed: false);
    }
  }

  /// Picks a random active track from the live genre pool, optionally avoiding
  /// [excludeTrack] so we never re-queue the same song back-to-back.
  ///
  /// The extra *audio-url* comparison (not just the id) mirrors the web
  /// `pickStationTrack`: the same recording can exist under two row ids, and
  /// publishing it again would make the station look "new" while sounding
  /// identical to what every listener is already hearing.
  Future<Music?> pickStationTrack({Music? excludeTrack}) async {
    final selected = await _musicApi.getRandomActiveMusic(
      genreFilters: liveGenreFilters,
      excludeTrack: excludeTrack,
    );
    if (selected == null) return null;

    if (excludeTrack != null &&
        excludeTrack.audio.isNotEmpty &&
        selected.audio == excludeTrack.audio) {
      final retry = await _musicApi.getRandomActiveMusic(
        genreFilters: liveGenreFilters,
      );
      if (retry?.audio.isNotEmpty == true) return retry;
    }
    return selected;
  }

  /// Ensures a live, un-expired track is on air; claims/publishes the next one
  /// if the station is empty or stale. Returns the row now on air.
  Future<LiveStation?> ensureLiveStation({Music? excludeTrack}) async {
    final current = await fetchLiveStation();
    if (current != null &&
        current.hasAudio &&
        !LiveStation.isTrackExpired(current)) {
      return current;
    }

    final nextTrack = await pickStationTrack(excludeTrack: excludeTrack);
    if (nextTrack == null) return current;

    final claimed = await claimLiveStation(current?.startedAtForCas, nextTrack);
    if (claimed.claimed) return claimed.data;

    final latest = await fetchLiveStation();
    if (latest != null &&
        latest.hasAudio &&
        !LiveStation.isTrackExpired(latest)) {
      return latest;
    }

    return await publishLiveStation(nextTrack) ?? latest;
  }

  /// Moves the station to the next track (used when the current one ends while
  /// in live mode). Falls back to publishing if the optimistic claim misses.
  Future<LiveStation?> advanceLiveStation({
    LiveStation? currentRow,
    Music? excludeTrack,
  }) async {
    final current = currentRow ?? await fetchLiveStation();
    final nextTrack = await pickStationTrack(excludeTrack: excludeTrack);
    if (nextTrack == null) return current;

    final claimed = await claimLiveStation(current?.startedAtForCas, nextTrack);
    if (claimed.claimed) return claimed.data;

    final latest = await fetchLiveStation();
    if (latest != null && latest.identity != (current?.identity ?? '')) {
      return latest;
    }

    return await publishLiveStation(nextTrack) ?? latest;
  }

  /// Subscribes to station changes via Supabase realtime + a polling fallback
  /// (same belt-and-braces approach as the web client). Returns a cancel fn.
  void Function() subscribeLiveStation(void Function(LiveStation row) onChange) {
    var stopped = false;

    void notify(LiveStation? row) {
      if (stopped || row == null || !row.hasAudio) return;
      _currentStation = row;
      onChange(row);
    }

    RealtimeChannel? channel;
    try {
      channel = _client.channel('live-radio-station-$liveStationId');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'live-music',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: liveStationId,
        ),
        callback: (payload) {
          notify(LiveStation.fromJson(payload.newRecord));
        },
      ).subscribe();
    } catch (e) {
      // ignore: avoid_print
      print('subscribeLiveStation realtime failed, relying on polling: $e');
    }

    Timer? poll;
    poll = Timer.periodic(pollInterval, (_) async {
      if (stopped) return;
      final row = await fetchLiveStation();
      notify(row);
    });

    return () {
      stopped = true;
      poll?.cancel();
      try {
        if (channel != null) _client.removeChannel(channel);
      } catch (_) {}
    };
  }
}
