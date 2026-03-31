// lib/widgets/app_notification.dart
//
// Top-right slide-in notification that auto-dismisses after 5 seconds.
// Replaces default SnackBar for a cleaner UX.

import 'package:flutter/material.dart';

/// Shows a top-right notification overlay on the given [context].
/// Auto-dismisses after [duration] (default 5 seconds).
/// Returns an [OverlayEntry] that can be removed early if needed.
OverlayEntry showAppNotification(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 5),
  IconData? icon,
  Color? color,
}) {
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _AppNotification(
      message: message,
      duration: duration,
      icon: icon,
      color: color,
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
  final Color? color;
  final VoidCallback onDismiss;

  const _AppNotification({
    required this.message,
    required this.duration,
    this.icon,
    this.color,
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

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? const Color(0xFF4FC3F7);
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
              constraints: const BoxConstraints(maxWidth: 400, minWidth: 200),
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(widget.icon ?? Icons.check_circle_rounded,
                    color: color, size: 18),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _dismiss,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded,
                        color: Colors.white38, size: 16),
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
