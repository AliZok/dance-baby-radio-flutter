import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'audio_service.dart' as app;

/// Bridges our custom [app.AudioService] (which manages the dual just_audio
/// players used for gapless track transitions) to the OS-level media
/// session via the `audio_service` package. This is what makes play/pause/
/// next/prev appear on the Android lock screen and notification shade.
class MediaAudioHandler extends BaseAudioHandler with SeekHandler {
  final app.AudioService _audioService;
  int? _lastMediaItemId;
  Duration _lastMediaDuration = Duration.zero;

  MediaAudioHandler(this._audioService) {
    _audioService.addListener(_broadcastState);
    _broadcastState();
  }

  void _broadcastState() {
    final track = _audioService.activeTrack;
    final sessionPlaying = _audioService.mediaSessionPlaying;
    final bufferingNext = _audioService.expectingPlayback &&
        (_audioService.isLoading || !_audioService.isPlaying);
    final duration = _audioService.duration;

    // Only push MediaItem when the track (or its duration) changes. Rewriting
    // it on every position tick can prevent OEMs from attaching lock-screen
    // transport controls reliably.
    final trackId = track?.id;
    if (trackId != _lastMediaItemId ||
        (duration - _lastMediaDuration).abs() > const Duration(milliseconds: 500)) {
      _lastMediaItemId = trackId;
      _lastMediaDuration = duration;
      mediaItem.add(MediaItem(
        id: trackId?.toString() ?? 'dance-baby-radio',
        album: 'Dance Baby Radio',
        title: track?.title ?? 'Dance Baby Radio',
        artist: (track?.artist.isNotEmpty == true)
            ? track!.artist
            : 'Dance Baby Radio',
        artUri: (track != null && track.cover.isNotEmpty)
            ? Uri.tryParse(track.cover)
            : null,
        duration: duration > Duration.zero ? duration : null,
        playable: true,
      ));
    }

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (sessionPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToPrevious,
        MediaAction.skipToNext,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: track == null
          ? AudioProcessingState.loading
          : bufferingNext
              ? AudioProcessingState.buffering
              : AudioProcessingState.ready,
      playing: sessionPlaying,
      updatePosition: _audioService.currentTime,
      bufferedPosition: _audioService.activePlayer.bufferedPosition,
      speed: _audioService.activePlayer.speed,
      queueIndex: 0,
      repeatMode: _audioService.isRepeat
          ? AudioServiceRepeatMode.one
          : AudioServiceRepeatMode.none,
    ));
  }

  @override
  Future<void> play() => _audioService.resumeAudio();

  @override
  Future<void> pause() => _audioService.pauseAudio();

  @override
  Future<void> stop() async {
    // Detach first so stopAudio()'s notifyListeners cannot overwrite the
    // idle processing state that clears the Android media notification.
    _audioService.removeListener(_broadcastState);
    await _audioService.stopAudio();
    await super.stop();
    // Re-attach so in-app play can restore lock-screen / notification controls
    // if the Flutter UI is still alive (e.g. user dismissed the notification).
    _audioService.addListener(_broadcastState);
  }

  /// User swiped the app away from Recents. Stop playback and tear down the
  /// media session / notification. Do NOT hook AppLifecycleState.paused —
  /// switching to Messages/etc. must keep background radio playing.
  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  @override
  Future<void> skipToNext() => _audioService.playNextMusic(fromUser: true);

  /// Prev control intentionally advances — same as Next for radio shuffle.
  @override
  Future<void> skipToPrevious() => _audioService.playNextMusic(fromUser: true);

  @override
  Future<void> rewind() async {
    final position = _audioService.currentTime - const Duration(seconds: 10);
    _audioService.seek(position.isNegative ? Duration.zero : position);
  }

  @override
  Future<void> fastForward() async {
    final target = _audioService.currentTime + const Duration(seconds: 10);
    final duration = _audioService.duration;
    _audioService.seek(
      duration > Duration.zero && target > duration ? duration : target,
    );
  }

  @override
  Future<void> seek(Duration position) async => _audioService.seek(position);

  void dispose() {
    _audioService.removeListener(_broadcastState);
  }
}

/// Ask Android 13+ for notification permission so the media-style notification
/// (and therefore lock-screen play/pause/next/prev) can actually appear.
Future<void> requestMediaNotificationPermission() async {
  if (!Platform.isAndroid) return;
  try {
    final status = await Permission.notification.status;
    if (status.isGranted || status.isLimited) return;
    await Permission.notification.request();
  } catch (e, st) {
    // Never block playback startup on a permission dialog failure.
    debugPrint('Notification permission request failed: $e\n$st');
  }
}
