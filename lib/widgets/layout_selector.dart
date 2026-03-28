// lib/widgets/layout_selector.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/layout_config.dart';
import '../providers/app_providers.dart';

/// Show the layout popup anchored above [anchorRect] with a bottom-to-top slide.
Future<void> showLayoutPopup(BuildContext context, {required Rect anchorRect}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Layout',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (ctx, anim, _, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: FadeTransition(opacity: anim, child: child),
      );
    },
    pageBuilder: (ctx, _, __) {
      final screenW = MediaQuery.of(ctx).size.width;
      final screenH = MediaQuery.of(ctx).size.height;
      const popupW  = 320.0;

      // Centre on anchor, but clamp to screen edges
      double left = (anchorRect.left + anchorRect.right) / 2 - popupW / 2;
      left = left.clamp(8.0, screenW - popupW - 8);

      final bottom = screenH - anchorRect.top + 8;

      return Stack(
        children: [
          Positioned(
            left: left,
            bottom: bottom,
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: popupW,
                child: _LayoutPanel(onClose: () => Navigator.of(ctx).pop()),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _LayoutPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const _LayoutPanel({required this.onClose});

  @override
  ConsumerState<_LayoutPanel> createState() => _LayoutPanelState();
}

class _LayoutPanelState extends ConsumerState<_LayoutPanel> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    final config   = ref.read(layoutConfigProvider);
    final notifier = ref.read(layoutConfigProvider.notifier);

    if (key == LogicalKeyboardKey.digit1) {
      notifier.state = config.copyWith(mode: LayoutMode.sideBySide);
    } else if (key == LogicalKeyboardKey.digit2) {
      notifier.state = config.copyWith(mode: LayoutMode.stacked);
    } else if (key == LogicalKeyboardKey.digit3) {
      notifier.state = config.copyWith(mode: LayoutMode.pip);
    } else if (key == LogicalKeyboardKey.escape ||
               key == LogicalKeyboardKey.keyL) {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final config   = ref.watch(layoutConfigProvider);
    final notifier = ref.read(layoutConfigProvider.notifier);

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Layout mode ────────────────────────────────
            const _Label('Layout'),
            const SizedBox(height: 10),
            _Chip(
              icon: Icons.view_column_rounded, label: 'Side by side',
              shortcut: '1',
              selected: config.mode == LayoutMode.sideBySide,
              onTap: () => notifier.state =
                  config.copyWith(mode: LayoutMode.sideBySide),
            ),
            const SizedBox(height: 6),
            _Chip(
              icon: Icons.view_stream_rounded, label: 'Stacked',
              shortcut: '2',
              selected: config.mode == LayoutMode.stacked,
              onTap: () => notifier.state =
                  config.copyWith(mode: LayoutMode.stacked),
            ),
            const SizedBox(height: 6),
            _Chip(
              icon: Icons.picture_in_picture_alt_rounded, label: 'PIP',
              shortcut: '3',
              selected: config.mode == LayoutMode.pip,
              onTap: () => notifier.state =
                  config.copyWith(mode: LayoutMode.pip),
            ),

            // ── PIP options ────────────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: config.mode != LayoutMode.pip
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),

                        // Primary video
                        const _Label('Primary video (large)'),
                        const SizedBox(height: 10),
                        Row(children: [
                          _Chip(
                            icon: Icons.camera_front_rounded, label: 'Front',
                            selected: config.pipPrimary == PipPrimary.front,
                            onTap: () => notifier.state =
                                config.copyWith(pipPrimary: PipPrimary.front),
                          ),
                          const SizedBox(width: 8),
                          _Chip(
                            icon: Icons.camera_rear_rounded, label: 'Back',
                            selected: config.pipPrimary == PipPrimary.back,
                            onTap: () => notifier.state =
                                config.copyWith(pipPrimary: PipPrimary.back),
                          ),
                        ]),

                        const SizedBox(height: 20),
                        const _Label('Default PIP position'),
                        const SizedBox(height: 4),
                        const Text(
                          'You can also drag the PIP window freely. '
                          'This snaps it to a grid position.',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                        const SizedBox(height: 12),

                        // 3×3 position grid
                        _PositionGrid(
                          hAlign: config.pipHAlign,
                          vAlign: config.pipVAlign,
                          onSelect: (h, v) {
                            notifier.state = config.copyWith(
                              pipHAlign: h, pipVAlign: v);
                            _resetPipOffset(ref);
                          },
                        ),

                        const SizedBox(height: 20),
                        const _Label('Horizontal position'),
                        const SizedBox(height: 10),
                        Row(children: [
                          _Chip(
                            icon: Icons.align_horizontal_left_rounded,
                            label: 'Left',
                            selected: config.pipHAlign == PipHAlign.left,
                            onTap: () {
                              notifier.state = config.copyWith(pipHAlign: PipHAlign.left);
                              _resetPipOffset(ref);
                            },
                          ),
                          const SizedBox(width: 8),
                          _Chip(
                            icon: Icons.align_horizontal_center_rounded,
                            label: 'Center',
                            selected: config.pipHAlign == PipHAlign.center,
                            onTap: () {
                              notifier.state = config.copyWith(pipHAlign: PipHAlign.center);
                              _resetPipOffset(ref);
                            },
                          ),
                          const SizedBox(width: 8),
                          _Chip(
                            icon: Icons.align_horizontal_right_rounded,
                            label: 'Right',
                            selected: config.pipHAlign == PipHAlign.right,
                            onTap: () {
                              notifier.state = config.copyWith(pipHAlign: PipHAlign.right);
                              _resetPipOffset(ref);
                            },
                          ),
                        ]),

                        const SizedBox(height: 16),
                        const _Label('Vertical position'),
                        const SizedBox(height: 10),
                        Row(children: [
                          _Chip(
                            icon: Icons.vertical_align_top_rounded,
                            label: 'Top',
                            selected: config.pipVAlign == PipVAlign.top,
                            onTap: () {
                              notifier.state = config.copyWith(pipVAlign: PipVAlign.top);
                              _resetPipOffset(ref);
                            },
                          ),
                          const SizedBox(width: 8),
                          _Chip(
                            icon: Icons.vertical_align_center_rounded,
                            label: 'Center',
                            selected: config.pipVAlign == PipVAlign.center,
                            onTap: () {
                              notifier.state = config.copyWith(pipVAlign: PipVAlign.center);
                              _resetPipOffset(ref);
                            },
                          ),
                          const SizedBox(width: 8),
                          _Chip(
                            icon: Icons.vertical_align_bottom_rounded,
                            label: 'Bottom',
                            selected: config.pipVAlign == PipVAlign.bottom,
                            onTap: () {
                              notifier.state = config.copyWith(pipVAlign: PipVAlign.bottom);
                              _resetPipOffset(ref);
                            },
                          ),
                        ]),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetPipOffset(WidgetRef ref) {
    ref.read(pipResetProvider.notifier).state++;
  }
}


// ─── 3×3 grid picker ─────────────────────────────────────────────────────────

class _PositionGrid extends StatelessWidget {
  final PipHAlign hAlign;
  final PipVAlign vAlign;
  final void Function(PipHAlign, PipVAlign) onSelect;

  const _PositionGrid({
    required this.hAlign,
    required this.vAlign,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final hAligns = [PipHAlign.left, PipHAlign.center, PipHAlign.right];
    final vAligns = [PipVAlign.top, PipVAlign.center, PipVAlign.bottom];

    return Container(
      width:   150,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border:       Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: vAligns.map((v) => Row(
          children: hAligns.map((h) {
            final selected = hAlign == h && vAlign == v;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelect(h, v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: 36,
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF4FC3F7)
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF4FC3F7)
                          : Colors.white12,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.picture_in_picture_alt_rounded,
                          color: Colors.black, size: 14)
                      : null,
                ),
              ),
            );
          }).toList(),
        )).toList(),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(
      color: Colors.white54, fontSize: 11,
      fontWeight: FontWeight.w600, letterSpacing: 0.8,
    ));
}

class _Chip extends StatelessWidget {
  final IconData   icon;
  final String     label;
  final String?    shortcut;
  final bool       selected;
  final VoidCallback onTap;

  const _Chip({
    required this.icon, required this.label,
    required this.selected, required this.onTap,
    this.shortcut,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:  selected
              ? const Color(0xFF4FC3F7).withValues(alpha: 0.15)
              : Colors.white10,
          border: Border.all(
            color: selected ? const Color(0xFF4FC3F7) : Colors.transparent,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
            color: selected ? const Color(0xFF4FC3F7) : Colors.white54,
            size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white54,
                fontSize: 13,
              )),
          ),
          if (shortcut != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(shortcut!,
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ),
          ],
        ]),
      ),
    );
  }
}
