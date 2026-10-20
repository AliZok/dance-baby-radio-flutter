import 'package:dance_baby_radio_flutter/models/live_station.dart';
import 'package:dance_baby_radio_flutter/widgets/welcome_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the behaviour the Android app must share with the
/// mobile web player (Dance Baby Radio frontend).
void main() {
  group('Let\'s GO welcome gate', () {
    testWidgets('shows LOADING and cannot be dismissed until a track is ready',
        (tester) async {
      var released = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeOverlay(
            isReady: false,
            onLetsGo: () => released++,
          ),
        ),
      );

      expect(find.text('LOADING...'), findsOneWidget);
      expect(find.text("Let's GO"), findsNothing);

      await tester.tap(find.byType(WelcomeOverlay));
      await tester.pump();
      expect(released, 0, reason: 'a tap must not start playback while loading');
    });

    testWidgets('releases playback on the Let\'s GO tap', (tester) async {
      var released = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeOverlay(
            isReady: true,
            onLetsGo: () => released++,
          ),
        ),
      );

      expect(find.text("Let's GO"), findsOneWidget);

      await tester.tap(find.byType(WelcomeOverlay));
      await tester.pump();
      expect(released, 1);
    });
  });

  group('LiveStation startedAt handling', () {
    const audio = 'https://cdn.example/track.mp3';

    Map<String, dynamic> row(Object? startedAt) => {
          'id': 1,
          'title': 'Live',
          'artist': 'DJ',
          'cover': '',
          'audio': audio,
          'genre': 'electronic',
          'duration': '00:03:00',
          'startedAt': startedAt,
        };

    test('offset-less realtime stamps are read as UTC, not local time', () {
      // PostgREST polls return `...+00:00`; realtime returns the same instant
      // without an offset. Both must normalize to one canonical UTC string,
      // otherwise every realtime echo looks hours old and the live station
      // advances in a loop.
      final polled = LiveStation.fromJson(
        row('2026-10-20T12:00:00.123456+00:00'),
      );
      final echoed = LiveStation.fromJson(row('2026-10-20 12:00:00.123456'));

      expect(polled.startedAt, startsWith('2026-10-20T12:00:00.123'));
      expect(echoed.startedAt, startsWith('2026-10-20T12:00:00.123'));
      expect(echoed.identity, polled.identity);
    });

    test('a freshly claimed station is never expired', () {
      final station = LiveStation.fromJson(
        row(DateTime.now().toUtc().toIso8601String()),
      );
      expect(LiveStation.isTrackExpired(station), isFalse);
      expect(LiveStation.getElapsedSeconds(station.startedAt),
        lessThan(5.0));
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
          LiveStation.fromJson({...row(recent), 'duration': ''}),
        ),
        isFalse,
      );
      expect(
        LiveStation.isTrackExpired(
          LiveStation.fromJson({...row(stale), 'duration': ''}),
        ),
        isTrue,
      );
    });

    test('parseDurationToSeconds accepts mm:ss, hh:mm:ss and raw seconds', () {
      expect(LiveStation.parseDurationToSeconds('03:00'), 180);
      expect(LiveStation.parseDurationToSeconds('00:03:00'), 180);
      expect(LiveStation.parseDurationToSeconds('180'), 180);
      expect(LiveStation.parseDurationToSeconds(''), isNull);
      expect(LiveStation.parseDurationToSeconds('0'), isNull);
    });

    test('identity is empty without audio so an unset station never matches',
        () {
      final unset = LiveStation.fromJson({
        ...row('2026-10-20T12:00:00+00:00'),
        'audio': '',
      });
      expect(unset.identity, isEmpty);
      expect(unset.hasAudio, isFalse);
      expect(LiveStation.isTrackExpired(unset), isTrue);
    });
  });
}
