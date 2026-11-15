# Windows build and validation

Build with Flutter 3.47.9 / Dart 3.13.7 and Visual Studio's Desktop C++ workload:

```powershell
flutter pub get
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter build windows --release
./tool/windows-smoke.ps1
```

The desktop GitHub Actions workflow can be dispatched on a feature branch with
`target=windows`. It creates a complete portable ZIP and an Inno Setup installer,
including the native audio libraries and the app-local Visual C++ runtime. The
Windows job checks the actual release executable: audio import, disk persistence,
native WAV decoding, seeking, volume and speed, then normal window startup.
Diagnostics are retained alongside the build artifacts. The installer is unsigned.

## Local use

Choose **Continue on this device**. In Library, import your own audio files.
Metadata and embedded/sidecar artwork are imported; adjacent `.lrc` files supply
lyrics. Tracks are copied into the application documents directory. Favorites,
playlists and playback history persist across restarts. Internet playback depends
on source availability and network access. Discord presence currently supports
Linux and macOS; its controls are disabled on Windows.

## Supabase

Set public client configuration using ignored `config.cloud.json`:

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "YOUR_PUBLIC_PUBLISHABLE_KEY"
}
```

```powershell
flutter build windows --release --dart-define-from-file=config.cloud.json
```

For Actions, use the optional `supabase_url` and `supabase_publishable_key`
workflow inputs. Never supply service-role keys or database passwords to the app.

Before cloud login/library/remote use, apply these migrations **in order** in the
Supabase SQL Editor using your project administrator account:

1. `supabase/migrations/0004_waveify_library.sql`
2. `supabase/migrations/0005_waveify_remote.sql`

They create separate `waveify_*` tables, per-user security policies and private
media storage without rewriting the existing legacy tables. Public client keys
cannot perform this administrative step. Email confirmation follows the project's
Auth settings. Cloud audio uploads are explicit; local device paths are not
playable on other devices. Native Windows validation does not certify live cloud
permissions, external music providers, audible speaker output or signed updates.
