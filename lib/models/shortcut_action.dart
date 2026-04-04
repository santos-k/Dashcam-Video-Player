// lib/models/shortcut_action.dart

import 'package:flutter/services.dart';

// ─── Action enum ────────────────────────────────────────────────────────────

enum ShortcutAction {
  // Playback
  playPause,
  seekForward,
  seekBackward,
  nextClip,
  previousClip,
  // Audio
  muteFront,
  muteBack,
  // Speed
  speedUp,
  speedDown,
  speedReset,
  // Zoom
  zoomIn,
  zoomOut,
  zoomReset,
  // Sync
  syncToggle,
  // Layout
  layoutSideBySide,
  layoutStacked,
  layoutPip,
  layoutFrontOnly,
  layoutBackOnly,
  layoutPopup,
  // View
  fullscreen,
  fullscreenAlt,
  clipList,
  thumbnailToggle,
  selectMode,
  selectAll,
  mapSidebar,
  wifiDashcam,
  about,
  // File
  openFolder,
  saveClips,
  deleteClips,
  exportVideo,
  closeFolder,
  toggleSort,
  // App
  quit,
  shortcutSettings,
}

// ─── Key binding ────────────────────────────────────────────────────────────

class KeyBinding {
  final String keyId;
  final bool shift;
  const KeyBinding(this.keyId, {this.shift = false});

  KeyBinding copyWith({String? keyId, bool? shift}) =>
      KeyBinding(keyId ?? this.keyId, shift: shift ?? this.shift);

  Map<String, dynamic> toJson() => {'key': keyId, 'shift': shift};

  factory KeyBinding.fromJson(Map<String, dynamic> json) =>
      KeyBinding(json['key'] as String, shift: json['shift'] as bool? ?? false);

  /// Human-readable label for display: e.g. "Shift+S", "Space", "F11"
  String get label {
    final name = keyDisplayNames[keyId] ?? keyId;
    return shift ? 'Shift+$name' : name;
  }

  /// Match against a keyboard event.
  bool matches(LogicalKeyboardKey key, bool shiftHeld) {
    final target = keyMap[keyId];
    if (target == null) return false;
    return key == target && shiftHeld == shift;
  }

  @override
  bool operator ==(Object other) =>
      other is KeyBinding && other.keyId == keyId && other.shift == shift;
  @override
  int get hashCode => Object.hash(keyId, shift);
}

// ─── Shortcut config ────────────────────────────────────────────────────────

class ShortcutConfig {
  final Map<ShortcutAction, KeyBinding> bindings;
  const ShortcutConfig(this.bindings);

  factory ShortcutConfig.defaults() => ShortcutConfig(Map.of(_defaults));

  KeyBinding operator [](ShortcutAction action) =>
      bindings[action] ?? _defaults[action]!;

  ShortcutConfig withBinding(ShortcutAction action, KeyBinding binding) {
    final copy = Map.of(bindings);
    copy[action] = binding;
    return ShortcutConfig(copy);
  }

  /// Find which action (if any) is bound to the given key+shift combo.
  ShortcutAction? actionFor(LogicalKeyboardKey key, bool shiftHeld) {
    for (final entry in bindings.entries) {
      if (entry.value.matches(key, shiftHeld)) return entry.key;
    }
    return null;
  }

  /// Label string for a given action (for tooltips).
  String label(ShortcutAction action) => this[action].label;

  Map<String, dynamic> toJson() => {
    for (final e in bindings.entries)
      e.key.name: e.value.toJson(),
  };

  factory ShortcutConfig.fromJson(Map<String, dynamic> json) {
    final map = <ShortcutAction, KeyBinding>{};
    for (final action in ShortcutAction.values) {
      final data = json[action.name];
      if (data is Map<String, dynamic>) {
        map[action] = KeyBinding.fromJson(data);
      } else {
        map[action] = _defaults[action]!;
      }
    }
    return ShortcutConfig(map);
  }
}

// ─── Metadata per action ────────────────────────────────────────────────────

