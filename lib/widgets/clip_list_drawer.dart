// lib/widgets/clip_list_drawer.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/video_pair.dart';
import '../providers/app_providers.dart';

class ClipListDrawer extends ConsumerWidget {
  final void Function(int index) onSelect;
  const ClipListDrawer({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairs     = ref.watch(videoPairListProvider);
    final current   = ref.watch(currentIndexProvider);
    final sortOrder = ref.watch(sortOrderProvider);

    final paired    = pairs.where((p) => p.isPaired).length;
    final frontOnly = pairs.where((p) => p.hasFront && !p.hasBack).length;
    final backOnly  = pairs.where((p) => p.hasBack  && !p.hasFront).length;

    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: Column(children: [
        // Header
        Container(
          width:   double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
          color:   const Color(0xFF1A1A1A),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CLIPS',
                style: TextStyle(
                  color: Color(0xFF4FC3F7), fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 2,
                )),
              const SizedBox(height: 4),
              Text('${pairs.length} total',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Text(
                '$paired paired  •  $frontOnly front-only  •  $backOnly back-only',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 10),

              // Sort toggle inside drawer
              GestureDetector(
                onTap: () {
                  final next = sortOrder == SortOrder.oldestFirst
                      ? SortOrder.newestFirst
                      : SortOrder.oldestFirst;
                  ref.read(sortOrderProvider.notifier).state = next;
                  ref.read(videoPairListProvider.notifier).applySort(next);
                  ref.read(currentIndexProvider.notifier).state = 0;
                },
                child: Row(children: [
                  Icon(
                    sortOrder == SortOrder.oldestFirst
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: Colors.white38, size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    sortOrder == SortOrder.oldestFirst
                        ? 'Oldest first  (tap to reverse)'
                        : 'Newest first  (tap to reverse)',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11),
                  ),
                ]),
              ),
            ],
          ),
        ),

        // Clip list
        Expanded(
          child: pairs.isEmpty
              ? const Center(
                  child: Text(
                    'No clips loaded.\nOpen your dashcam drive.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ))
              : ListView.builder(
                  itemCount: pairs.length,
                  itemBuilder: (ctx, i) => _ClipTile(
                    pair:      pairs[i],
                    index:     i,
                    isCurrent: i == current,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      onSelect(i);
                    },
                  ),
                ),
        ),
      ]),
    );
  }
}

class _ClipTile extends StatelessWidget {
  final VideoPair    pair;
  final int          index;
  final bool         isCurrent;
  final VoidCallback onTap;

  const _ClipTile({
    required this.pair, required this.index,
    required this.isCurrent, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy  HH:mm:ss');

    return ListTile(
      onTap:     onTap,
      tileColor: isCurrent
          ? const Color(0xFF4FC3F7).withOpacity(0.1)
          : null,
      leading: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: isCurrent
              ? const Color(0xFF4FC3F7).withOpacity(0.2)
              : Colors.white10,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text('${index + 1}',
            style: TextStyle(
              color: isCurrent ? const Color(0xFF4FC3F7) : Colors.white38,
              fontSize: 12, fontWeight: FontWeight.w600,
            )),
        ),
      ),
      title: Text(
        fmt.format(pair.timestamp),
        style: TextStyle(
          color: isCurrent ? Colors.white : Colors.white70,
          fontSize: 13,
        ),
      ),
      subtitle: Row(children: [
        _badge(pair),
        if (pair.isLocked) ...[
          const SizedBox(width: 4),
          _pill('locked', Colors.red.shade300),
        ],
      ]),
      trailing: isCurrent
          ? const Icon(Icons.play_arrow_rounded,
              color: Color(0xFF4FC3F7), size: 18)
          : null,
    );
  }

  Widget _badge(VideoPair p) {
    if (p.isPaired)  return _pill('F+B',    const Color(0xFF4FC3F7));
    if (p.hasFront)  return _pill('F only', Colors.orange);
    return                  _pill('B only', Colors.purple);
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color:        color.withOpacity(0.15),
      border:       Border.all(color: color.withOpacity(0.4)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(text,
      style: TextStyle(
          color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );
}