// lib/models/layout_config.dart

/// The three possible viewing layouts.
enum LayoutMode {
  sideBySide,   // Front | Back  (horizontal split)
  stacked,      // Front on top, Back below (vertical split)
  pip,          // One video fullscreen, smaller overlay in corner
}

/// Which video is primary (large) in PIP mode.
enum PipPrimary { front, back }

/// Which corner the PIP overlay sits in.
enum PipCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Full layout configuration snapshot.
class LayoutConfig {
  final LayoutMode mode;
  final PipPrimary pipPrimary;
  final PipCorner  pipCorner;

  const LayoutConfig({
    this.mode       = LayoutMode.sideBySide,
    this.pipPrimary = PipPrimary.front,
    this.pipCorner  = PipCorner.bottomRight,
  });

  LayoutConfig copyWith({
    LayoutMode?  mode,
    PipPrimary?  pipPrimary,
    PipCorner?   pipCorner,
  }) =>
      LayoutConfig(
        mode:       mode       ?? this.mode,
        pipPrimary: pipPrimary ?? this.pipPrimary,
        pipCorner:  pipCorner  ?? this.pipCorner,
      );
}