const actionDisplayNames = <ShortcutAction, String>{
  ShortcutAction.playPause:        'Play / Pause',
  ShortcutAction.seekForward:      'Seek forward 10s',
  ShortcutAction.seekBackward:     'Seek backward 10s',
  ShortcutAction.nextClip:         'Next clip',
  ShortcutAction.previousClip:     'Previous clip',
  ShortcutAction.muteFront:        'Mute front camera',
  ShortcutAction.muteBack:         'Mute back camera',
  ShortcutAction.speedUp:          'Speed up',
  ShortcutAction.speedDown:        'Speed down',
  ShortcutAction.speedReset:       'Reset speed 1x',
  ShortcutAction.zoomIn:           'Zoom in',
  ShortcutAction.zoomOut:          'Zoom out',
  ShortcutAction.zoomReset:        'Reset zoom',
  ShortcutAction.syncToggle:       'Toggle sync panel',
  ShortcutAction.layoutSideBySide: 'Side-by-side / Stacked',
  ShortcutAction.layoutStacked:    'Stacked',
  ShortcutAction.layoutPip:        'PIP (toggle primary)',
  ShortcutAction.layoutFrontOnly:  'Solo view (toggle F/B)',
  ShortcutAction.layoutBackOnly:   'Solo view (toggle B/F)',
  ShortcutAction.layoutPopup:      'Layout popup',
  ShortcutAction.fullscreen:       'Fullscreen',
  ShortcutAction.fullscreenAlt:    'Fullscreen (alt)',
  ShortcutAction.clipList:         'Clip list',
  ShortcutAction.thumbnailToggle:  'List / Thumbnails',
  ShortcutAction.selectMode:       'Select mode',
  ShortcutAction.selectAll:        'Select all',
  ShortcutAction.mapSidebar:       'Map sidebar',
  ShortcutAction.wifiDashcam:      'Wi-Fi dashcam',
  ShortcutAction.about:            'About',
  ShortcutAction.openFolder:       'Open folder',
  ShortcutAction.saveClips:        'Save clips',
  ShortcutAction.deleteClips:      'Delete clips',
  ShortcutAction.exportVideo:      'Export video',
  ShortcutAction.closeFolder:      'Close folder',
  ShortcutAction.toggleSort:       'Toggle sort',
  ShortcutAction.quit:             'Quit',
  ShortcutAction.shortcutSettings: 'Keyboard shortcuts',
};

const actionCategories = <String, List<ShortcutAction>>{
  'Playback': [
    ShortcutAction.playPause,
    ShortcutAction.seekForward,
    ShortcutAction.seekBackward,
    ShortcutAction.nextClip,
    ShortcutAction.previousClip,
  ],
  'Audio': [
    ShortcutAction.muteFront,
    ShortcutAction.muteBack,
  ],
  'Speed': [
    ShortcutAction.speedUp,
    ShortcutAction.speedDown,
    ShortcutAction.speedReset,
    ShortcutAction.zoomIn,
    ShortcutAction.zoomOut,
    ShortcutAction.zoomReset,
  ],
  'Sync': [
    ShortcutAction.syncToggle,
  ],
  'Layout': [
    ShortcutAction.layoutSideBySide,
    ShortcutAction.layoutStacked,
    ShortcutAction.layoutPip,
    ShortcutAction.layoutFrontOnly,
    ShortcutAction.layoutBackOnly,
    ShortcutAction.layoutPopup,
  ],
  'View': [
    ShortcutAction.fullscreen,
    ShortcutAction.fullscreenAlt,
    ShortcutAction.clipList,
    ShortcutAction.thumbnailToggle,
    ShortcutAction.selectMode,
    ShortcutAction.selectAll,
    ShortcutAction.mapSidebar,
    ShortcutAction.wifiDashcam,
    ShortcutAction.about,
  ],
  'File': [
    ShortcutAction.openFolder,
    ShortcutAction.saveClips,
    ShortcutAction.deleteClips,
    ShortcutAction.exportVideo,
    ShortcutAction.closeFolder,
    ShortcutAction.toggleSort,
  ],
  'App': [
    ShortcutAction.quit,
    ShortcutAction.shortcutSettings,
  ],
};

// ─── Default bindings ───────────────────────────────────────────────────────

