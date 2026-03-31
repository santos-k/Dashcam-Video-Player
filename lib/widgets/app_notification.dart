// lib/widgets/app_notification.dart
//
// Top-right slide-in notification with solid color background.
// Green = success, Red = error, Yellow/Amber = warning.

import 'package:flutter/material.dart';

enum NotificationType { success, error, warning }

/// Shows a top-right notification overlay.
/// Auto-dismisses after [duration] (default 5 seconds).
OverlayEntry showAppNotification(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 5),
  IconData? icon,
  Color? color,
  NotificationType type = NotificationType.success,
}) {
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _AppNotification(
      message: message,
      duration: duration,
      icon: icon,
      type: type,
      colorOverride: color,
      onDismiss: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  Overlay.of(context).insert(entry);
  return entry;
}

class _AppNotification extends StatefulWidget {
  final String message;
  final Duration duration;
  final IconData? icon;
  final NotificationType type;
  final Color? colorOverride;
  final VoidCallback onDismiss;

  const _AppNotification({
    required this.message,
    required this.duration,
    this.icon,
    required this.type,
    this.colorOverride,
    required this.onDismiss,
  });

  @override
  State<_AppNotification> createState() => _AppNotificationState();
}

class _AppNotificationState extends State<_AppNotification>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slide = Tween(
      begin: const Offset(1.0, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _fade = Tween(begin: 0.0, end: 1.0).animate(_anim);

    _anim.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  void _dismiss() async {
    if (!mounted) return;
    await _anim.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  (Color bg, IconData icon) get _style {
    if (widget.colorOverride == Colors.redAccent ||
        widget.type == NotificationType.error) {
      return (const Color(0xFFE53935), widget.icon ?? Icons.error_rounded);
    }
    if (widget.colorOverride == Colors.orange ||
        widget.colorOverride == Colors.amber ||
        widget.type == NotificationType.warning) {
      return (const Color(0xFFFFA726), widget.icon ?? Icons.warning_rounded);
    }
    return (const Color(0xFF43A047), widget.icon ?? Icons.check_circle_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final (bgColor, iconData) = _style;

    return Positioned(
      top: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420, minWidth: 180),
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: bgColor.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(iconData, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _dismiss,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded,
                        color: Colors.white.withValues(alpha: 0.8), size: 18),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
