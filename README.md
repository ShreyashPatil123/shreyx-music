# ShreyX Player (Flutter Edition)

**Autonomous, 100% Standalone Music Player for Android & iOS**

---

## Key Highlights

- **Zero PC Hosting**: Streams are resolved directly on your phone using `youtube_explode_dart`. Your computer does not need to be turned on or hosting any local servers.
- **True Background Playback & Lock Screen Transport**: Powered by `just_audio` and `audio_service`, audio continues uninterrupted with the screen locked or app minimized.
- **Grouped Offline Downloads**:
  - Downloaded playlist tracks stay grouped under that playlist.
  - Individual downloaded songs are grouped under **"Standalone Tracks"**.
  - 100% offline playback from device storage (`.m4a`).
- **High-Precision Song Scrubber Bar**:
  - Fully functional seeking forward and backward.
  - Smooth live duration tracking (`mm:ss / mm:ss`).
  - Direct tap and drag-to-seek.
- **No Redundant Sound Bar**:
  - The volume slider has been removed from the UI so it never interferes with track seeking. Volume is cleanly controlled with your phone's physical volume buttons.
- **Synced Lyrics**:
  - Real-time synced scrolling lyrics powered by LRCLIB. Tap any lyric line to jump directly to that timestamp.

---

## Getting the Standalone APK onto your Phone

### Method A: Build via GitHub Actions (Recommended — No Local Setup Needed)

Since this project contains a ready-to-go GitHub Actions workflow (`.github/workflows/build_apk.yml`):

1. Initialize git and push this repository to GitHub:
   ```bash
   git init
   git add .
   git commit -m "Initial commit of ShreyX Flutter"
   git remote add origin https://github.com/<your-username>/shrex_flutter.git
   git push -u origin main
   ```
2. Navigate to your repository on GitHub and click the **Actions** tab.
3. The **"Build Standalone Android APK"** action will run automatically (takes ~3 minutes).
4. When finished, click the workflow run and download the `ShreyX-Release-APK` artifact.
5. Transfer the downloaded `app-release.apk` to your phone and install it!

---

### Method B: Build Locally (If Flutter & Android SDK are installed)

```bash
# Fetch dependencies
flutter pub get

# Run on connected phone
flutter run

# Or build standalone release APK
flutter build apk --release --no-tree-shake-icons
```
Output location: `build/app/outputs/flutter-apk/app-release.apk`.