const _defaults = <ShortcutAction, KeyBinding>{
  ShortcutAction.playPause:        KeyBinding('space'),
  ShortcutAction.seekForward:      KeyBinding('arrowRight'),
  ShortcutAction.seekBackward:     KeyBinding('arrowLeft'),
  ShortcutAction.nextClip:         KeyBinding('period', shift: true),
  ShortcutAction.previousClip:     KeyBinding('comma', shift: true),
  ShortcutAction.muteFront:        KeyBinding('keyF'),
  ShortcutAction.muteBack:         KeyBinding('keyB'),
  ShortcutAction.speedUp:          KeyBinding('bracketRight'),
  ShortcutAction.speedDown:        KeyBinding('bracketLeft'),
  ShortcutAction.speedReset:       KeyBinding('backslash'),
  ShortcutAction.zoomIn:           KeyBinding('equal'),
  ShortcutAction.zoomOut:          KeyBinding('minus'),
  ShortcutAction.zoomReset:        KeyBinding('digit0'),
  ShortcutAction.syncToggle:       KeyBinding('keyY'),
  ShortcutAction.layoutSideBySide: KeyBinding('digit1'),
  ShortcutAction.layoutStacked:    KeyBinding('digit1', shift: true),
  ShortcutAction.layoutPip:        KeyBinding('digit2'),
  ShortcutAction.layoutFrontOnly:  KeyBinding('digit3'),
  ShortcutAction.layoutBackOnly:   KeyBinding('digit3', shift: true),
  ShortcutAction.layoutPopup:      KeyBinding('keyL'),
  ShortcutAction.fullscreen:       KeyBinding('shiftLeft'),
  ShortcutAction.fullscreenAlt:    KeyBinding('f11'),
  ShortcutAction.clipList:         KeyBinding('keyC'),
  ShortcutAction.thumbnailToggle:  KeyBinding('keyT'),
  ShortcutAction.selectMode:       KeyBinding('keyX'),
  ShortcutAction.selectAll:        KeyBinding('keyA'),
  ShortcutAction.mapSidebar:       KeyBinding('keyM'),
  ShortcutAction.wifiDashcam:      KeyBinding('keyN'),
  ShortcutAction.about:            KeyBinding('keyI'),
  ShortcutAction.openFolder:       KeyBinding('keyO'),
  ShortcutAction.saveClips:        KeyBinding('keyS'),
  ShortcutAction.deleteClips:      KeyBinding('keyD'),
  ShortcutAction.exportVideo:      KeyBinding('keyE'),
  ShortcutAction.closeFolder:      KeyBinding('keyW'),
  ShortcutAction.toggleSort:       KeyBinding('keyR'),
  ShortcutAction.quit:             KeyBinding('keyQ'),
  ShortcutAction.shortcutSettings: KeyBinding('slash'),
};

// ─── Key ID <-> LogicalKeyboardKey mapping ──────────────────────────────────

const keyMap = <String, LogicalKeyboardKey>{
  'space':        LogicalKeyboardKey.space,
  'arrowRight':   LogicalKeyboardKey.arrowRight,
  'arrowLeft':    LogicalKeyboardKey.arrowLeft,
  'arrowUp':      LogicalKeyboardKey.arrowUp,
  'arrowDown':    LogicalKeyboardKey.arrowDown,
  'enter':        LogicalKeyboardKey.enter,
  'escape':       LogicalKeyboardKey.escape,
  'tab':          LogicalKeyboardKey.tab,
  'backspace':    LogicalKeyboardKey.backspace,
  'delete':       LogicalKeyboardKey.delete,
  'home':         LogicalKeyboardKey.home,
  'end':          LogicalKeyboardKey.end,
  'pageUp':       LogicalKeyboardKey.pageUp,
  'pageDown':     LogicalKeyboardKey.pageDown,
  'f1':           LogicalKeyboardKey.f1,
  'f2':           LogicalKeyboardKey.f2,
  'f3':           LogicalKeyboardKey.f3,
  'f4':           LogicalKeyboardKey.f4,
  'f5':           LogicalKeyboardKey.f5,
  'f6':           LogicalKeyboardKey.f6,
  'f7':           LogicalKeyboardKey.f7,
  'f8':           LogicalKeyboardKey.f8,
  'f9':           LogicalKeyboardKey.f9,
  'f10':          LogicalKeyboardKey.f10,
  'f11':          LogicalKeyboardKey.f11,
  'f12':          LogicalKeyboardKey.f12,
  'keyA':         LogicalKeyboardKey.keyA,
  'keyB':         LogicalKeyboardKey.keyB,
  'keyC':         LogicalKeyboardKey.keyC,
  'keyD':         LogicalKeyboardKey.keyD,
  'keyE':         LogicalKeyboardKey.keyE,
  'keyF':         LogicalKeyboardKey.keyF,
  'keyG':         LogicalKeyboardKey.keyG,
  'keyH':         LogicalKeyboardKey.keyH,
  'keyI':         LogicalKeyboardKey.keyI,
  'keyJ':         LogicalKeyboardKey.keyJ,
  'keyK':         LogicalKeyboardKey.keyK,
  'keyL':         LogicalKeyboardKey.keyL,
  'keyM':         LogicalKeyboardKey.keyM,
  'keyN':         LogicalKeyboardKey.keyN,
  'keyO':         LogicalKeyboardKey.keyO,
  'keyP':         LogicalKeyboardKey.keyP,
  'keyQ':         LogicalKeyboardKey.keyQ,
  'keyR':         LogicalKeyboardKey.keyR,
  'keyS':         LogicalKeyboardKey.keyS,
  'keyT':         LogicalKeyboardKey.keyT,
  'keyU':         LogicalKeyboardKey.keyU,
  'keyV':         LogicalKeyboardKey.keyV,
  'keyW':         LogicalKeyboardKey.keyW,
  'keyX':         LogicalKeyboardKey.keyX,
  'keyY':         LogicalKeyboardKey.keyY,
  'keyZ':         LogicalKeyboardKey.keyZ,
  'digit0':       LogicalKeyboardKey.digit0,
  'digit1':       LogicalKeyboardKey.digit1,
  'digit2':       LogicalKeyboardKey.digit2,
  'digit3':       LogicalKeyboardKey.digit3,
  'digit4':       LogicalKeyboardKey.digit4,
  'digit5':       LogicalKeyboardKey.digit5,
  'digit6':       LogicalKeyboardKey.digit6,
  'digit7':       LogicalKeyboardKey.digit7,
  'digit8':       LogicalKeyboardKey.digit8,
  'digit9':       LogicalKeyboardKey.digit9,
  'comma':        LogicalKeyboardKey.comma,
  'period':       LogicalKeyboardKey.period,
  'semicolon':    LogicalKeyboardKey.semicolon,
  'quote':        LogicalKeyboardKey.quote,
  'bracketLeft':  LogicalKeyboardKey.bracketLeft,
  'bracketRight': LogicalKeyboardKey.bracketRight,
  'backslash':    LogicalKeyboardKey.backslash,
  'slash':        LogicalKeyboardKey.slash,
  'minus':        LogicalKeyboardKey.minus,
  'equal':        LogicalKeyboardKey.equal,
  'backquote':    LogicalKeyboardKey.backquote,
  'shiftLeft':    LogicalKeyboardKey.shiftLeft,
};

