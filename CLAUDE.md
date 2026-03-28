# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dashcam Video Player is a Flutter desktop app (primarily Windows) that plays paired front/back dashcam videos side-by-side with synchronized controls and exports composited videos via system FFmpeg. Version 1.1.1, Dart 3.0+/Flutter 3.0+.

## Common Commands

```bash
# Install dependencies
flutter pub get

# Run on Windows desktop
flutter run -d windows

# Release build (output: build/windows/x64/runner/Release/)
flutter build windows --release

# Static analysis (linting)
flutter analyze

# Run all tests
flutter test

# Run a single test file
flutter test test/<file>_test.dart
```

The Windows installer is built via InnoSetup using `installer.iss`.

## Architecture

**State management:** flutter_riverpod (reactive providers, no BuildContext needed). All providers live in `lib/providers/app_providers.dart` (~14 providers including sort order, video pair list, current index, layout config, sync offset, playback state, export progress, map state, mute toggles, and PIP position).

**Video playback:** Two independent `media_kit.Player` instances (front + back camera) managed by `PlaybackNotifier` (StateNotifier). Sync is achieved by pre-seeking the appropriate player by the offset amount.

**Key data flow:**
1. User selects folder -> `FilePairer.pairFromRoot()` scans for front/back video pairs
2. Pairs populate `videoPairListProvider` -> selecting a pair triggers `PlaybackNotifier.loadPair()`
3. Two media_kit Players open simultaneously, synced via `applySyncOffset()`
4. Export composes videos via system FFmpeg process (`Process.start()`) with filter graphs (hstack/vstack/overlay)

**File pairing logic** (`lib/utils/file_pairer.dart`): Supports two folder structures:
- Separate directories: `video_front/`, `video_back/`, `video_front_lock/`, `video_back_lock/`
- Single directory with F/B suffix in filename (e.g., `20240315_143022F.mp4`)
- Matches by timestamp with +/-5 second tolerance

## Key Source Files

| File | Role |
|---|---|
| `lib/providers/app_providers.dart` | All Riverpod state (providers + notifiers) |
| `lib/screens/player_screen.dart` | Main UI screen, keyboard shortcuts, fullscreen |
| `lib/widgets/dual_video_view.dart` | Renders two video players in side-by-side/stacked/PIP layouts |
| `lib/widgets/playback_controls.dart` | Transport controls + sync offset slider |
| `lib/services/export_service.dart` | FFmpeg process spawning, filter graph construction, progress parsing |
| `lib/utils/file_pairer.dart` | Dashcam file discovery and front/back matching |
| `lib/models/layout_config.dart` | LayoutMode, PipPrimary, alignment enums |
| `lib/services/log_service.dart` | File-based logging (daily rollover, `appLog()` function) |

## Adding a New Layout Mode

1. Add value to `LayoutMode` in `models/layout_config.dart`
2. Handle in `DualVideoView` switch statement
3. Add FFmpeg filter graph case in `ExportService._buildFilterGraph()`
4. Add UI chip in `_LayoutSheet` in `widgets/layout_selector.dart`

## External Dependencies

- **FFmpeg** must be installed on the system PATH for video export (not bundled; invoked via `Process.start()`)
- **media_kit** handles video playback (replaces deprecated video_player plugin)
- **window_manager** controls desktop window sizing/fullscreen
- Dark theme with Material 3, seed color `0xFF4FC3F7` (cyan)
