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
  bool _isInitializing = false;

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
    if (widget.shouldShow && !_isInitialized && !_isInitializing) {
      _initializeVideo();
    } else if (!widget.shouldShow &&
        (_isInitialized || _isInitializing || _controller != null)) {
      _disposeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    if (_isInitializing || _isInitialized) return;
    _isInitializing = true;
    const videoUrl = 'https://static.vecteezy.com/system/resources/previews/003/769/185/mp4/interstellar-space-travel-universe-to-the-m31-spiral-galaxy-free-video.mp4';
    final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    _controller = controller;
    
    try {
      await controller.initialize();
      await controller.setVolume(0.0);
      await controller.setLooping(true);
      if (!mounted || !widget.shouldShow || _controller != controller) {
        await controller.dispose();
        return;
      }
      await controller.play();
      if (mounted && _controller == controller) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('VideoBackground initialization failed: $e');
    } finally {
      _isInitializing = false;
    }
  }

  void _disposeVideo() {
    final controller = _controller;
    _controller = null;
    _isInitialized = false;
    _isInitializing = false;
    controller?.pause();
    controller?.dispose();
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
