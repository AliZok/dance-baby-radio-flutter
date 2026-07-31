import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoBackground extends StatefulWidget {
  final bool shouldShow;

  const VideoBackground({
    Key? key,
    required this.shouldShow,
  }) : super(key: key);

  @override
  _VideoBackgroundState createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<VideoBackground> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.shouldShow) {
      _initializeVideo();
    }
  }

  @override
  void didUpdateWidget(covariant VideoBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldShow && !_isInitialized) {
      _initializeVideo();
    } else if (!widget.shouldShow && _isInitialized) {
      _disposeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    const videoUrl = 'https://static.vecteezy.com/system/resources/previews/003/769/185/mp4/interstellar-space-travel-universe-to-the-m31-spiral-galaxy-free-video.mp4';
    _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    
    try {
      await _controller!.initialize();
      await _controller!.setVolume(0.0); // Muted
      await _controller!.setLooping(true);
      await _controller!.play();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('VideoBackground initialization failed: $e');
    }
  }

  void _disposeVideo() {
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.shouldShow || !_isInitialized || _controller == null) {
      return const SizedBox.shrink();
    }

    return Opacity(
      opacity: 0.5,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        ),
      ),
    );
  }
}
