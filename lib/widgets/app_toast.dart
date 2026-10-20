import 'dart:async';

import 'package:flutter/material.dart';

/// Severity of a notification, mirroring the Nuxt `useToast()` variants
/// (`toast.info` / `success` / `warning` / `error`).
enum AppToastKind { info, success, warning, error }

class _ToastModel {
  _ToastModel({
    required this.id,
    required this.kind,
    required this.title,
    required this.message,
    required this.highlight,
    required this.duration,
  });

  final int id;
  final AppToastKind kind;
  final String? title;
  final String message;

  /// Substring rendered in the accent colour, like Nuxt `options.highlight`.
  final String? highlight;

  /// `null` / zero means the card stays until dismissed (web `duration: 0`).
  final Duration? duration;

  /// Set when the card should animate out; the widget then drops itself.
  bool dismissRequested = false;
}

/// Global notification stack matching Nuxt `components/NotificationStack`:
/// cards appear under the status bar, several can stack at once, each has a
/// type icon / coloured border, an auto-dismiss progress bar, a close button,
/// and the countdown pauses while the user touches (or hovers) the card.
class AppToast {
  AppToast._();

  static const Duration _defaultDuration = Duration(milliseconds: 4500);
  static const Duration _exitDuration = Duration(milliseconds: 280);

  static final List<_ToastModel> _toasts = [];
  static OverlayEntry? _entry;
  static int _seed = 0;

  static void show(
    BuildContext context, {
    required String message,
    String? title,
    AppToastKind kind = AppToastKind.info,
    String? highlight,
    Duration? duration = _defaultDuration,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _toasts.add(
      _ToastModel(
        id: ++_seed,
        kind: kind,
        title: title,
        message: message,
        highlight: highlight,
        duration: duration,
      ),
    );

    if (_entry == null) {
      _entry = OverlayEntry(builder: (_) => _AppToastStack());
      overlay.insert(_entry!);
    } else {
      _entry!.markNeedsBuild();
    }
  }

  static void info(
    BuildContext context,
    String message, {
    String? title,
    String? highlight,
    Duration? duration = _defaultDuration,
  }) {
    show(
      context,
      message: message,
      title: title,
      highlight: highlight,
      duration: duration,
    );
  }

  static void success(
    BuildContext context,
    String message, {
    String? title,
    String? highlight,
    Duration? duration = _defaultDuration,
  }) {
    show(
      context,
      message: message,
      title: title,
      highlight: highlight,
      duration: duration,
      kind: AppToastKind.success,
    );
  }

  static void warning(
    BuildContext context,
    String message, {
    String? title,
    String? highlight,
    Duration? duration = _defaultDuration,
  }) {
    show(
      context,
      message: message,
      title: title,
      highlight: highlight,
      duration: duration,
      kind: AppToastKind.warning,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    String? title,
    String? highlight,
    Duration? duration = _defaultDuration,
  }) {
    show(
      context,
      message: message,
      title: title,
      highlight: highlight,
      duration: duration,
      kind: AppToastKind.error,
    );
  }

  /// Animated removal: mark the model, the card collapses and drops itself.
  static void dismiss(int id) {
    for (final toast in _toasts) {
      if (toast.id == id) {
        toast.dismissRequested = true;
        _entry?.markNeedsBuild();
        return;
      }
    }
  }

  static void clear() {
    _toasts.clear();
    _entry?.remove();
    _entry = null;
  }

  static void _drop(int id) {
    _toasts.removeWhere((toast) => toast.id == id);
    if (_toasts.isEmpty) {
      _entry?.remove();
      _entry = null;
    } else {
      _entry?.markNeedsBuild();
    }
  }
}

class _AppToastStack extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top + 14;
    // Deferred hit-testing: the empty area around the cards never swallows
    // taps, so notifications can sit over the player without blocking it.
    return Stack(
      alignment: Alignment.topRight,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, topInset, 16, 16),
          // Nuxt: width min(380px, calc(100vw - 32px)).
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < AppToast._toasts.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _ToastCard(
                    key: ValueKey(AppToast._toasts[i].id),
                    toast: AppToast._toasts[i],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({required super.key, required this.toast});

  final _ToastModel toast;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _countdown;
  Timer? _dropTimer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    final duration = widget.toast.duration;
    if (duration != null && duration > Duration.zero) {
      // The countdown animation is the single source of truth: pausing it
      // pauses the auto-dismiss too (Nuxt hover → `animation-play-state`).
      _countdown = AnimationController(
        vsync: this,
        lowerBound: 0,
        upperBound: 1,
        value: 1,
      )
        ..addListener(_onCountdownTick)
        ..animateTo(0, duration: duration);
    }
  }

  void _onCountdownTick() {
    if ((widget.toast.duration ?? Duration.zero) <= Duration.zero) return;
    if (_countdown!.value > _countdown!.lowerBound) return;
    _startExit();
  }

