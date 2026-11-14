# Waveify

Waveify is an original multi-platform music player built with Flutter. It is designed for local-first playback, self-hosted or custom backends, and clear ownership of the application code and assets.

## Features

- Multi-platform Flutter app for Android, iOS, macOS, Linux, and Windows
- Local library and user-managed playlists
- Playback controls, queue management, shuffle, repeat, and favorites
- Background and system-device integrations
- Self-hosted backend configuration through environment variables
- Offline download support for locally owned media
- Deep links using a custom `waveify://` scheme

## Project structure

```text
lib/
  app/
  core/
  features/
  models/
  shared/
  main.dart
assets/
  locales/
  images/
shaders/
linux/
macos/
windows/
android/
ios/
```

## Requirements

- Flutter 3.47.9 (versione fissata nei workflow)
- Dart 3.13.7, incluso in Flutter: non installarlo separatamente
- Per Windows: Visual Studio con il workload Desktop development with C++, MSVC, CMake e Windows SDK; verificare con `flutter doctor -v`
- Optional backend service for synced catalog and user data

## Local setup

```bash
flutter --version
dart --version
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build windows --debug
flutter run -d windows
```

Su Windows usare un percorso SDK senza spazi o parentesi. Se il terminale
era aperto prima dell'aggiornamento del PATH, riaprirlo. Se `flutter doctor -v`
segnala un'installazione incompleta di Visual Studio, completarla tramite
Visual Studio Installer prima della build Windows.

To point the app at a custom backend:

```bash
flutter run --dart-define=API_URL=https://api.example.com
flutter run --dart-define=COVERS_PROXY_URL=https://images.example.com
```

When `API_URL` is unset, the app stays in local/offline mode instead of forcing a localhost dependency.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `API_URL` | empty | Base URL of the Waveify backend; leave empty for offline/local-first mode |
| `COVERS_PROXY_URL` | empty | Cover or artwork CDN; leave empty for offline/local-first mode |
| `CLIENT_VERSION` | `1.0.0-flutter` | Client version header |
| `UPDATE_FEED_URL` | GitHub Releases appcast URL | Desktop updater feed used by `auto_updater` |

## Automatic updates

Waveify ships with a desktop updater based on the `auto_updater` package. The app checks the appcast at `releases/latest/download/appcast.xml` by default, and if a newer build is available, the native updater downloads it and restarts the app for the update.

The GitHub desktop workflow creates a release and publishes an `appcast.xml` alongside the packaged Windows/macOS installers. For the release to be trusted, the release secrets must be configured:

- `WINDOWS_DSA_SIGNATURE`: the Sparkle/WinSparkle DSA signature for the Windows installer
- `MACOS_ED_SIGNATURE`: the Sparkle EdDSA signature for the macOS zip

Once set, the app will check for updates automatically on supported desktop builds. Android still uses the store update flow; Linux does not participate in the desktop in-place updater.

## License

This project is distributed under the MIT license. See `LICENSE` for details.

## Privacy and rights

Use only media and playlists you have the legal right to access, play, and redistribute. Waveify does not grant permission to use protected content outside the applicable terms of the source provider or the user’s rights.
