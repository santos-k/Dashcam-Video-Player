// lib/widgets/layout_selector.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/layout_config.dart';
import '../providers/app_providers.dart';

Future<void> showLayoutSelector(BuildContext context) {
  return showModalBottomSheet(
    context:         context,
    backgroundColor: const Color(0xFF1E1E1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    isScrollControlled: true,
    builder: (_) => const _LayoutSheet(),
  );
}

class _LayoutSheet extends ConsumerWidget {
  const _LayoutSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config   = ref.watch(layoutConfigProvider);
    final notifier = ref.read(layoutConfigProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Drag handle
        Center(
          child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // ── Layout mode ────────────────────────────────
        const _Label('Layout'),
        const SizedBox(height: 10),
        Row(children: [
          _Chip(
            icon: Icons.view_column_rounded, label: 'Side by side',
            selected: config.mode == LayoutMode.sideBySide,
            onTap: () => notifier.state =
                config.copyWith(mode: LayoutMode.sideBySide),
          ),
          const SizedBox(width: 8),
          _Chip(
            icon: Icons.view_stream_rounded, label: 'Stacked',
            selected: config.mode == LayoutMode.stacked,
            onTap: () => notifier.state =
                config.copyWith(mode: LayoutMode.stacked),
          ),
          const SizedBox(width: 8),
          _Chip(
            icon: Icons.picture_in_picture_alt_rounded, label: 'PIP',
            selected: config.mode == LayoutMode.pip,
            onTap: () => notifier.state =
                config.copyWith(mode: LayoutMode.pip),
          ),
        ]),

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
                        // Reset drag position so it snaps to new grid cell
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
      ]),
    );
  }

  void _resetPipOffset(WidgetRef ref) {
    // Notify DualVideoView to recalculate position from alignment
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
  final bool       selected;
  final VoidCallback onTap;

  const _Chip({
    required this.icon, required this.label,
    required this.selected, required this.onTap,
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
          Text(label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white54,
              fontSize: 13,
            )),
        ]),
      ),
    );
  }
}