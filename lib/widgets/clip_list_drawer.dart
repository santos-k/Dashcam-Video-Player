// lib/widgets/clip_list_drawer.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/shortcut_action.dart';
import '../models/video_pair.dart';
import '../providers/app_providers.dart';
import '../services/thumbnail_service.dart';

class ClipListDrawer extends ConsumerStatefulWidget {
  final void Function(int index) onSelect;
  final VoidCallback? onSave;
  final void Function(Set<int> indices)? onDelete;
  const ClipListDrawer({
    super.key,
    required this.onSelect,
    this.onSave,
    this.onDelete,
  });

  @override
  ConsumerState<ClipListDrawer> createState() => _ClipListDrawerState();
}

class _ClipListDrawerState extends ConsumerState<ClipListDrawer> {
  ScrollController _scrollController = ScrollController();

  // Approximate heights for scroll offset calculation
  static const double _listTileHeight = 64.0;
  static const double _gridRowHeight  = 140.0;

  ClipViewMode? _lastViewMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentClip(animate: true));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentClip({bool animate = false}) {
    if (!_scrollController.hasClients) return;
    final current  = ref.read(currentIndexProvider);
    final viewMode = ref.read(clipViewModeProvider);
    final viewportH = _scrollController.position.viewportDimension;

    double itemOffset;
    if (viewMode == ClipViewMode.thumbnail) {
      final row = current ~/ 2;
      itemOffset = row * (_gridRowHeight + 6);
    } else {
      itemOffset = current * _listTileHeight;
    }

    // Center the item in the viewport
    final offset = (itemOffset - viewportH / 2 + _listTileHeight / 2)
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    if (animate) {
      _scrollController.animateTo(offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic);
    } else {
      _scrollController.jumpTo(offset);
    }
  }

  void _toggleSelection(Set<int> current, int index) {
    final updated = Set.of(current);
    if (updated.contains(index)) {
      updated.remove(index);
    } else {
      updated.add(index);
    }
    ref.read(selectedClipIndicesProvider.notifier).state = updated;
  }

  void _enterSelectMode(int index) {
    ref.read(clipSelectionModeProvider.notifier).state = true;
    ref.read(selectedClipIndicesProvider.notifier).state = {index};
  }

  @override
  Widget build(BuildContext context) {
    final pairs        = ref.watch(videoPairListProvider);
    final current      = ref.watch(currentIndexProvider);
    final sortOrder    = ref.watch(sortOrderProvider);
    final viewMode     = ref.watch(clipViewModeProvider);
    final selectMode   = ref.watch(clipSelectionModeProvider);
    final selected     = ref.watch(selectedClipIndicesProvider);

    final paired    = pairs.where((p) => p.isPaired).length;
    final frontOnly = pairs.where((p) => p.hasFront && !p.hasBack).length;
    final backOnly  = pairs.where((p) => p.hasBack  && !p.hasFront).length;

    // When view mode switches, the old ScrollController detaches. Create a
    // fresh one so the new list/grid starts at the right position instantly.
    if (_lastViewMode != null && _lastViewMode != viewMode) {
      _scrollController.dispose();
      _scrollController = ScrollController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentClip();
      });
    }
    _lastViewMode = viewMode;

    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: Column(children: [
        // ── Header ──
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

              // Sort dropdown
              Row(children: [
                const Icon(Icons.sort_rounded, color: Colors.white38, size: 14),
                const SizedBox(width: 4),
                DropdownButton<SortOrder>(
                  value: sortOrder,
                  dropdownColor: const Color(0xFF222222),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                  underline: const SizedBox(),
                  isDense: true,
                  items: const [
                    DropdownMenuItem(value: SortOrder.oldestFirst, child: Text('Date (oldest)')),
                    DropdownMenuItem(value: SortOrder.newestFirst, child: Text('Date (newest)')),
                    DropdownMenuItem(value: SortOrder.nameAZ, child: Text('Name (A-Z)')),
                    DropdownMenuItem(value: SortOrder.nameZA, child: Text('Name (Z-A)')),
                    DropdownMenuItem(value: SortOrder.longestFirst, child: Text('Duration (longest)')),
                    DropdownMenuItem(value: SortOrder.shortestFirst, child: Text('Duration (shortest)')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    ref.read(sortOrderProvider.notifier).state = v;
                    final notifier = ref.read(videoPairListProvider.notifier);
                    notifier.setDurationCache(ref.read(clipDurationCacheProvider));
                    notifier.applySort(v);
                    ref.read(currentIndexProvider.notifier).state = 0;
                  },
                ),
              ]),
            ],
          ),
        ),

        // ── Toolbar ──
        if (pairs.isNotEmpty)
          _Toolbar(
            viewMode:   viewMode,
            selectMode: selectMode,
            selected:   selected,
            totalCount: pairs.length,
            onToggleView: () {
              final next = viewMode == ClipViewMode.text
                  ? ClipViewMode.thumbnail
                  : ClipViewMode.text;
              ref.read(clipViewModeProvider.notifier).state = next;
            },
            onToggleSelect: () {
              final next = !selectMode;
              ref.read(clipSelectionModeProvider.notifier).state = next;
              if (!next) {
                ref.read(selectedClipIndicesProvider.notifier).state = {};
              }
            },
            onSelectAll: () {
              if (selected.length == pairs.length) {
                ref.read(selectedClipIndicesProvider.notifier).state = {};
              } else {
                ref.read(selectedClipIndicesProvider.notifier).state =
                    Set.of(List.generate(pairs.length, (i) => i));
              }
            },
            onSave: selected.isNotEmpty ? widget.onSave : null,
            onDelete: selected.isNotEmpty
                ? () => widget.onDelete?.call(Set.of(selected))
                : null,
          ),

        // ── Clip list ──
        Expanded(
          child: pairs.isEmpty
              ? const Center(
                  child: Text(
                    'No clips loaded.\nOpen your dashcam drive.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ))
              : viewMode == ClipViewMode.thumbnail
                  ? _ThumbnailGrid(
                      scrollController: _scrollController,
                      pairs: pairs,
                      current: current,
                      selectMode: selectMode,
                      selected: selected,
                      durations: ref.watch(clipDurationCacheProvider),
                      onTap: (i) {
                        if (selectMode) {
                          _toggleSelection(selected, i);
                        } else {
                          Navigator.of(context).pop();
                          widget.onSelect(i);
                        }
                      },
                      onLongPress: (i) => _enterSelectMode(i),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: pairs.length,
                      itemBuilder: (ctx, i) => _ClipTile(
                        pair:       pairs[i],
                        index:      i,
                        isCurrent:  i == current,
                        selectMode: selectMode,
                        isSelected: selected.contains(i),
                        duration:   ref.watch(clipDurationCacheProvider)[pairs[i].id],
                        onTap: () {
                          if (selectMode) {
                            _toggleSelection(selected, i);
                          } else {
                            Navigator.of(ctx).pop();
                            widget.onSelect(i);
                          }
                        },
                        onLongPress: () => _enterSelectMode(i),
                      ),
                    ),
        ),
      ]),
    );
  }
}

