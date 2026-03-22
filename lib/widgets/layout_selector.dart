// lib/widgets/layout_selector.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/layout_config.dart';
import '../providers/app_providers.dart';

/// Shows a bottom sheet with layout mode, PIP primary, and PIP corner choices.
void showLayoutSelector(BuildContext context) {
  showModalBottomSheet(
    context:           context,
    backgroundColor:   const Color(0xFF1E1E1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _LayoutSheet(),
  );
}

class _LayoutSheet extends ConsumerWidget {
  const _LayoutSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(layoutConfigProvider);
    final notifier = ref.read(layoutConfigProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Layout mode ────────────────────────────────
          const _SectionLabel('Layout'),
          const SizedBox(height: 10),
          Row(
            children: [
              _LayoutChip(
                label:    'Side by side',
                icon:     Icons.view_column_rounded,
                selected: config.mode == LayoutMode.sideBySide,
                onTap:    () => notifier.state =
                    config.copyWith(mode: LayoutMode.sideBySide),
              ),
              const SizedBox(width: 8),
              _LayoutChip(
                label:    'Stacked',
                icon:     Icons.view_stream_rounded,
                selected: config.mode == LayoutMode.stacked,
                onTap:    () => notifier.state =
                    config.copyWith(mode: LayoutMode.stacked),
              ),
              const SizedBox(width: 8),
              _LayoutChip(
                label:    'PIP',
                icon:     Icons.picture_in_picture_alt_rounded,
                selected: config.mode == LayoutMode.pip,
                onTap:    () => notifier.state =
                    config.copyWith(mode: LayoutMode.pip),
              ),
            ],
          ),

          // ── PIP options (only visible in PIP mode) ─────
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: config.mode == LayoutMode.pip
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      const _SectionLabel('Primary video'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _LayoutChip(
                            label: 'Front',
                            icon: Icons.camera_front_rounded,
                            selected: config.pipPrimary == PipPrimary.front,
                            onTap: () => notifier.state =
                                config.copyWith(pipPrimary: PipPrimary.front),
                          ),
                          const SizedBox(width: 8),
                          _LayoutChip(
                            label: 'Back',
                            icon: Icons.camera_rear_rounded,
                            selected: config.pipPrimary == PipPrimary.back,
                            onTap: () => notifier.state =
                                config.copyWith(pipPrimary: PipPrimary.back),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const _SectionLabel('PIP corner'),
                      const SizedBox(height: 10),
                      _PipCornerPicker(
                        selected: config.pipCorner,
                        onSelect: (c) => notifier.state =
                            config.copyWith(pipCorner: c),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─── PIP corner 2×2 grid picker ──────────────────────────────────────────────

class _PipCornerPicker extends StatelessWidget {
  final PipCorner selected;
  final ValueChanged<PipCorner> onSelect;

  const _PipCornerPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  140,
      height: 90,
      decoration: BoxDecoration(
        border:       Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: GridView.count(
        crossAxisCount: 2,
        physics:        const NeverScrollableScrollPhysics(),
        children: [
          _cornerDot(PipCorner.topLeft,     Alignment.topLeft),
          _cornerDot(PipCorner.topRight,    Alignment.topRight),
          _cornerDot(PipCorner.bottomLeft,  Alignment.bottomLeft),
          _cornerDot(PipCorner.bottomRight, Alignment.bottomRight),
        ],
      ),
    );
  }

  Widget _cornerDot(PipCorner corner, Alignment alignment) {
    final isSel = selected == corner;
    return GestureDetector(
      onTap: () => onSelect(corner),
      child: Container(
        color: Colors.transparent,
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Container(
              width:  16,
              height: 16,
              decoration: BoxDecoration(
                color:        isSel
                    ? const Color(0xFF4FC3F7)
                    : Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color:      Colors.white54,
        fontSize:   12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _LayoutChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _LayoutChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:  selected
              ? const Color(0xFF4FC3F7).withOpacity(0.15)
              : Colors.white10,
          border: Border.all(
            color: selected ? const Color(0xFF4FC3F7) : Colors.transparent,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? const Color(0xFF4FC3F7) : Colors.white54, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color:    selected ? Colors.white : Colors.white54,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}