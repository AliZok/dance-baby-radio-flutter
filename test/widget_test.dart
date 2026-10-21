import 'package:dance_baby_radio_flutter/models/live_station.dart';
import 'package:dance_baby_radio_flutter/models/music.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the behaviour the Android app must share with the
/// mobile web player (Dance Baby Radio frontend).
void main() {
  group('LiveStation startedAt handling', () {
    const audio = 'https://cdn.example/track.mp3';

    Map<String, dynamic> row(Object? startedAt, {String duration = '00:03:00'}) =>
        {
          'id': 1,
          'title': 'Live',
          'artist': 'DJ',
          'cover': '',
          'audio': audio,
          'genre': 'electronic',
          'duration': duration,
          'startedAt': startedAt,
        };

    test('offset-less realtime stamps are read as UTC, not local time', () {
      // PostgREST polls return `...+00:00`; realtime returns the same instant
      // without an offset. Both must normalize to one canonical UTC string for
      // the clock math, otherwise every realtime echo looks hours old and the
      // live station advances in a loop.
      final polled = LiveStation.fromJson(
        row('2026-10-20T12:00:00.123456+00:00'),
      );
      final echoed = LiveStation.fromJson(row('2026-10-20 12:00:00.123456'));

      expect(polled.startedAt, startsWith('2026-10-20T12:00:00.123'));
      expect(echoed.startedAt, startsWith('2026-10-20T12:00:00.123'));
      expect(echoed.identity, polled.identity);
    });

    test('the raw startedAt is kept for the compare-and-swap claim', () {
      // claimLiveStation sends this value back in `.eq('startedAt', …)`, so it
      // has to be Postgres' own text — re-formatting it makes every claim miss
      // and fall through to an unconditional publish (station hijack loop).
      const raw = '2026-10-20T12:00:00.123456+00:00';
      final station = LiveStation.fromJson(row(raw));

      expect(station.startedAtForCas, raw);
      expect(station.startedAt, isNot(raw));
    });

    test('a freshly claimed station is never expired', () {
      final station = LiveStation.fromJson(
        row(DateTime.now().toUtc().toIso8601String()),
      );
      expect(LiveStation.isTrackExpired(station), isFalse);
      expect(
        LiveStation.getElapsedSeconds(station.startedAt),
        lessThan(5.0),
      );
    });

    test('a station past its duration is expired', () {
      final started = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 10));
      final station = LiveStation.fromJson(row(started.toIso8601String()));
      expect(LiveStation.isTrackExpired(station), isTrue);
    });

    test('unknown duration falls back to the 15 minute stale window', () {
      final recent = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 5));
      final stale = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 20));

      expect(
        LiveStation.isTrackExpired(
          LiveStation.fromJson(row(recent, duration: '')),
        ),
        isFalse,
      );
      expect(
        LiveStation.isTrackExpired(
          LiveStation.fromJson(row(stale, duration: '')),
        ),
        isTrue,
      );
    });
  });

  group('LiveStation zero-duration guard (the live claim storm)', () {
    final fresh = DateTime.now().toUtc().toIso8601String();

    LiveStation stationWith(String duration) => LiveStation.fromJson({
          'id': 1,
          'title': 'Live',
          'artist': 'DJ',
          'cover': '',
          'audio': 'https://cdn.example/track.mp3',
          'genre': 'electronic',
          'duration': duration,
          'startedAt': fresh,
        });

    test('parseDurationToSeconds treats every zero form as unknown', () {
      expect(LiveStation.parseDurationToSeconds('00:00'), isNull);
      expect(LiveStation.parseDurationToSeconds('00:00:00'), isNull);
      expect(LiveStation.parseDurationToSeconds('0'), isNull);
      expect(LiveStation.parseDurationToSeconds(''), isNull);
      expect(LiveStation.parseDurationToSeconds('03:00'), 180);
      expect(LiveStation.parseDurationToSeconds('00:03:00'), 180);
      expect(LiveStation.parseDurationToSeconds('180'), 180);
    });

    test('a bogus 00:00 station row is NOT instantly expired', () {
      // A 0 second duration must never be read as "the song is already over":
      // that made every client claim a new track ~1.25s after the last publish
      // and rewrote the shared live station in a loop.
      expect(LiveStation.isTrackExpired(stationWith('00:00')), isFalse);
      expect(LiveStation.isTrackExpired(stationWith('00:00:00')), isFalse);
      expect(LiveStation.isTrackExpired(stationWith('')), isFalse);
    });

    test('publishing a track without a duration writes an empty one', () {
      Music track(String duration) => Music(
            id: 7,
            title: 'Song',
            artist: 'Artist',
            cover: '',
            audio: 'https://cdn.example/track.mp3',
            genre: 'electronic',
            duration: duration,
            isActive: true,
          );

      // Music substitutes '00:00' for a missing DB duration — that placeholder
      // may not be broadcast to the shared row (it would poison it for the web
      // client too, which parses it as a zero-length song).
      expect(
        LiveStation.fromMusic(track('00:00')).toPayload()['duration'],
        '',
      );
      expect(
        LiveStation.fromMusic(track('04:20')).toPayload()['duration'],
        '04:20',
      );
      expect(
        LiveStation.fromMusic(track('')).toPayload()['duration'],
        '',
      );
    });

    test('identity is empty without audio so an unset station never matches',
        () {
      final unset = LiveStation.fromJson({
        'id': 1,
        'title': 'Live',
        'artist': 'DJ',
        'cover': '',
        'audio': '',
        'genre': 'electronic',
        'duration': '00:03:00',
        'startedAt': '2026-10-20T12:00:00+00:00',
      });
      expect(unset.identity, isEmpty);
      expect(unset.hasAudio, isFalse);
      expect(LiveStation.isTrackExpired(unset), isTrue);
    });
  });
}
