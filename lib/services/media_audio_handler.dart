import 'package:audio_service/audio_service.dart';
import 'audio_service.dart' as app;

/// Bridges our custom [app.AudioService] (which manages the dual just_audio
/// players used for gapless track transitions) to the OS-level media
/// session via the `audio_service` package. This is what makes play/pause/
/// next work from the Android lock screen and notification shade, exactly
/// like a native music app.
class MediaAudioHandler extends BaseAudioHandler with SeekHandler {
  final app.AudioService _audioService;

  MediaAudioHandler(this._audioService) {
    _audioService.addListener(_broadcastState);
    _broadcastState();
  }

  void _broadcastState() {
    final track = _audioService.activeTrack;
    final playing = _audioService.isPlaying;

    mediaItem.add(MediaItem(
      id: track?.id.toString() ?? 'dance-baby-radio',
      title: track?.title ?? 'Dance Baby Radio',
      artist: (track?.artist.isNotEmpty == true) ? track!.artist : 'Dance Baby Radio',
      artUri: (track != null && track.cover.isNotEmpty) ? Uri.tryParse(track.cover) : null,
      duration: _audioService.duration,
    ));

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekBackward,
        MediaAction.seekForward,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToPrevious,
        MediaAction.skipToNext,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: track == null
          ? AudioProcessingState.loading
          : _audioService.isLoading
              ? AudioProcessingState.buffering
              : AudioProcessingState.ready,
      playing: playing,
      updatePosition: _audioService.currentTime,
      bufferedPosition: _audioService.activePlayer.bufferedPosition,
      speed: _audioService.activePlayer.speed,
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
    await _audioService.pauseAudio();
    await super.stop();
  }

  @override
  Future<void> skipToNext() => _audioService.playNextMusic();

  @override
  Future<void> skipToPrevious() => _audioService.playNextMusic();

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
