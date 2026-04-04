// lib/widgets/clip_list_drawer.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/shortcut_action.dart';
import '../models/video_pair.dart';
import '../providers/app_providers.dart';
import '../services/thumbnail_service.dart';

const _cyan = Color(0xFF4FC3F7);

// ─── Group helpers ──────────────────────────────────────────────────────────

class _Group {
  final String label;
  final List<int> indices; // indices into the flat pairs list
  const _Group(this.label, this.indices);
}

List<_Group> _buildGroups(List<VideoPair> pairs, GroupBy groupBy) {
  if (groupBy == GroupBy.none) {
    return [_Group('', List.generate(pairs.length, (i) => i))];
  }
  final map = <String, List<int>>{};
  for (var i = 0; i < pairs.length; i++) {
    final key = switch (groupBy) {
      GroupBy.date     => DateFormat('yyyy-MM-dd').format(pairs[i].timestamp),
      GroupBy.fileType => _fileExt(pairs[i]),
      GroupBy.videoType => _videoType(pairs[i]),
      GroupBy.none     => '',
    };
    (map[key] ??= []).add(i);
  }
  return map.entries.map((e) => _Group(e.key, e.value)).toList();
}

String _fileExt(VideoPair p) {
  final path = p.frontPath ?? p.backPath ?? '';
  final dot = path.lastIndexOf('.');
  return dot >= 0 ? path.substring(dot + 1).toUpperCase() : 'Unknown';
}

String _videoType(VideoPair p) {
  if (p.isPaired) return 'Paired (F+B)';
  if (p.hasFront && !p.hasBack) return 'Front Only';
  if (p.hasBack && !p.hasFront) return 'Back Only';
  return 'Unknown';
}

String _groupLabel(GroupBy groupBy, String key) {
  if (groupBy == GroupBy.date) {
    try {
      final dt = DateTime.parse(key);
      return DateFormat('EEEE, MMM d, yyyy').format(dt);
    } catch (_) {
      return key;
    }
  }
  return key;
}

// ─── Main drawer ────────────────────────────────────────────────────────────

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
  ClipViewMode? _lastViewMode;
  final Set<String> _collapsedGroups = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToCurrentClip(animate: true));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentClip({bool animate = false}) {
    if (!_scrollController.hasClients) return;
    // Best-effort scroll; exact offset varies with groups
    final current = ref.read(currentIndexProvider);
    final viewMode = ref.read(clipViewModeProvider);
    final h = viewMode == ClipViewMode.thumbnail ? 146.0 : 72.0;
    final viewportH = _scrollController.position.viewportDimension;
    final offset = (current * h - viewportH / 2 + h / 2)
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
    updated.contains(index) ? updated.remove(index) : updated.add(index);
    ref.read(selectedClipIndicesProvider.notifier).state = updated;
  }

  void _toggleGroupSelection(Set<int> current, List<int> groupIndices) {
    final updated = Set.of(current);
    final allSelected = groupIndices.every(updated.contains);
    if (allSelected) {
      updated.removeAll(groupIndices);
    } else {
      updated.addAll(groupIndices);
    }
    ref.read(selectedClipIndicesProvider.notifier).state = updated;
  }

  void _enterSelectMode(int index) {
    ref.read(clipSelectionModeProvider.notifier).state = true;
    ref.read(selectedClipIndicesProvider.notifier).state = {index};
  }

  @override
  Widget build(BuildContext context) {
    final pairs      = ref.watch(videoPairListProvider);
    final current    = ref.watch(currentIndexProvider);
    final sortOrder  = ref.watch(sortOrderProvider);
    final groupBy    = ref.watch(groupByProvider);
    final viewMode   = ref.watch(clipViewModeProvider);
    final selectMode = ref.watch(clipSelectionModeProvider);
    final selected   = ref.watch(selectedClipIndicesProvider);
    final durations  = ref.watch(clipDurationCacheProvider);

    // Rebuild scroll controller on view switch
    if (_lastViewMode != null && _lastViewMode != viewMode) {
      _scrollController.dispose();
      _scrollController = ScrollController();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentClip());
    }
    _lastViewMode = viewMode;

    final groups = _buildGroups(pairs, groupBy);

    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: Column(children: [
        // ── Header ──
        _Header(
          total: pairs.length,
          paired: pairs.where((p) => p.isPaired).length,
          frontOnly: pairs.where((p) => p.hasFront && !p.hasBack).length,
          backOnly: pairs.where((p) => p.hasBack && !p.hasFront).length,
          sortOrder: sortOrder,
          groupBy: groupBy,
          onSortChanged: (o) {
            ref.read(sortOrderProvider.notifier).state = o;
            ref.read(videoPairListProvider.notifier).applySort(o);
            ref.read(currentIndexProvider.notifier).state = 0;
          },
          onGroupChanged: (g) {
            ref.read(groupByProvider.notifier).state = g;
          },
        ),

        // ── Toolbar ──
        if (pairs.isNotEmpty)
          _Toolbar(
            viewMode: viewMode,
            selectMode: selectMode,
            selected: selected,
            totalCount: pairs.length,
            onToggleView: () {
              ref.read(clipViewModeProvider.notifier).state =
                  viewMode == ClipViewMode.text
                      ? ClipViewMode.thumbnail
                      : ClipViewMode.text;
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
              : _GroupedClipList(
                  scrollController: _scrollController,
                  groups: groups,
                  groupBy: groupBy,
                  pairs: pairs,
                  current: current,
                  viewMode: viewMode,
                  selectMode: selectMode,
                  selected: selected,
                  durations: durations,
                  collapsedGroups: _collapsedGroups,
                  onTap: (i) {
                    if (selectMode) {
                      _toggleSelection(selected, i);
                    } else {
                      Navigator.of(context).pop();
                      widget.onSelect(i);
                    }
                  },
                  onLongPress: _enterSelectMode,
                  onGroupTap: selectMode
                      ? (indices) => _toggleGroupSelection(selected, indices)
                      : null,
                  onGroupCollapse: (label) {
                    setState(() {
                      _collapsedGroups.contains(label)
                          ? _collapsedGroups.remove(label)
                          : _collapsedGroups.add(label);
                    });
                  },
                ),
        ),
      ]),
    );
  }
}

