// lib/widgets/clip_list_drawer.dart

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/video_pair.dart';
import '../providers/app_providers.dart';
import '../services/thumbnail_service.dart';

// ─── Theme constants ───────────────────────────────────────────────────────

const _kDrawerBg       = Color(0xFF0A0A0F);
const _kHeaderBg       = Color(0xFF0F1118);
const _kToolbarBg      = Color(0xFF0D0F16);
const _kCyan           = Color(0xFF4FC3F7);
const _kAmber          = Color(0xFFFFD54F);
const _kAmberGlow      = Color(0x30FFD54F);
const _kRed            = Color(0xFFEF5350);

const _kTextPrimary    = Color(0xE6FFFFFF);
const _kTextSecondary  = Color(0x99FFFFFF);
const _kTextTertiary   = Color(0x4DFFFFFF);
const _kBorderSubtle   = Color(0x0FFFFFFF);
const _kBorderHover    = Color(0x33FFFFFF);

const _kListTileH      = 68.0;
const _kGridRowH       = 146.0;

// ─── Group helpers ──────────────────────────────────────────────────────────

class _Group {
  final String key;
  final String label;
  final List<int> indices;
  const _Group(this.key, this.label, this.indices);
}

List<_Group> _buildGroups(List<VideoPair> pairs, GroupBy groupBy) {
  if (groupBy == GroupBy.none) {
    return [_Group('', '', List.generate(pairs.length, (i) => i))];
  }
  final map = <String, List<int>>{};
  for (var i = 0; i < pairs.length; i++) {
    final key = switch (groupBy) {
      GroupBy.date      => DateFormat('yyyy-MM-dd').format(pairs[i].timestamp),
      GroupBy.fileType  => _fileExt(pairs[i]),
      GroupBy.videoType => _videoType(pairs[i]),
      GroupBy.none      => '',
    };
    (map[key] ??= []).add(i);
  }
  return map.entries.map((e) => _Group(e.key, _groupLabel(groupBy, e.key), e.value)).toList();
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
    try { return DateFormat('EEEE, MMM d, yyyy').format(DateTime.parse(key)); }
    catch (_) { return key; }
  }
  return key;
}

String _fileName(VideoPair p) {
  final path = p.frontPath ?? p.backPath ?? '';
  final sep = path.contains('\\') ? '\\' : '/';
  return path.split(sep).last;
}