/// Reverse lookup: LogicalKeyboardKey -> string ID.
final reverseKeyMap = <LogicalKeyboardKey, String>{
  for (final e in keyMap.entries) e.value: e.key,
};

/// Human-readable names for keys.
const keyDisplayNames = <String, String>{
  'space':        'Space',
  'arrowRight':   '\u2192',
  'arrowLeft':    '\u2190',
  'arrowUp':      '\u2191',
  'arrowDown':    '\u2193',
  'enter':        'Enter',
  'escape':       'Esc',
  'tab':          'Tab',
  'backspace':    'Backspace',
  'delete':       'Del',
  'home':         'Home',
  'end':          'End',
  'pageUp':       'PgUp',
  'pageDown':     'PgDn',
  'f1': 'F1', 'f2': 'F2', 'f3': 'F3', 'f4': 'F4',
  'f5': 'F5', 'f6': 'F6', 'f7': 'F7', 'f8': 'F8',
  'f9': 'F9', 'f10': 'F10', 'f11': 'F11', 'f12': 'F12',
  'keyA': 'A', 'keyB': 'B', 'keyC': 'C', 'keyD': 'D',
  'keyE': 'E', 'keyF': 'F', 'keyG': 'G', 'keyH': 'H',
  'keyI': 'I', 'keyJ': 'J', 'keyK': 'K', 'keyL': 'L',
  'keyM': 'M', 'keyN': 'N', 'keyO': 'O', 'keyP': 'P',
  'keyQ': 'Q', 'keyR': 'R', 'keyS': 'S', 'keyT': 'T',
  'keyU': 'U', 'keyV': 'V', 'keyW': 'W', 'keyX': 'X',
  'keyY': 'Y', 'keyZ': 'Z',
  'digit0': '0', 'digit1': '1', 'digit2': '2', 'digit3': '3',
  'digit4': '4', 'digit5': '5', 'digit6': '6', 'digit7': '7',
  'digit8': '8', 'digit9': '9',
  'comma': ',', 'period': '.', 'semicolon': ';', 'quote': "'",
  'bracketLeft': '[', 'bracketRight': ']', 'backslash': '\\',
  'slash': '/', 'minus': '-', 'equal': '=', 'backquote': '`',
  'shiftLeft': 'Shift',
};