// ─── Header with sort + group controls ──────────────────────────────────────

class _Header extends StatelessWidget {
  final int total, paired, frontOnly, backOnly;
  final SortOrder sortOrder;
  final GroupBy groupBy;
  final ValueChanged<SortOrder> onSortChanged;
  final ValueChanged<GroupBy> onGroupChanged;

  const _Header({
    required this.total,
    required this.paired,
    required this.frontOnly,
    required this.backOnly,
    required this.sortOrder,
    required this.groupBy,
    required this.onSortChanged,
    required this.onGroupChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 10),
      color: const Color(0xFF1A1A1A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('CLIPS',
                style: TextStyle(
                    color: _cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2)),
            const SizedBox(width: 8),
            Text('$total',
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 2),
          Text(
            '$paired paired  ·  $frontOnly front  ·  $backOnly back',
            style: const TextStyle(color: Colors.white30, fontSize: 10),
          ),
          const SizedBox(height: 8),
          // Sort + Group row
          Row(children: [
            // Sort dropdown
            _MiniDropdown<SortOrder>(
              icon: sortOrder == SortOrder.oldestFirst
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              label: sortOrder == SortOrder.oldestFirst
                  ? 'Oldest first'
                  : 'Newest first',
              value: sortOrder,
              items: const [
                (SortOrder.oldestFirst, 'Oldest first'),
                (SortOrder.newestFirst, 'Newest first'),
              ],
              onChanged: onSortChanged,
            ),
            const SizedBox(width: 6),
            // Group dropdown
            _MiniDropdown<GroupBy>(
              icon: Icons.workspaces_rounded,
              label: switch (groupBy) {
                GroupBy.none      => 'No groups',
                GroupBy.date      => 'By date',
                GroupBy.fileType  => 'By file type',
                GroupBy.videoType => 'By video type',
              },
              value: groupBy,
              items: const [
                (GroupBy.none, 'No groups'),
                (GroupBy.date, 'By date'),
                (GroupBy.fileType, 'By file type'),
                (GroupBy.videoType, 'By video type'),
              ],
              onChanged: onGroupChanged,
            ),
          ]),
        ],
      ),
    );
  }
}

class _MiniDropdown<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  const _MiniDropdown({
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      onSelected: onChanged,
      tooltip: label,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      color: const Color(0xFF222222),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      itemBuilder: (_) => [
        for (final (val, text) in items)
          PopupMenuItem(
            value: val,
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    color: val == value ? _cyan : Colors.white60)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: Colors.white38),
          const SizedBox(width: 4),
          Text(label,
              style:
                  const TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down_rounded,
              size: 14, color: Colors.white24),
        ]),
      ),
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
        _ToolbarBtn(
          icon: viewMode == ClipViewMode.text
              ? Icons.grid_view_rounded
              : Icons.list_rounded,
          tooltip: viewMode == ClipViewMode.text
              ? 'Grid view (${sc.label(ShortcutAction.thumbnailToggle)})'
              : 'List view (${sc.label(ShortcutAction.thumbnailToggle)})',
          onPressed: onToggleView,
        ),
        const SizedBox(width: 2),
        _ToolbarBtn(
          icon: Icons.checklist_rounded,
          tooltip: selectMode
              ? 'Exit select (${sc.label(ShortcutAction.selectMode)})'
              : 'Select (${sc.label(ShortcutAction.selectMode)})',
          isActive: selectMode,
          onPressed: onToggleSelect,
        ),
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
          if (selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text('${selected.length}',
                  style: const TextStyle(
                      color: _cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          _ToolbarBtn(
            icon: Icons.save_alt_rounded,
            tooltip: 'Save selected (${sc.label(ShortcutAction.saveClips)})',
            onPressed: onSave,
            color: _cyan,
          ),
          const SizedBox(width: 2),
          _ToolbarBtn(
            icon: Icons.delete_outline_rounded,
            tooltip:
                'Delete selected (${sc.label(ShortcutAction.deleteClips)})',
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
        ? (isActive ? _cyan : (color ?? Colors.white60))
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
                  color: _cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6))
              : null,
          child: Icon(icon, color: c, size: 18),
        ),
      ),
    );
  }
}

