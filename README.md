# [DashCam Player](https://santos-k.github.io/Dashcam-Video-Player/)

A cross-platform Flutter desktop app that plays paired dashcam front/back videos side by side with synchronized controls, variable speed playback, GPS map integration, and FFmpeg-powered video export.

**Live site:** https://santos-k.github.io/Dashcam-Video-Player/

![DashCam Player - Side by side view](assets/screenshots/side_by_side.png)

---

## Screenshots

| View | Screenshot |
|---|---|
| **Welcome Screen** — Clean landing page with 3-column shortcut reference | ![Landing](assets/screenshots/landing.png) |
| **Side by Side** — Front and back cameras playing in perfect sync | ![Side by Side](assets/screenshots/side_by_side.png) |
| **Stacked Layout** — Front on top, back below for wide monitors | ![Stacked](assets/screenshots/stacked.png) |
| **Picture-in-Picture** — Draggable PIP overlay with GPS coordinates | ![PIP](assets/screenshots/pip.png) |
| **Clip Browser** — Sortable drawer with timestamps and pairing badges | ![Clips](assets/screenshots/clips.png) |
| **GPS Map** — Interactive OpenStreetMap sidebar with coordinate search | ![Map](assets/screenshots/map.png) |
| **Map + Playback** — Review footage alongside GPS position | ![Map Sidebar](assets/screenshots/map_sidebar.png) |

---

## Features

| Feature | Details |
|---|---|
| Dual video playback | Front + back cameras synced side by side |
| Auto file pairing | Matches by timestamp (±5s tolerance) from video_front/video_back folders or F/B filename suffixes |
| 3 layout modes | Side-by-side, Stacked, Picture-in-Picture (key 1/2/3) |
| PIP controls | Draggable, resizable overlay with position memory. Key 3 toggles primary camera |
| Variable speed | 11 levels from 0.1x to 5x. Speed persists across clips. Keys [ ] \ |
| Sync offset | ±5000ms slider to compensate for recording start differences |
| GPS & Map | Interactive OpenStreetMap sidebar with device location, tile layers, Google Maps link |
| FFmpeg export | Export composed videos in any layout with H.264. Sync offset applied automatically |
| Batch save | Select multiple clips, real-time progress counter (e.g. "2/6 saved") |
| Audio control | Independent front/back mute (F/B keys) |
| Smart UI | Auto-hide controls after 5s inactivity, video fills full screen |
| 20+ shortcuts | Full keyboard control for every feature |
| Fullscreen | Shift key toggles fullscreen with wakelock |

---

## Keyboard Shortcuts

### Playback
| Key | Action |
|---|---|
| `Space` | Play / Pause |
| `← →` | Seek ±10 seconds |
| `Shift+.` | Next clip |
| `Shift+,` | Previous clip |
| `[ ]` | Decrease / increase speed |
| `\` | Reset speed to 1x |

### Layout & View
| Key | Action |
|---|---|
| `1` | Side by side |
| `2` | Stacked |
| `3` | PIP (toggle primary camera) |
| `L` | Layout popup |
| `Shift` | Toggle fullscreen |

### Panels
| Key | Action |
|---|---|
| `C` | Toggle clip list |
| `M` | Toggle map sidebar |
| `I` | Toggle about |
| `Esc` | Close overlay |

### Audio
| Key | Action |
|---|---|
| `F` | Mute front (or single camera) |
| `B` | Mute back camera |

### File Operations
| Key | Action |
|---|---|
| `O` | Open dashcam folder |
| `S` | Save clips to folder |
| `E` | Export composed video |
| `W` | Close folder |
| `R` | Toggle sort order |
| `Q` | Quit application |

---

## Project Structure

```
lib/
  main.dart                      App entry point (ProviderScope + MaterialApp)
  models/
    video_pair.dart              VideoPair data class
    layout_config.dart           LayoutMode / PipPrimary / alignment enums
  providers/
    app_providers.dart           All Riverpod providers & notifiers
  utils/
    file_pairer.dart             F/B file matching logic
  services/
    export_service.dart          FFmpeg export (side-by-side / stacked / PIP)
    log_service.dart             File-based logging
  screens/
    player_screen.dart           Main screen with all keyboard shortcuts
  widgets/
    dual_video_view.dart         Renders the two video players
    playback_controls.dart       Transport bar, speed, sync, export, save
    layout_selector.dart         Layout & PIP options popup
    clip_list_drawer.dart        Side drawer listing all pairs
    map_dialog.dart              OpenStreetMap sidebar with GPS
```

---

## Getting Started

### Requirements

- **Windows 10+** (64-bit x64)
- **Flutter SDK** 3.0+ ([install](https://docs.flutter.dev/get-started/install))
- **Visual Studio 2022** with "Desktop development with C++" workload
- **FFmpeg** on PATH (optional, for video export only — [download](https://ffmpeg.org/download.html))

### Run from Source

```bash
flutter pub get
flutter run -d windows
```

### Build Release

```bash
flutter build windows --release
```

Output: `build/windows/x64/runner/Release/`

### Windows Installer

Build the installer with [InnoSetup](https://jrsoftware.org/isinfo.php) using `installer.iss`.

---

## Dashcam File Structure

The app supports two folder layouts:

**Separate directories** (preferred):
```
SD_Card/
  video_front/          Normal front clips
  video_back/           Normal back clips
  video_front_lock/     Protected front clips
  video_back_lock/      Protected back clips
```

**Single directory with suffixes:**
```
Folder/
  20240315_143022F.mp4    Front camera
  20240315_143022B.mp4    Back camera
```

Supported formats: `.mp4`, `.ts`, `.avi`, `.mkv`

---

## Sync Offset

The slider range is **−5000 ms to +5000 ms**.

- **Positive offset** (+N ms): front video starts N ms later than back. The app seeks back forward to align.
- **Negative offset** (−N ms): back video starts N ms later. Front is seeked forward.

During export, FFmpeg applies `-itsoffset` to match.

---

## Adding a New Layout Mode

1. Add a value to `LayoutMode` in `models/layout_config.dart`
2. Handle it in `DualVideoView` switch statement
3. Add FFmpeg filter graph case in `ExportService._buildFilterGraph()`
4. Add UI option in `widgets/layout_selector.dart`

---

## Tech Stack

- **Flutter 3.0+** — Cross-platform desktop UI
- **media_kit** — Video playback (replaces deprecated video_player)
- **flutter_riverpod** — Reactive state management
- **flutter_map** + **latlong2** — Interactive OpenStreetMap
- **window_manager** — Desktop window control
- **FFmpeg** — Video composition & export (system CLI)

---

## Version History

| Version | Highlights |
|---|---|
| 1.2.0 | Variable speed (0.1x–5x), redesigned landing page, auto-hide controls, save progress, toggle shortcuts, PIP primary swap, instant quit |
| 1.1.1 | PIP bounds fix, shortcuts overhaul, export improvements, About popup, landing page |
| 1.1.0 | Interactive map sidebar, ref-after-dispose fix |
| 1.0.0 | Initial release: dual playback, sync, export, PIP |