// ─── Toolbar ────────────────────────────────────────────────────────────────

class _Toolbar extends ConsumerWidget {
  final ClipViewMode viewMode;
  final bool selectMode;
  final Set<int> selected;
  final int totalCount;
  final VoidCallback onToggleView;
  final VoidCallback onToggleSelect;
  final VoidCallback onSelectAll;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;

  const _Toolbar({
    required this.viewMode,
    required this.selectMode,
    required this.selected,
    required this.totalCount,
    required this.onToggleView,
    required this.onToggleSelect,
    required this.onSelectAll,
    this.onSave,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sc = ref.watch(shortcutConfigProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(children: [
        // View toggle
        _ToolbarBtn(
          icon: viewMode == ClipViewMode.text
              ? Icons.grid_view_rounded
              : Icons.list_rounded,
          tooltip: viewMode == ClipViewMode.text
              ? 'Thumbnail view (${sc.label(ShortcutAction.thumbnailToggle)})'
              : 'List view (${sc.label(ShortcutAction.thumbnailToggle)})',
          onPressed: onToggleView,
        ),

        const SizedBox(width: 2),

        // Select mode toggle
        _ToolbarBtn(
          icon: Icons.checklist_rounded,
          tooltip: selectMode
              ? 'Exit select (${sc.label(ShortcutAction.selectMode)})'
              : 'Select (${sc.label(ShortcutAction.selectMode)})',
          isActive: selectMode,
          onPressed: onToggleSelect,
        ),

        // Select all (only visible in select mode)
        if (selectMode) ...[
          const SizedBox(width: 2),
          _ToolbarBtn(
            icon: selected.length == totalCount
                ? Icons.deselect_rounded
                : Icons.select_all_rounded,
            tooltip: selected.length == totalCount
                ? 'Deselect all (${sc.label(ShortcutAction.selectAll)})'
                : 'Select all (${sc.label(ShortcutAction.selectAll)})',
            onPressed: onSelectAll,
          ),
        ],

        const Spacer(),

        if (selectMode) ...[
          // Selection count
          if (selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                '${selected.length}',
                style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),

          // Save
          _ToolbarBtn(
            icon: Icons.save_alt_rounded,
            tooltip: 'Save selected (${sc.label(ShortcutAction.saveClips)})',
            onPressed: onSave,
            color: const Color(0xFF4FC3F7),
          ),

          const SizedBox(width: 2),

          // Delete
          _ToolbarBtn(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete selected (${sc.label(ShortcutAction.deleteClips)})',
            onPressed: onDelete,
            color: Colors.redAccent,
          ),
        ],
      ]),
    );
  }
}

class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isActive;
  final Color? color;