  void _startExit() {
    if (_leaving) return;
    _leaving = true;
    widget.toast.dismissRequested = true;
    if (mounted) setState(() {});
    _dropTimer = Timer(AppToast._exitDuration, () {
      AppToast._drop(widget.toast.id);
    });
  }

  void _pause() => _countdown?.stop();

  void _resume() {
    final controller = _countdown;
    final duration = widget.toast.duration;
    if (controller == null || duration == null) return;
    if (controller.isAnimating) return;
    if (controller.value <= controller.lowerBound) {
      _startExit();
      return;
    }
    controller.animateTo(
      0,
      duration: duration * controller.value,
    );
  }

  @override
  void dispose() {
    _dropTimer?.cancel();
    _countdown
      ?..removeListener(_onCountdownTick)
      ..dispose();
    super.dispose();
  }

  Color get _accentColor {
    switch (widget.toast.kind) {
      case AppToastKind.success:
        return const Color(0xFF64EEB4);
      case AppToastKind.error:
        return const Color(0xFFFF6B8A);
      case AppToastKind.warning:
        return const Color(0xFFFFD060);
      case AppToastKind.info:
        return const Color(0xFF84F3FF);
    }
  }

  IconData get _icon {
    switch (widget.toast.kind) {
      case AppToastKind.success:
        return Icons.check_circle_outline;
      case AppToastKind.error:
        return Icons.cancel_outlined;
      case AppToastKind.warning:
        return Icons.error_outline;
      case AppToastKind.info:
        return Icons.info_outline;
    }
  }

  /// Nuxt `splitHighlight()` — the accent word inside the message body.
  Widget _buildMessage() {
    final highlight = widget.toast.highlight;
    final style = TextStyle(
      fontSize: 13,
      height: 1.5,
      color: const Color(0xFFE8FBFF).withOpacity(0.92),
    );
    if (highlight == null || highlight.isEmpty || !widget.toast.message.contains(highlight)) {
      return Text(widget.toast.message, style: style);
    }

    final parts = <InlineSpan>[];
    var remaining = widget.toast.message;
    while (remaining.isNotEmpty) {
      final at = remaining.indexOf(highlight);
      if (at == -1) {
        parts.add(TextSpan(text: remaining));
        break;
      }
      if (at > 0) parts.add(TextSpan(text: remaining.substring(0, at)));
      parts.add(
        TextSpan(
          text: highlight,
          style: const TextStyle(color: Color(0xFF84F3FF), fontWeight: FontWeight.w600),
        ),
      );
      remaining = remaining.substring(at + highlight.length);
    }
    return RichText(text: TextSpan(style: style, children: parts));
  }

  List<Color> get _progressColors {
    switch (widget.toast.kind) {
      case AppToastKind.success:
        return const [Color(0xFF64EEB4), Color(0x7364EEB4)];
      case AppToastKind.error:
        return const [Color(0xFFFF6B8A), Color(0x73FF6B8A)];
      case AppToastKind.warning:
        return const [Color(0xFFFFD060), Color(0x73FFD060)];
      case AppToastKind.info:
        return const [Color(0xF284F3FF), Color(0x8C58D1EF)];
    }
  }

  Widget _buildProgressBar() {
    final controller = _countdown;
    if (controller == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 2,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) => Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: controller.value.clamp(0.0, 1.0),
            child: child,
          ),
        ),
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: _progressColors),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final leaving = _leaving || widget.toast.dismissRequested;
    final accent = _accentColor;

    return MouseRegion(
      onEnter: (_) => _pause(),
      onExit: (_) => _resume(),
      child: GestureDetector(
        // Touch has no hover: hold the card to keep it on screen.
        onTapDown: (_) => _pause(),
        onTapUp: (_) => _resume(),
        onTapCancel: _resume,
        child: AnimatedOpacity(
          duration: AppToast._exitDuration,
          opacity: leaving ? 0 : 1,
          child: AnimatedSlide(
            duration: AppToast._exitDuration,
            offset: leaving ? const Offset(0.06, 0) : Offset.zero,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xF0061C22),
                borderRadius: BorderRadius.circular(12),
                border: Border.fromBorderSide(
                  BorderSide(color: accent.withOpacity(0.4)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.45),
                    blurRadius: 36,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 40, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_icon, size: 22, color: accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.toast.title != null &&
                                  widget.toast.title!.isNotEmpty) ...[
                                Text(
                                  widget.toast.title!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                    color: Color(0xFFD8F6FF),
                                  ),
                                ),
                                const SizedBox(height: 3),
                              ],
                              _buildMessage(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Nuxt `.notify-card__close` — top-right, 26×26, 14px glyph.
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _startExit,
                      child: const SizedBox(
                        width: 26,
                        height: 26,
                        child: Center(
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: Color(0x8CE8FBFF),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _buildProgressBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