// ─── Grouped clip list (works for both views) ───────────────────────────────

class _GroupedClipList extends StatelessWidget {
  final ScrollController scrollController;
  final List<_Group> groups;
  final GroupBy groupBy;
  final List<VideoPair> pairs;
  final int current;
  final ClipViewMode viewMode;
  final bool selectMode;
  final Set<int> selected;
  final Map<String, Duration> durations;
  final Set<String> collapsedGroups;
  final void Function(int) onTap;
  final void Function(int) onLongPress;
  final void Function(List<int>)? onGroupTap;
  final void Function(String)? onGroupCollapse;

  const _GroupedClipList({
    required this.scrollController,
    required this.groups,
    required this.groupBy,
    required this.pairs,
    required this.current,
    required this.viewMode,
    required this.selectMode,
    required this.selected,
    required this.durations,
    required this.collapsedGroups,
    required this.onTap,
    required this.onLongPress,
    this.onGroupTap,
    this.onGroupCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        for (final group in groups) ...[
          // Group header
          if (groupBy != GroupBy.none)
            SliverToBoxAdapter(
              child: _GroupHeader(
                label: _groupLabel(groupBy, group.label),
                count: group.indices.length,
                allSelected: selectMode &&
                    group.indices.every(selected.contains),
                selectMode: selectMode,
                collapsed: collapsedGroups.contains(group.label),
                onTap: selectMode && onGroupTap != null
                    ? () => onGroupTap!(group.indices)
                    : () => onGroupCollapse?.call(group.label),
              ),
            ),
          // Items (hidden when collapsed)
          if (!collapsedGroups.contains(group.label)) ...[
            if (viewMode == ClipViewMode.thumbnail)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 1.1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, j) {
                      final i = group.indices[j];
                      return _ThumbCard(
                        pair: pairs[i],
                        index: i,
                        isCurrent: i == current,
                        selectMode: selectMode,
                        isSelected: selected.contains(i),
                        duration: durations[pairs[i].id],
                        onTap: () => onTap(i),
                        onLongPress: () => onLongPress(i),
                      );
                    },
                    childCount: group.indices.length,
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, j) {
                    final i = group.indices[j];
                    return _ClipTile(
                      pair: pairs[i],
                      index: i,
                      isCurrent: i == current,
                      selectMode: selectMode,
                      isSelected: selected.contains(i),
                      duration: durations[pairs[i].id],
                      onTap: () => onTap(i),
                      onLongPress: () => onLongPress(i),
                    );
                  },
                  childCount: group.indices.length,
                ),
              ),
          ],
        ],
      ],
    );
  }
}