  const _ToolbarBtn({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.isActive = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final c = enabled
        ? (isActive ? const Color(0xFF4FC3F7) : (color ?? Colors.white60))
        : Colors.white24;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: isActive
              ? BoxDecoration(
                  color: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          child: Icon(icon, color: c, size: 18),
        ),
      ),
    );
  }
}

// ─── Text list tile with thumbnail ──────────────────────────────────────────

class _ClipTile extends StatefulWidget {
  final VideoPair    pair;
  final int          index;
  final bool         isCurrent;
  final bool         selectMode;
  final bool         isSelected;
  final Duration?    duration;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ClipTile({
    required this.pair, required this.index,
    required this.isCurrent, required this.onTap,
    required this.selectMode, required this.isSelected,
    required this.onLongPress, this.duration,
  });

  @override
  State<_ClipTile> createState() => _ClipTileState();
}

class _ClipTileState extends State<_ClipTile> {
  String? _thumbPath;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  @override
  void didUpdateWidget(_ClipTile old) {
    super.didUpdateWidget(old);
    if (old.pair.frontPath != widget.pair.frontPath ||
        old.pair.backPath  != widget.pair.backPath) {
      _loadThumb();
    }
  }

  Future<void> _loadThumb() async {
    final videoPath = widget.pair.frontPath ?? widget.pair.backPath;
    if (videoPath == null) return;
    final path = await ThumbnailService.getThumbnail(videoPath);
    if (mounted && path != null) setState(() => _thumbPath = path);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy  HH:mm:ss');

    return ListTile(
      onTap:      widget.onTap,
      onLongPress: widget.onLongPress,
      tileColor: widget.isSelected
          ? const Color(0xFF4FC3F7).withValues(alpha: 0.15)
          : widget.isCurrent
              ? const Color(0xFF4FC3F7).withValues(alpha: 0.1)
              : null,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.selectMode)
            SizedBox(
              width: 28,
              child: Checkbox(
                value: widget.isSelected,
                onChanged: (_) => widget.onTap(),
                activeColor: const Color(0xFF4FC3F7),
                side: const BorderSide(color: Colors.white38),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          // Thumbnail or index box
          Container(
            width: 52, height: 36,
            decoration: BoxDecoration(
              color: widget.isCurrent
                  ? const Color(0xFF4FC3F7).withValues(alpha: 0.2)
                  : Colors.white10,
              borderRadius: BorderRadius.circular(4),
              border: widget.isCurrent
                  ? Border.all(color: const Color(0xFF4FC3F7).withValues(alpha: 0.4))
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: _thumbPath != null
                ? Image.file(File(_thumbPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _indexLabel())
                : _indexLabel(),
          ),
        ],
      ),
      title: Text(
        fmt.format(widget.pair.timestamp),
        style: TextStyle(
          color: widget.isCurrent ? Colors.white : Colors.white70,
          fontSize: 13,
        ),
      ),
      subtitle: Row(children: [
        _badge(widget.pair),
        if (widget.duration != null) ...[
          const SizedBox(width: 6),
          Text(_fmtDuration(widget.duration!),
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
        if (widget.pair.isLocked) ...[
          const SizedBox(width: 4),
          _pill('locked', Colors.red.shade300),
        ],
        if (widget.pair.isRemote) ...[
          const SizedBox(width: 4),
          const Icon(Icons.wifi_rounded, size: 10, color: Color(0xFF4FC3F7)),
        ],
      ]),
      trailing: widget.isCurrent
          ? const Icon(Icons.play_arrow_rounded,
              color: Color(0xFF4FC3F7), size: 18)
          : null,
    );
  }

  Widget _indexLabel() => Center(
    child: Text('${widget.index + 1}',
      style: TextStyle(
        color: widget.isCurrent ? const Color(0xFF4FC3F7) : Colors.white38,
        fontSize: 12, fontWeight: FontWeight.w600,
      )),
  );

  static Widget _badge(VideoPair p) {
    if (p.isPaired) return _pill('F+B', const Color(0xFF4FC3F7));
    if (p.hasFront && !p.hasBack && p.source == 'local') {
      return _pill('Video', Colors.teal);
    }
    if (p.hasFront) return _pill('F only', Colors.orange);
    return _pill('B only', Colors.purple);
  }

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  static Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color:        color.withValues(alpha: 0.15),
      border:       Border.all(color: color.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(text,
      style: TextStyle(
          color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );
}

// ─── Thumbnail grid view ────────────────────────────────────────────────────

class _ThumbnailGrid extends StatelessWidget {
  final ScrollController? scrollController;
  final List<VideoPair> pairs;
  final int current;
  final bool selectMode;
  final Set<int> selected;
  final Map<String, Duration> durations;
  final void Function(int) onTap;
  final void Function(int) onLongPress;

  const _ThumbnailGrid({
    this.scrollController,
    required this.pairs,
    required this.current,
    required this.selectMode,
    required this.selected,
    required this.durations,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.1,
      ),
      itemCount: pairs.length,
      itemBuilder: (_, i) => _ThumbCard(
        pair: pairs[i],
        index: i,
        isCurrent: i == current,
        selectMode: selectMode,
        isSelected: selected.contains(i),
        duration: durations[pairs[i].id],
        onTap: () => onTap(i),
        onLongPress: () => onLongPress(i),
      ),
    );
  }
}

class _ThumbCard extends StatefulWidget {
  final VideoPair pair;
  final int index;
  final bool isCurrent;
  final bool selectMode;
  final bool isSelected;
  final Duration? duration;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ThumbCard({
    required this.pair,
    required this.index,
    required this.isCurrent,
    required this.selectMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    this.duration,
  });

  @override
  State<_ThumbCard> createState() => _ThumbCardState();
}

class _ThumbCardState extends State<_ThumbCard> {
  String? _thumbPath;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(_ThumbCard old) {
    super.didUpdateWidget(old);
    if (old.pair.frontPath != widget.pair.frontPath ||
        old.pair.backPath  != widget.pair.backPath) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    setState(() => _loading = true);
    final videoPath = widget.pair.frontPath ?? widget.pair.backPath;
    if (videoPath == null) {
      setState(() => _loading = false);
      return;
    }
    final path = await ThumbnailService.getThumbnail(videoPath);
    if (mounted) {
      setState(() {
        _thumbPath = path;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm:ss');
    final borderColor = widget.isSelected
        ? const Color(0xFF4FC3F7)
        : widget.isCurrent
            ? const Color(0xFF4FC3F7).withValues(alpha: 0.5)
            : Colors.white10;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: widget.isSelected ? 2 : 1),
          color: widget.isSelected
              ? const Color(0xFF4FC3F7).withValues(alpha: 0.1)
              : const Color(0xFF1A1A1A),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          // Thumbnail image
          Positioned.fill(
            child: _loading
                ? const Center(
                    child: SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white24)))
                : _thumbPath != null
                    ? Image.file(File(_thumbPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholderIcon())
                    : _placeholderIcon(),
          ),

          // Bottom gradient overlay
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 16, 6, 4),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fmt.format(widget.pair.timestamp),
                    style: const TextStyle(color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Row(children: [
                    _miniBadge(widget.pair),
                    if (widget.duration != null) ...[
                      const SizedBox(width: 4),
                      Text(_fmtDur(widget.duration!),
                          style: const TextStyle(color: Colors.white60,
                              fontSize: 9, fontFamily: 'monospace')),
                    ],
                    if (widget.pair.isLocked) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.lock, color: Colors.redAccent, size: 10),
                    ],
                    if (widget.pair.isRemote) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.wifi_rounded, size: 9, color: Color(0xFF4FC3F7)),
                    ],
                  ]),
                ],
              ),
            ),
          ),

          // Selection checkbox
          if (widget.selectMode)
            Positioned(
              top: 4, left: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SizedBox(
                  width: 24, height: 24,
                  child: Checkbox(
                    value: widget.isSelected,
                    onChanged: (_) => widget.onTap(),
                    activeColor: const Color(0xFF4FC3F7),
                    side: const BorderSide(color: Colors.white54),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),

          // Current playing indicator
          if (widget.isCurrent && !widget.selectMode)
            Positioned(
              top: 4, right: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Color(0xFF4FC3F7), size: 14),
              ),
            ),

          // Index badge
          Positioned(
            top: 4, right: widget.isCurrent && !widget.selectMode ? 28 : 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('${widget.index + 1}',
                style: const TextStyle(color: Colors.white54, fontSize: 9,
                    fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  static String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _placeholderIcon() => Container(
    color: const Color(0xFF1A1A1A),
    child: const Center(
      child: Icon(Icons.videocam_rounded, color: Colors.white12, size: 28),
    ),
  );

  Widget _miniBadge(VideoPair p) {
    final (text, color) = p.isPaired
        ? ('F+B', const Color(0xFF4FC3F7))
        : p.hasFront
            ? ('F', Colors.orange)
            : ('B', Colors.purple);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text,
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w700)),
    );
  }
}