String _fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
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
  late ScrollController _scrollCtrl;
  final FocusNode _focusNode = FocusNode();
  final Set<String> _collapsed = {};
  ClipViewMode? _lastView;
  int _focusedIndex = -1;

  @override
  void initState() {
    super.initState();
    final playing = ref.read(currentIndexProvider);
    _focusedIndex = playing;
    _scrollCtrl = ScrollController(
        initialScrollOffset: _estimateOffset(playing));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCenter(playing, animate: false);
      _focusNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCenter(playing, animate: true);
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Scroll helpers ──

  double _estimateOffset(int index) {
    final vm = ref.read(clipViewModeProvider);
    return vm == ClipViewMode.thumbnail
        ? (index ~/ 2) * _kGridRowH
        : index * _kListTileH;
  }

  void _scrollToCenter(int index, {bool animate = false}) {
    if (!_scrollCtrl.hasClients) return;
    final offset = _estimateOffset(index);
    final vp = _scrollCtrl.position.viewportDimension;
    final max = _scrollCtrl.position.maxScrollExtent;
    final target = (offset - vp / 2 + 36).clamp(0.0, max);
    if (animate) {
      _scrollCtrl.animateTo(target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
    } else {
      _scrollCtrl.jumpTo(target);
    }
  }

  void _ensureVisible(int index) {
    if (!_scrollCtrl.hasClients) return;
    final offset = _estimateOffset(index);
    final pos = _scrollCtrl.position;
    final top = pos.pixels;
    final bottom = top + pos.viewportDimension;
    if (offset < top + 40) {
      _scrollCtrl.animateTo((offset - 40).clamp(0.0, pos.maxScrollExtent),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic);
    } else if (offset > bottom - 100) {
      _scrollCtrl.animateTo(
          (offset - pos.viewportDimension + 100)
              .clamp(0.0, pos.maxScrollExtent),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic);
    }
  }

  // ── Keyboard ──

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final pairs = ref.read(videoPairListProvider);
    if (pairs.isEmpty) return KeyEventResult.ignored;

    final vm = ref.read(clipViewModeProvider);
    final selectMode = ref.read(clipSelectionModeProvider);
    int next = _focusedIndex;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      next += vm == ClipViewMode.thumbnail ? 2 : 1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      next -= vm == ClipViewMode.thumbnail ? 2 : 1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        vm == ClipViewMode.thumbnail) {
      next += 1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        vm == ClipViewMode.thumbnail) {
      next -= 1;
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (selectMode) {
        _toggleSel(_focusedIndex);
      } else if (_focusedIndex >= 0 && _focusedIndex < pairs.length) {
        Navigator.of(context).pop();
        widget.onSelect(_focusedIndex);
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.space && selectMode) {
      _toggleSel(_focusedIndex);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (selectMode) {
        ref.read(clipSelectionModeProvider.notifier).state = false;
        ref.read(selectedClipIndicesProvider.notifier).state = {};
      } else {
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }

    next = next.clamp(0, pairs.length - 1);
    if (next != _focusedIndex) {
      setState(() => _focusedIndex = next);
      _ensureVisible(next);
    }
    return KeyEventResult.handled;
  }

  // ── Selection helpers ──

  void _toggleSel(int index) {
    final sel = Set.of(ref.read(selectedClipIndicesProvider));
    sel.contains(index) ? sel.remove(index) : sel.add(index);
    ref.read(selectedClipIndicesProvider.notifier).state = sel;
  }

  void _toggleGroupSel(List<int> indices) {
    final sel = Set.of(ref.read(selectedClipIndicesProvider));
    indices.every(sel.contains)
        ? sel.removeAll(indices)
        : sel.addAll(indices);
    ref.read(selectedClipIndicesProvider.notifier).state = sel;
  }

  void _enterSelectMode(int index) {
    ref.read(clipSelectionModeProvider.notifier).state = true;
    ref.read(selectedClipIndicesProvider.notifier).state = {index};
    setState(() => _focusedIndex = index);
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final pairs      = ref.watch(videoPairListProvider);
    final playing    = ref.watch(currentIndexProvider);
    final sortOrder  = ref.watch(sortOrderProvider);
    final groupBy    = ref.watch(groupByProvider);
    final viewMode   = ref.watch(clipViewModeProvider);
    final selectMode = ref.watch(clipSelectionModeProvider);
    final selected   = ref.watch(selectedClipIndicesProvider);
    final durations  = ref.watch(clipDurationCacheProvider);

    // Rebuild scroll on view switch
    if (_lastView != null && _lastView != viewMode) {
      _scrollCtrl.dispose();
      _scrollCtrl = ScrollController(
          initialScrollOffset: _estimateOffset(playing));
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToCenter(playing));
    }
    _lastView = viewMode;

    final groups = _buildGroups(pairs, groupBy);

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Drawer(
        width: 340,
        backgroundColor: _kDrawerBg,
        child: Column(children: [
          // ── Header ──
          _PlaylistHeader(
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
              setState(() => _focusedIndex = 0);
            },
            onGroupChanged: (g) =>
                ref.read(groupByProvider.notifier).state = g,
          ),

          // ── Toolbar ──
          if (pairs.isNotEmpty)
            _PlaylistToolbar(
              viewMode: viewMode,
              selectMode: selectMode,
              selectedCount: selected.length,
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

          // ── Body ──
          Expanded(
            child: pairs.isEmpty
                ? const _EmptyState()
                : _PlaylistBody(
                    scrollCtrl: _scrollCtrl,
                    groups: groups,
                    groupBy: groupBy,
                    pairs: pairs,
                    playing: playing,
                    focusedIndex: _focusedIndex,
                    viewMode: viewMode,
                    selectMode: selectMode,
                    selected: selected,
                    durations: durations,
                    collapsed: _collapsed,
                    onTap: (i) {
                      if (selectMode) {
                        _toggleSel(i);
                      } else {
                        Navigator.of(context).pop();
                        widget.onSelect(i);
                      }
                    },
                    onLongPress: _enterSelectMode,
                    onGroupTap: selectMode ? _toggleGroupSel : null,
                    onGroupCollapse: (key) {
                      setState(() {
                        _collapsed.contains(key)
                            ? _collapsed.remove(key)
                            : _collapsed.add(key);
                      });
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────

class _PlaylistHeader extends StatelessWidget {
  final int total, paired, frontOnly, backOnly;
  final SortOrder sortOrder;
  final GroupBy groupBy;
  final ValueChanged<SortOrder> onSortChanged;
  final ValueChanged<GroupBy> onGroupChanged;

  const _PlaylistHeader({
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
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
      decoration: const BoxDecoration(
        color: _kHeaderBg,
        border: Border(bottom: BorderSide(color: _kBorderSubtle)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title row
        Row(children: [
          const Text('PLAYLIST',
              style: TextStyle(
                  color: _kCyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.5)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _kCyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$total',
                style: const TextStyle(
                    color: _kCyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),
        // Stats
        Text(
          [
            if (paired > 0) '$paired paired',
            if (frontOnly > 0) '$frontOnly front',
            if (backOnly > 0) '$backOnly back',
          ].join('  ·  '),
          style: const TextStyle(color: _kTextTertiary, fontSize: 10),
        ),
        const SizedBox(height: 12),
        // Sort + Group dropdowns
        Row(children: [
          _MiniDropdown<SortOrder>(
            icon: Icons.swap_vert_rounded,
            label: sortOrder == SortOrder.oldestFirst ? 'Oldest' : 'Newest',
            items: const {
              SortOrder.oldestFirst: 'Oldest first',
              SortOrder.newestFirst: 'Newest first',
            },
            value: sortOrder,
            onChanged: onSortChanged,
          ),
          const SizedBox(width: 8),
          _MiniDropdown<GroupBy>(
            icon: Icons.workspaces_rounded,
            label: switch (groupBy) {
              GroupBy.none => 'No groups',
              GroupBy.date => 'By date',
              GroupBy.fileType => 'By type',
              GroupBy.videoType => 'By video',
            },
            items: const {
              GroupBy.none: 'No groups',
              GroupBy.date: 'By date',
              GroupBy.fileType: 'By file type',
              GroupBy.videoType: 'By video type',
            },
            value: groupBy,
            onChanged: onGroupChanged,
          ),
        ]),
      ]),
    );
  }
}

// ─── Mini dropdown ──────────────────────────────────────────────────────────

class _MiniDropdown<T> extends StatefulWidget {
  final IconData icon;
  final String label;
  final Map<T, String> items;
  final T value;
  final ValueChanged<T> onChanged;

  const _MiniDropdown({
    required this.icon,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_MiniDropdown<T>> createState() => _MiniDropdownState<T>();
}

class _MiniDropdownState<T> extends State<_MiniDropdown<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PopupMenuButton<T>(
        onSelected: widget.onChanged,
        color: const Color(0xFF151520),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        offset: const Offset(0, 32),
        itemBuilder: (_) => widget.items.entries
            .map((e) => PopupMenuItem(
                  value: e.key,
                  height: 36,
                  child: Text(e.value,
                      style: TextStyle(
                        color:
                            e.key == widget.value ? _kCyan : _kTextSecondary,
                        fontSize: 12,
                        fontWeight: e.key == widget.value
                            ? FontWeight.w600
                            : FontWeight.w400,
                      )),
                ))
            .toList(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _hovered ? _kBorderHover : _kBorderSubtle,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 12, color: _kTextTertiary),
            const SizedBox(width: 5),
            Text(widget.label,
                style: const TextStyle(
                    color: _kTextSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 3),
            const Icon(Icons.expand_more_rounded,
                size: 12, color: _kTextTertiary),
          ]),
        ),
      ),
    );
  }
}

// ─── Toolbar ────────────────────────────────────────────────────────────────

class _PlaylistToolbar extends StatelessWidget {
  final ClipViewMode viewMode;
  final bool selectMode;
  final int selectedCount;
  final int totalCount;
  final VoidCallback onToggleView;
  final VoidCallback onToggleSelect;
  final VoidCallback onSelectAll;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;

  const _PlaylistToolbar({
    required this.viewMode,
    required this.selectMode,
    required this.selectedCount,
    required this.totalCount,
    required this.onToggleView,
    required this.onToggleSelect,
    required this.onSelectAll,
    this.onSave,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: _kToolbarBg,
        border: Border(bottom: BorderSide(color: _kBorderSubtle)),
      ),
      child: Row(children: [
        _ToolBtn(
          icon: viewMode == ClipViewMode.text
              ? Icons.grid_view_rounded
              : Icons.view_list_rounded,
          tooltip: viewMode == ClipViewMode.text ? 'Grid view' : 'List view',
          onTap: onToggleView,
        ),
        const SizedBox(width: 2),
        _ToolBtn(
          icon: Icons.checklist_rounded,
          tooltip: 'Select mode',
          active: selectMode,
          onTap: onToggleSelect,
        ),
        if (selectMode) ...[
          const SizedBox(width: 2),
          _ToolBtn(
            icon: selectedCount == totalCount
                ? Icons.deselect_rounded
                : Icons.select_all_rounded,
            tooltip: selectedCount == totalCount ? 'Deselect all' : 'Select all',
            onTap: onSelectAll,
          ),
        ],
        const Spacer(),
        if (selectMode && selectedCount > 0)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _kCyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$selectedCount',
                style: const TextStyle(
                    color: _kCyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
        if (selectMode) ...[
          _ToolBtn(
            icon: Icons.save_alt_rounded,
            tooltip: 'Save selected',
            onTap: onSave,
            color: _kCyan,
          ),
          const SizedBox(width: 2),
          _ToolBtn(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete selected',
            onTap: onDelete,
            color: _kRed,
          ),
        ],
      ]),
    );
  }
}

class _ToolBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final Color? color;

  const _ToolBtn({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
    this.color,
  });

  @override
  State<_ToolBtn> createState() => _ToolBtnState();
}

class _ToolBtnState extends State<_ToolBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final c = widget.active
        ? (widget.color ?? _kCyan)
        : disabled
            ? _kTextTertiary.withValues(alpha: 0.4)
            : _hovered
                ? _kTextPrimary
                : _kTextSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: widget.active
                  ? (widget.color ?? _kCyan).withValues(alpha: 0.15)
                  : _hovered
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: 16, color: c),
          ),
        ),
      ),
    );
  }
}