// ─── Group header ───────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  final String label;
  final int count;
  final bool allSelected;
  final bool selectMode;
  final bool collapsed;
  final VoidCallback? onTap;
  const _GroupHeader({
    required this.label,
    required this.count,
    required this.allSelected,
    required this.selectMode,
    required this.collapsed,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 14, 6),
        decoration: const BoxDecoration(
          color: Color(0xFF161616),
          border: Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(children: [
          if (selectMode)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                allSelected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 16,
                color: allSelected ? _cyan : Colors.white30,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                collapsed
                    ? Icons.chevron_right_rounded
                    : Icons.expand_more_rounded,
                size: 18,
                color: Colors.white30,
              ),
            ),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count',
                style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

// ─── Redesigned list tile ───────────────────────────────────────────────────

class _ClipTile extends StatefulWidget {
  final VideoPair pair;
  final int index;
  final bool isCurrent;
  final bool selectMode;
  final bool isSelected;
  final Duration? duration;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _ClipTile({
    required this.pair,
    required this.index,
    required this.isCurrent,
    required this.onTap,
    required this.selectMode,
    required this.isSelected,
    required this.onLongPress,
    this.duration,
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
        old.pair.backPath != widget.pair.backPath) {
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
    final p = widget.pair;
    final bg = widget.isSelected
        ? _cyan.withValues(alpha: 0.12)
        : widget.isCurrent
            ? _cyan.withValues(alpha: 0.06)
            : Colors.transparent;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          border: const Border(
              bottom: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        child: Row(children: [
          // Checkbox
          if (widget.selectMode)
            SizedBox(
              width: 28,
              child: Checkbox(
                value: widget.isSelected,
                onChanged: (_) => widget.onTap(),
                activeColor: _cyan,
                side: const BorderSide(color: Colors.white38),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          // Thumbnail
          Container(
            width: 60,
            height: 40,
            decoration: BoxDecoration(
              color: widget.isCurrent
                  ? _cyan.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(4),
              border: widget.isCurrent
                  ? Border.all(color: _cyan.withValues(alpha: 0.4))
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: _thumbPath != null
                ? Image.file(File(_thumbPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _indexLabel())
                : _indexLabel(),
          ),
          const SizedBox(width: 10),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('HH:mm:ss').format(p.timestamp),
                  style: TextStyle(
                    color: widget.isCurrent ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM d, yyyy').format(p.timestamp),
                  style: const TextStyle(color: Colors.white30, fontSize: 10),
                ),
              ],
            ),
          ),
          // Right side: badge + duration + icons
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                _badge(p),
                if (p.isLocked) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.lock_rounded,
                      size: 10, color: Colors.redAccent),
                ],
                if (p.isRemote) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.wifi_rounded,
                      size: 10, color: _cyan),
                ],
              ]),
              if (widget.duration != null) ...[
                const SizedBox(height: 3),
                Text(_fmtDuration(widget.duration!),
                    style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 9,
                        fontFamily: 'monospace')),
              ],
            ],
          ),
          // Play indicator
          if (widget.isCurrent && !widget.selectMode)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.play_arrow_rounded,
                  color: _cyan, size: 16),
            ),
        ]),
      ),
    );
  }

  Widget _indexLabel() => Center(
        child: Text('${widget.index + 1}',
            style: TextStyle(
                color: widget.isCurrent ? _cyan : Colors.white30,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      );

  static Widget _badge(VideoPair p) {
    final (text, color) = p.isPaired
        ? ('F+B', _cyan)
        : p.hasFront && !p.hasBack && p.source == 'local'
            ? ('Video', Colors.teal)
            : p.hasFront
                ? ('F', Colors.orange)
                : ('B', Colors.purple);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 9, fontWeight: FontWeight.w700)),
    );
  }

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ─── Thumbnail card ─────────────────────────────────────────────────────────

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
        old.pair.backPath != widget.pair.backPath) {
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
    final p = widget.pair;
    final borderColor = widget.isSelected
        ? _cyan
        : widget.isCurrent
            ? _cyan.withValues(alpha: 0.5)
            : Colors.white10;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: borderColor, width: widget.isSelected ? 2 : 1),
          color: widget.isSelected
              ? _cyan.withValues(alpha: 0.1)
              : const Color(0xFF1A1A1A),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          // Thumbnail
          Positioned.fill(
            child: _loading
                ? const Center(
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white24)))
                : _thumbPath != null
                    ? Image.file(File(_thumbPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder())
                    : _placeholder(),
          ),
          // Bottom overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
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
                  Text(DateFormat('HH:mm:ss').format(p.timestamp),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Row(children: [
                    _miniBadge(p),
                    if (widget.duration != null) ...[
                      const SizedBox(width: 4),
                      Text(_fmtDur(widget.duration!),
                          style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 9,
                              fontFamily: 'monospace')),
                    ],
                    if (p.isLocked) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.lock,
                          color: Colors.redAccent, size: 10),
                    ],
                    if (p.isRemote) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.wifi_rounded,
                          size: 9, color: _cyan),
                    ],
                  ]),
                ],
              ),
            ),
          ),
          // Checkbox
          if (widget.selectMode)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: widget.isSelected,
                    onChanged: (_) => widget.onTap(),
                    activeColor: _cyan,
                    side: const BorderSide(color: Colors.white54),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
          // Playing indicator
          if (widget.isCurrent && !widget.selectMode)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: _cyan, size: 14),
              ),
            ),
          // Index
          Positioned(
            top: 4,
            right: widget.isCurrent && !widget.selectMode ? 28 : 4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('${widget.index + 1}',
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 9,
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

  Widget _placeholder() => Container(
        color: const Color(0xFF1A1A1A),
        child: const Center(
          child:
              Icon(Icons.videocam_rounded, color: Colors.white12, size: 28),
        ),
      );

  Widget _miniBadge(VideoPair p) {
    final (text, color) = p.isPaired
        ? ('F+B', _cyan)
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
          style: TextStyle(
              color: color, fontSize: 8, fontWeight: FontWeight.w700)),
    );
  }
}
