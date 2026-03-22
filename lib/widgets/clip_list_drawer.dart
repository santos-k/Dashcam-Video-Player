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

    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: Column(
        children: [
          // Header
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
                    color:      Color(0xFF4FC3F7),
                    fontSize:   11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${pairs.length} paired set${pairs.length != 1 ? "s" : ""}',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
          ),

          // Clip list
          Expanded(
            child: pairs.isEmpty
                ? const Center(
                    child: Text(
                      'No clips loaded.\nUse the folder icon to open a directory.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: pairs.length,
                    itemBuilder: (ctx, i) => _ClipTile(
                      pair:       pairs[i],
                      index:      i,
                      isCurrent:  i == current,
                      onTap: () {
                        Navigator.of(ctx).pop(); // close drawer
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
  final VideoPair pair;
  final int index;
  final bool isCurrent;
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
      onTap:       onTap,
      tileColor:   isCurrent ? const Color(0xFF4FC3F7).withOpacity(0.1) : null,
      leading: Container(
        width:  32,
        height: 32,
        decoration: BoxDecoration(
          color:        isCurrent
              ? const Color(0xFF4FC3F7).withOpacity(0.2)
              : Colors.white10,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: TextStyle(
              color:      isCurrent
                  ? const Color(0xFF4FC3F7)
                  : Colors.white38,
              fontSize:   12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      title: Text(
        fmt.format(pair.timestamp),
        style: TextStyle(
          color:    isCurrent ? Colors.white : Colors.white70,
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        pair.id,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: isCurrent
          ? const Icon(Icons.play_arrow_rounded,
              color: Color(0xFF4FC3F7), size: 18)
          : null,
    );
  }
}