// ─── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.videocam_off_rounded, size: 48, color: _kTextTertiary),
        SizedBox(height: 12),
        Text('No clips loaded',
            style: TextStyle(
                color: _kTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        SizedBox(height: 4),
        Text('Open a dashcam folder to get started',
            style: TextStyle(color: _kTextTertiary, fontSize: 12)),
      ]),
    );
  }
}

// ─── Playlist body ──────────────────────────────────────────────────────────

class _PlaylistBody extends StatelessWidget {
  final ScrollController scrollCtrl;
  final List<_Group> groups;
  final GroupBy groupBy;
  final List<VideoPair> pairs;
  final int playing;
  final int focusedIndex;
  final ClipViewMode viewMode;
  final bool selectMode;
  final Set<int> selected;
  final Map<String, Duration> durations;
  final Set<String> collapsed;
  final void Function(int) onTap;
  final void Function(int) onLongPress;
  final void Function(List<int>)? onGroupTap;
  final void Function(String)? onGroupCollapse;

  const _PlaylistBody({
    required this.scrollCtrl,
    required this.groups,
    required this.groupBy,
    required this.pairs,
    required this.playing,
    required this.focusedIndex,
    required this.viewMode,
    required this.selectMode,
    required this.selected,
    required this.durations,
    required this.collapsed,
    required this.onTap,
    required this.onLongPress,
    this.onGroupTap,
    this.onGroupCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollCtrl,
      slivers: [
        for (final group in groups) ...[
          if (groupBy != GroupBy.none)
            SliverToBoxAdapter(
              child: _GroupHeader(
                label: group.label,
                count: group.indices.length,
                selectMode: selectMode,
                selectedCount:
                    group.indices.where(selected.contains).length,
                isCollapsed: collapsed.contains(group.key),
                onTap: selectMode && onGroupTap != null
                    ? () => onGroupTap!(group.indices)
                    : () => onGroupCollapse?.call(group.key),
              ),
            ),
          if (!collapsed.contains(group.key)) ...[
            if (viewMode == ClipViewMode.thumbnail)
              SliverPadding(
                padding: const EdgeInsets.all(10),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.05,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, j) {
                      final i = group.indices[j];
                      return _GridCard(
                        pair: pairs[i],
                        index: i,
                        isPlaying: i == playing,
                        isFocused: i == focusedIndex,
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
                    return _ListTile(
                      pair: pairs[i],
                      index: i,
                      isPlaying: i == playing,
                      isFocused: i == focusedIndex,
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

class _GroupHeader extends StatefulWidget {
  final String label;
  final int count;
  final bool selectMode;
  final int selectedCount;
  final bool isCollapsed;
  final VoidCallback? onTap;

  const _GroupHeader({
    required this.label,
    required this.count,
    required this.selectMode,
    required this.selectedCount,
    required this.isCollapsed,
    this.onTap,
  });

  @override
  State<_GroupHeader> createState() => _GroupHeaderState();
}

class _GroupHeaderState extends State<_GroupHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final allSelected =
        widget.selectMode && widget.selectedCount == widget.count;
    final someSelected =
        widget.selectMode && widget.selectedCount > 0 && !allSelected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 8),
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFF161620)
                : const Color(0xFF0E1018),
            border:
                const Border(bottom: BorderSide(color: _kBorderSubtle)),
          ),
          child: Row(children: [
            if (widget.selectMode)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  allSelected
                      ? Icons.check_box_rounded
                      : someSelected
                          ? Icons.indeterminate_check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                  size: 16,
                  color: allSelected || someSelected
                      ? _kCyan
                      : _kTextTertiary,
                ),
              )
            else
              AnimatedRotation(
                turns: widget.isCollapsed ? -0.25 : 0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.expand_more_rounded,
                      size: 18, color: _kTextTertiary),
                ),
              ),
            Expanded(
              child: Text(widget.label,
                  style: const TextStyle(
                      color: _kTextSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${widget.count}',
                  style: const TextStyle(
                      color: _kTextTertiary,
                      fontSize: 9,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Now-playing equalizer ──────────────────────────────────────────────────

class _Equalizer extends StatefulWidget {
  final double size;
  const _Equalizer({this.size = 14});

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (i) {
            final phase = i * 2.1;
            final h = widget.size *
                (0.3 + 0.7 * ((sin(_ctrl.value * 2 * pi + phase) + 1) / 2));
            return Container(
              width: 2,
              height: h,
              margin: EdgeInsets.only(left: i > 0 ? 1.5 : 0),
              decoration: BoxDecoration(
                color: _kAmber,
                borderRadius: BorderRadius.circular(1),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─── List tile ──────────────────────────────────────────────────────────────

class _ListTile extends StatefulWidget {
  final VideoPair pair;
  final int index;
  final bool isPlaying;
  final bool isFocused;
  final bool selectMode;
  final bool isSelected;
  final Duration? duration;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ListTile({
    required this.pair,
    required this.index,
    required this.isPlaying,
    required this.isFocused,
    required this.selectMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    this.duration,
  });

  @override
  State<_ListTile> createState() => _ListTileState();
}

class _ListTileState extends State<_ListTile> {
  String? _thumbPath;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  @override
  void didUpdateWidget(_ListTile old) {
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

    // Background
    final bg = widget.isSelected
        ? _kCyan.withValues(alpha: 0.10)
        : widget.isPlaying
            ? _kAmber.withValues(alpha: 0.06)
            : _hovered
                ? Colors.white.withValues(alpha: 0.05)
                : widget.isFocused
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.transparent;

    // Border
    final border = widget.isPlaying
        ? Border.all(color: _kAmber.withValues(alpha: 0.6), width: 1.5)
        : widget.isSelected
            ? Border.all(color: _kCyan.withValues(alpha: 0.3), width: 1)
            : widget.isFocused
                ? const Border(
                    left: BorderSide(color: _kCyan, width: 2),
                    bottom: BorderSide(color: _kBorderSubtle, width: 0.5))
                : const Border(
                    bottom: BorderSide(color: _kBorderSubtle, width: 0.5));

    final radius = widget.isPlaying || widget.isSelected
        ? BorderRadius.circular(8)
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: _kListTileH,
          margin: widget.isPlaying
              ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
              : EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            border: border,
            borderRadius: radius,
            boxShadow: widget.isPlaying
                ? [BoxShadow(color: _kAmberGlow, blurRadius: 12)]
                : null,
          ),
          child: Row(children: [
            // Checkbox (animated width)
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: widget.selectMode
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: widget.isSelected,
                          onChanged: (_) => widget.onTap(),
                          activeColor: _kCyan,
                          side: const BorderSide(color: _kTextTertiary),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // Thumbnail
            AnimatedScale(
              scale: _hovered ? 1.04 : 1.0,
              duration: const Duration(milliseconds: 120),
              child: Container(
                width: 56,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                  border: widget.isPlaying
                      ? Border.all(
                          color: _kAmber.withValues(alpha: 0.4), width: 1)
                      : _hovered
                          ? Border.all(color: _kBorderHover, width: 0.5)
                          : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: _thumbPath != null
                    ? Image.file(File(_thumbPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder())
                    : _placeholder(),
              ),
            ),
            const SizedBox(width: 10),

            // Info
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fileName(p),
                    style: TextStyle(
                      color: widget.isPlaying ? Colors.white : _kTextPrimary,
                      fontSize: 11,
                      fontWeight:
                          widget.isPlaying ? FontWeight.w600 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${DateFormat('HH:mm:ss').format(p.timestamp)}  |  ${DateFormat('MMM d, yyyy').format(p.timestamp)}',
                    style: const TextStyle(
                        color: _kTextTertiary, fontSize: 10),
                  ),
                ],
              ),
            ),

            // Right side
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _badge(p),
                  if (p.isLocked) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.lock_rounded,
                        size: 10, color: _kRed),
                  ],
                  if (p.isRemote) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.wifi_rounded,
                        size: 10, color: _kCyan),
                  ],
                ]),
                if (widget.duration != null) ...[
                  const SizedBox(height: 4),
                  Text(_fmtDuration(widget.duration!),
                      style: const TextStyle(
                          color: _kTextTertiary,
                          fontSize: 9,
                          fontFamily: 'monospace')),
                ],
              ],
            ),

            // Play indicator
            if (widget.isPlaying && !widget.selectMode)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _Equalizer(size: 14),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _placeholder() => Center(
        child: Text('${widget.index + 1}',
            style: TextStyle(
                color: widget.isPlaying ? _kAmber : _kTextTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      );

  static Widget _badge(VideoPair p) {
    final (text, color) = p.isPaired
        ? ('F+B', _kCyan)
        : p.hasFront && !p.hasBack && p.source == 'local'
            ? ('Video', Colors.teal)
            : p.hasFront
                ? ('F', Colors.orange)
                : ('B', Colors.purple);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 8, fontWeight: FontWeight.w700)),
    );
  }
}

// ─── Grid card ──────────────────────────────────────────────────────────────

class _GridCard extends StatefulWidget {
  final VideoPair pair;
  final int index;
  final bool isPlaying;
  final bool isFocused;
  final bool selectMode;
  final bool isSelected;
  final Duration? duration;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _GridCard({
    required this.pair,
    required this.index,
    required this.isPlaying,
    required this.isFocused,
    required this.selectMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    this.duration,
  });

  @override
  State<_GridCard> createState() => _GridCardState();
}

class _GridCardState extends State<_GridCard> {
  String? _thumbPath;
  bool _loading = true;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(_GridCard old) {
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
        ? _kCyan
        : widget.isPlaying
            ? _kAmber
            : widget.isFocused
                ? _kCyan.withValues(alpha: 0.6)
                : _hovered
                    ? _kBorderHover
                    : _kBorderSubtle;

    final borderWidth =
        widget.isSelected || widget.isPlaying || widget.isFocused ? 2.0 : 1.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _hovered && !widget.isPlaying ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: widget.isPlaying
                  ? [BoxShadow(color: _kAmberGlow, blurRadius: 16, spreadRadius: 1)]
                  : null,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10 - borderWidth),
                color: widget.isSelected
                    ? _kCyan.withValues(alpha: 0.08)
                    : const Color(0xFF1A1A1A),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: [
                // Thumbnail
                Positioned.fill(
                  child: _loading
                      ? const _ShimmerPlaceholder()
                      : _thumbPath != null
                          ? Image.file(File(_thumbPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _placeholderIcon())
                          : _placeholderIcon(),
                ),

                // Bottom gradient overlay
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 18, 6, 5),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xE6000000)],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_fileName(p),
                            style: TextStyle(
                                color: widget.isPlaying
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.9),
                                fontSize: 9,
                                fontWeight: widget.isPlaying
                                    ? FontWeight.w600
                                    : FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1),
                        const SizedBox(height: 3),
                        Row(children: [
                          _miniBadge(p),
                          if (widget.duration != null) ...[
                            const SizedBox(width: 4),
                            Text(_fmtDuration(widget.duration!),
                                style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 8,
                                    fontFamily: 'monospace')),
                          ],
                          if (p.isLocked) ...[
                            const SizedBox(width: 3),
                            const Icon(Icons.lock,
                                color: _kRed, size: 9),
                          ],
                          if (p.isRemote) ...[
                            const SizedBox(width: 3),
                            const Icon(Icons.wifi_rounded,
                                size: 9, color: _kCyan),
                          ],
                        ]),
                      ],
                    ),
                  ),
                ),

                // Checkbox (select mode)
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
                          activeColor: _kCyan,
                          side: const BorderSide(color: Colors.white54),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ),

                // Playing indicator
                if (widget.isPlaying && !widget.selectMode)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: _Equalizer(size: 12),
                    ),
                  ),

                // Index badge
                if (!widget.isPlaying || widget.selectMode)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
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
          ),
        ),
      ),
    );
  }

  static Widget _placeholderIcon() => const Center(
        child: Icon(Icons.videocam_rounded, color: Colors.white12, size: 28),
      );

  static Widget _miniBadge(VideoPair p) {
    final (text, color) = p.isPaired
        ? ('F+B', _kCyan)
        : p.hasFront
            ? ('F', Colors.orange)
            : ('B', Colors.purple);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 7, fontWeight: FontWeight.w700)),
    );
  }
}

// ─── Shimmer placeholder ────────────────────────────────────────────────────

class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder();

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
              end: Alignment(-0.5 + 2.0 * _ctrl.value, 0),
              colors: const [
                Color(0xFF1A1A1A),
                Color(0xFF252530),
                Color(0xFF1A1A1A),
              ],
            ),
          ),
        );
      },
    );
  }
}
