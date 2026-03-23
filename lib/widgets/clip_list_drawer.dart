// lib/widgets/clip_list_drawer.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/video_pair.dart';
import '../providers/app_providers.dart';

class ClipListDrawer extends ConsumerWidget {
  const ClipListDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairs   = ref.watch(videoPairListProvider);
    final current = ref.watch(currentIndexProvider);

    final paired    = pairs.where((p) => p.isPaired).length;
    final frontOnly = pairs.where((p) => p.hasFront && !p.hasBack).length;
    final backOnly  = pairs.where((p) => p.hasBack  && !p.hasFront).length;

    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: Column(
        children: [
          Container(
            width:   double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            color:   const Color(0xFF1A1A1A),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CLIPS',
                  style: TextStyle(
                    color: Color(0xFF4FC3F7), fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${pairs.length} total',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '$paired paired  •  $frontOnly front-only  •  $backOnly back-only',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          Expanded(
            child: pairs.isEmpty
                ? const Center(
                    child: Text(
                      'No clips loaded.\nOpen your dashcam drive.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: pairs.length,
                    itemBuilder: (ctx, i) => _ClipTile(
                      pair:      pairs[i],
                      index:     i,
                      isCurrent: i == current,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _loadClip(ref, i);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _loadClip(WidgetRef ref, int index) {
    final pairs = ref.read(videoPairListProvider);
    ref.read(currentIndexProvider.notifier).state = index;
    ref.read(syncOffsetProvider.notifier).state   = 0;
    ref.read(playbackProvider.notifier).loadPair(pairs[index], 0);
  }
}

class _ClipTile extends StatelessWidget {
  final VideoPair  pair;
  final int        index;
  final bool       isCurrent;
  final VoidCallback onTap;

  const _ClipTile({
    required this.pair,
    required this.index,
    required this.isCurrent,
    required this.onTap,
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
          child: Text(
            '${index + 1}',
            style: TextStyle(
              color: isCurrent ? const Color(0xFF4FC3F7) : Colors.white38,
              fontSize: 12, fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      title: Text(
        fmt.format(pair.timestamp),
        style: TextStyle(
          color: isCurrent ? Colors.white : Colors.white70,
          fontSize: 13,
        ),
      ),
      subtitle: Row(
        children: [
          // Paired / single indicator
          if (pair.isPaired)
            _Badge('F+B', const Color(0xFF4FC3F7))
          else if (pair.hasFront)
            _Badge('F only', Colors.orange)
          else
            _Badge('B only', Colors.purple),
          // Lock indicator
          if (pair.isLocked) ...[
            const SizedBox(width: 4),
            _Badge('🔒 locked', Colors.red.shade300),
          ],
        ],
      ),
      trailing: isCurrent
          ? const Icon(Icons.play_arrow_rounded,
              color: Color(0xFF4FC3F7), size: 18)
          : null,
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color  color;
  const _Badge(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.15),
        border:       Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}