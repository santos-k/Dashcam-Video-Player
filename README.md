# DashCam Player — Flutter App

A cross-platform Flutter app (Windows, Android, iOS) that plays paired dashcam
front/back videos side-by-side with full sync controls and export capability.

---

## Features

| Feature | Status |
|---|---|
| Dual video playback (front + back, side by side) | ✅ |
| Automatic F/B file pairing by timestamp | ✅ |
| Next/previous clip navigation | ✅ |
| Manual sync slider (±5 s) | ✅ |
| Side-by-side, stacked, and PIP layouts | ✅ |
| PIP: choose primary video & corner | ✅ |
| Export composed video via FFmpeg | ✅ |
| Responsive layout (portrait + landscape) | ✅ |
| Windows, Android, iOS | ✅ |

---

## Project structure

```
lib/
  main.dart                      ← App entry point (ProviderScope + MaterialApp)
  models/
    video_pair.dart              ← VideoPair data class
    layout_config.dart           ← LayoutMode / PipPrimary / PipCorner enums + config
  providers/
    app_providers.dart           ← All Riverpod providers & notifiers
  utils/
    file_pairer.dart             ← F/B file matching logic
  services/
    export_service.dart          ← FFmpeg export (side-by-side / stacked / PIP)
  screens/
    player_screen.dart           ← Main screen
  widgets/
    dual_video_view.dart         ← Renders the two VideoPlayer widgets
    playback_controls.dart       ← Transport bar + sync slider
    layout_selector.dart         ← Bottom sheet for layout/PIP options
    clip_list_drawer.dart        ← Side drawer listing all pairs
```

---

## Step 1 — Install Flutter

1. Download the Flutter SDK from https://docs.flutter.dev/get-started/install
2. Add `flutter/bin` to your PATH.
3. Run `flutter doctor` and resolve any issues.
4. Install platform tools:
   - **Android**: Android Studio + Android SDK (API 33+)
   - **iOS**: Xcode 15+ (macOS only)
   - **Windows**: Visual Studio 2022 with "Desktop development with C++"

---

## Step 2 — Create the project

```bash
flutter create dashcam_player
cd dashcam_player
```

Replace the generated files with the source files in this repository.

---

## Step 3 — Install dependencies

```bash
flutter pub get
```

Key packages used:
- `video_player` — platform video playback
- `flutter_riverpod` — state management
- `file_picker` — folder/file selection dialog
- `ffmpeg_kit_flutter_full_gpl` — video export/compositing
- `permission_handler` — runtime permissions (Android/iOS)
- `wakelock_plus` — prevent screen sleep during playback
- `share_plus` — share exported file

---

## Step 4 — Platform configuration

### Android

Edit `android/app/src/main/AndroidManifest.xml`:
- Add the permissions from `android_permissions_snippet.xml`
- Add the FileProvider entry for share_plus

Set minimum SDK to 21 in `android/app/build.gradle`:
```gradle
defaultConfig {
    minSdkVersion 21
    targetSdkVersion 34
}
```

### iOS

Edit `ios/Runner/Info.plist`:
- Add the keys from `ios_info_plist_snippet.xml`

In `ios/Podfile`, set the minimum iOS version:
```ruby
platform :ios, '14.0'
```

Run `pod install` in the `ios/` directory.

### Windows

No manifest changes needed for development builds.
See `windows_notes.txt` for MSIX distribution.

---

## Step 5 — Dashcam file naming

The app expects files named:

```
<timestamp>F.<ext>   ← front camera
<timestamp>B.<ext>   ← back camera
```

Supported formats:
- `20240315_143022F.mp4` + `20240315_143022B.mp4`
- `2024-03-15_14-30-22F.MP4` + `2024-03-15_14-30-22B.MP4`
- `20240315143022F.avi` + `20240315143022B.avi`

Both files must be in the **same folder**, or you can use
`FilePairer.pairFromTwoDirectories()` if they are in separate front/back folders.

---

## Step 6 — Run the app

```bash
# Android (USB debugging enabled)
flutter run -d android

# iOS (physical device or simulator)
flutter run -d ios

# Windows desktop
flutter run -d windows

# Debug in Chrome (no video playback — web not supported for this app)
# NOT recommended
```

---

## Step 7 — Using the app

1. Tap the **folder icon** (top right) to open a dashcam folder.
2. The app automatically pairs F/B files and loads the first pair.
3. Use **Play/Pause** and the **seek bar** to control playback.
4. **⏮ / ⏭** skip to the previous/next pair.
5. Tap **Sync** to reveal the offset slider. Drag to compensate for recording
   start differences (±5 seconds range).
6. Tap the **layout icon** to switch between side-by-side, stacked, and PIP.
   In PIP mode, choose which video is primary and which corner the overlay sits in.
7. Tap the **share icon** to export the current pair as a composited MP4.
   The export uses FFmpeg and may take 1–5× the clip duration.
8. Open the **hamburger menu** to see all loaded clips and jump to any pair.

---

## Sync slider — how it works

The slider range is **−5000 ms to +5000 ms**.

- **Positive offset** (+N ms) means the **front video starts N ms later** than
  the back. The app seeks the back video forward by N ms so both appear at the
  same real-world moment.
- **Negative offset** (−N ms) means the **back video starts N ms later**.
  The front is seeked forward instead.

During export, `ffmpeg_kit` applies `-itsoffset` to compensate, so the
exported file is always in sync regardless of original offset.

---

## Adding your own layout

1. Add a new value to `LayoutMode` in `models/layout_config.dart`.
2. Handle it in `DualVideoView._build()` switch statement.
3. Add a filter graph case to `ExportService._buildFilterGraph()`.
4. Add a chip in `_LayoutSheet` in `widgets/layout_selector.dart`.

---

## Known limitations

- **Web** is not supported — `video_player` and `ffmpeg_kit` require native
  platform APIs.
- **Export progress** is estimated (assumes 5-minute clip max). The FFmpeg
  statistics API does not expose total duration.
- **PIP drag-to-reposition** is not implemented (corner selection only).
  Adding `Draggable` + `DragTarget` around the PIP widget is straightforward.
- **Audio** from the back camera is discarded in the exported file. Extend
  `ExportService` with `-map 1:a?` if you need it.