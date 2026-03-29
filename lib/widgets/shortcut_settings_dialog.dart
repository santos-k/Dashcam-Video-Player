// lib/widgets/shortcut_settings_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shortcut_action.dart';
import '../providers/app_providers.dart';

/// Full-screen dialog for viewing and remapping keyboard shortcuts.
class ShortcutSettingsDialog extends ConsumerStatefulWidget {
  const ShortcutSettingsDialog({super.key});

  @override
  ConsumerState<ShortcutSettingsDialog> createState() =>
      _ShortcutSettingsDialogState();
}

class _ShortcutSettingsDialogState
    extends ConsumerState<ShortcutSettingsDialog> {
  ShortcutAction? _capturing; // action currently being rebound
  final FocusNode _captureFocus = FocusNode();

  @override
  void dispose() {
    _captureFocus.dispose();
    super.dispose();
  }

  void _startCapture(ShortcutAction action) {
    setState(() => _capturing = action);
    _captureFocus.requestFocus();
  }

  void _cancelCapture() {
    setState(() => _capturing = null);
  }

  void _onCaptureKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (_capturing == null) return;

    final key = event.logicalKey;

    // Escape cancels capture
    if (key == LogicalKeyboardKey.escape) {
      _cancelCapture();
      return;
    }

    // Ignore modifier-only presses
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight) {
      // But allow shiftLeft as a binding target (fullscreen uses it)
      if (key == LogicalKeyboardKey.shiftLeft) {
        final keyId = reverseKeyMap[key];
        if (keyId != null) {
          ref.read(shortcutConfigProvider.notifier)
              .updateBinding(_capturing!, KeyBinding(keyId, shift: false));
          setState(() => _capturing = null);
        }
      }
      return;
    }

    // Look up key in our map
    final keyId = reverseKeyMap[key];
    if (keyId == null) return; // unknown key, ignore

    final shift = HardwareKeyboard.instance.isShiftPressed;
    ref.read(shortcutConfigProvider.notifier)
        .updateBinding(_capturing!, KeyBinding(keyId, shift: shift));
    setState(() => _capturing = null);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(shortcutConfigProvider);

    return KeyboardListener(
      focusNode: _captureFocus,
      onKeyEvent: _capturing != null ? _onCaptureKey : (_) {},
      child: Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
          child: Column(children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              decoration: const BoxDecoration(
                color: Color(0xFF222222),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(children: [
                const Icon(Icons.keyboard_rounded,
                    color: Color(0xFF4FC3F7), size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Keyboard Shortcuts',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(shortcutConfigProvider.notifier).resetToDefaults();
                  },
                  child: const Text('Reset all',
                      style:
                          TextStyle(fontSize: 11, color: Colors.white38)),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white38, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),

            // Capture banner
            if (_capturing != null)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                color: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
                child: Row(children: [
                  const Icon(Icons.keyboard_alt_outlined,
                      color: Color(0xFF4FC3F7), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Press a key for "${actionDisplayNames[_capturing]}"   (Esc to cancel)',
                      style: const TextStyle(
                          color: Color(0xFF4FC3F7), fontSize: 12),
                    ),
                  ),
                  GestureDetector(
                    onTap: _cancelCapture,
                    child: const Text('Cancel',
                        style:
                            TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
                ]),
              ),

            // Shortcut list grouped by category
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final category in actionCategories.entries) ...[
                    _CategoryHeader(category.key),
                    for (final action in category.value)
                      _ShortcutRow(
                        action: action,
                        binding: config[action],
                        isDefault: config[action] ==
                            ShortcutConfig.defaults()[action],
                        isCapturing: _capturing == action,
                        conflict: _findConflict(config, action),
                        onTap: () => _startCapture(action),
                        onReset: () {
                          ref
                              .read(shortcutConfigProvider.notifier)
                              .updateBinding(
                                  action,
                                  ShortcutConfig.defaults()[action]);
                        },
                      ),
                  ],
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              decoration: const BoxDecoration(
                color: Color(0xFF222222),
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    color: Colors.white24, size: 14),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Click a shortcut to rebind. Changes are saved automatically.',
                    style:
                        TextStyle(color: Colors.white30, fontSize: 10),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done',
                      style: TextStyle(color: Color(0xFF4FC3F7))),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// Check if a given action's binding conflicts with another action.
  String? _findConflict(ShortcutConfig config, ShortcutAction action) {
    final binding = config[action];
    for (final other in ShortcutAction.values) {
      if (other == action) continue;
      if (config[other] == binding) {
        return actionDisplayNames[other];
      }
    }
    return null;
  }
}

// ─── Category header ────────────────────────────────────────────────────────

class _CategoryHeader extends StatelessWidget {
  final String title;
  const _CategoryHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(title,
          style: const TextStyle(
            color: Color(0xFF4FC3F7),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          )),
    );
  }
}

// ─── Single shortcut row ────────────────────────────────────────────────────

class _ShortcutRow extends StatelessWidget {
  final ShortcutAction action;
  final KeyBinding binding;
  final bool isDefault;
  final bool isCapturing;
  final String? conflict;
  final VoidCallback onTap;
  final VoidCallback onReset;

  const _ShortcutRow({
    required this.action,
    required this.binding,
    required this.isDefault,
    required this.isCapturing,
    this.conflict,
    required this.onTap,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        color: isCapturing
            ? const Color(0xFF4FC3F7).withValues(alpha: 0.08)
            : null,
        child: Row(children: [
          // Action name
          Expanded(
            child: Text(
              actionDisplayNames[action] ?? action.name,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),

          // Conflict warning
          if (conflict != null) ...[
            Tooltip(
              message: 'Conflicts with "$conflict"',
              child: const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 14),
            ),
            const SizedBox(width: 6),
          ],

          // Key badge
          if (isCapturing)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF4FC3F7).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: const Color(0xFF4FC3F7).withValues(alpha: 0.5)),
              ),
              child: const Text('Press a key...',
                  style: TextStyle(
                      color: Color(0xFF4FC3F7),
                      fontSize: 11,
                      fontStyle: FontStyle.italic)),
            )
          else
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isDefault
                        ? Colors.white.withValues(alpha: 0.1)
                        : const Color(0xFF4FC3F7).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  binding.label,
                  style: TextStyle(
                    color: isDefault ? Colors.white54 : const Color(0xFF4FC3F7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),

          // Reset button (only if customized)
          if (!isDefault) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Reset to default',
              child: GestureDetector(
                onTap: onReset,
                child: const Icon(Icons.undo_rounded,
                    color: Colors.white30, size: 14),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
