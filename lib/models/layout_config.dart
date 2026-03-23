// lib/models/layout_config.dart

enum LayoutMode  { sideBySide, stacked, pip }
enum PipPrimary  { front, back }
enum PipHAlign   { left, center, right }
enum PipVAlign   { top, center, bottom }

class LayoutConfig {
  final LayoutMode mode;
  final PipPrimary pipPrimary;
  final PipHAlign  pipHAlign;
  final PipVAlign  pipVAlign;

  const LayoutConfig({
    this.mode      = LayoutMode.sideBySide,
    this.pipPrimary = PipPrimary.front,
    this.pipHAlign  = PipHAlign.right,
    this.pipVAlign  = PipVAlign.top,
  });

  LayoutConfig copyWith({
    LayoutMode?  mode,
    PipPrimary?  pipPrimary,
    PipHAlign?   pipHAlign,
    PipVAlign?   pipVAlign,
  }) => LayoutConfig(
    mode:       mode       ?? this.mode,
    pipPrimary: pipPrimary ?? this.pipPrimary,
    pipHAlign:  pipHAlign  ?? this.pipHAlign,
    pipVAlign:  pipVAlign  ?? this.pipVAlign,
  );
}