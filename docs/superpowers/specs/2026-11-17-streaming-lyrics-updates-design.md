# Streaming, timed lyrics and in-app Windows updates

User intent: play music online without importing every file; follow real timed
lyrics; install updates from the app without uninstalling or losing the library.
Keep the app free of advertising and retain local/offline use.

Build on existing Flutter/Riverpod, just_audio/media_kit, Dio and SHA256. Audius
provides a keyless public catalog; filter stream-gated, unavailable and hidden
recordings and recheck availability before resolving their current stream URL.
Honor the provider's download flag. Keep YouTube as a separately selectable
existing provider; its availability depends on that provider and network.
Search sources are explicit: online Audius, YouTube and the user's library.
Direct audio URLs remain playable. No alternative recording is silently used
when a selected track is unavailable.

Lyrics prefer local/backend timed content and fall back to LRCLIB on backend
failure. Match title, full artist credit and known duration; do not manufacture
timings for plain lyrics. Follow the audio position after forward/backward seeks,
pause auto-scroll during manual browsing, support tap-to-seek and manual offset.

Windows updates use a versioned JSON manifest from this repository's GitHub
Release, HTTPS trust restrictions, byte count and SHA256 checks. An external
PowerShell helper waits for the running process to exit, rechecks integrity,
installs the same Inno Setup AppId in the existing directory and restarts the app.
Keep user documents and settings separate from installed files. Check quietly
at startup at most once per 12 hours, notify inside the app, download/install only
on user action. Android keeps the Google Play path; unsupported platforms are
identified accurately. Initial installation of this updater-bearing version is
an over-install; the previous build cannot gain new updater code remotely.

Publish a tagged Windows release with installer, portable ZIP and update.json.
Test actual network decoding and timed lyric lookup in the packaged executable;
exercise the production update helper against a previous installer, verify app
restart and persistent library/settings. No subscription or ad SDK is introduced.
