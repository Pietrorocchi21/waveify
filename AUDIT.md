# Waveify audit and remediation log

## File safe to keep

- `lib/app.dart`
- `lib/main.dart`
- `lib/core/config/app_config.dart`
- `lib/core/network/api_client.dart`
- `lib/core/network/waveify_api.dart`
- `lib/core/providers/app_providers.dart`
- `lib/models/track.dart`
- `lib/models/catalog.dart`
- `lib/core/storage/app_settings.dart`
- `lib/core/theme/app_theme.dart`
- `lib/features/player/audio_handler.dart`
- `lib/features/auth/*`
- `lib/features/downloads/*`
- `lib/features/remote/*`
- `assets/locales/*.json` (after sanitization)

## Files to remove

- Any file that contains proprietary Liner client logic, request-signing code, or direct Liner endpoints
- `signer/` Rust project and request-signing implementation
- `lib/core/crypto/liner_signer.dart`
- `lib/core/media/innertube/*` files containing Liner-specific protocol logic (historical sources)
- `lib/features/covers/cover_proxy.dart`
- `lib/features/player/ui/kawarp_visualizer.dart`
- `shaders/kawarp.frag`
- `tool/probe_*` scripts that targeted Liner-specific backends

## Files rewritten from zero

- `lib/core/network/api_client.dart` rewritten as a standard auth client without custom signing
- `lib/core/deeplink/deeplink_parser.dart` rewritten to use `waveify://` instead of `liner://`
- `lib/core/deeplink/deeplink_service.dart` rewritten to use the generic wire format
- `lib/core/config/app_config.dart` sanitized to use generic defaults and environment variables
- `lib/core/media/innertube/*.dart` reintroduced as neutral, compile-safe stubs

## Dependencies to remove

- Any dependency carrying Liner-proprietary code or a fork tied to Liner
- Any package whose source or distribution contract is incompatible with public release

## Dependencies to replace

- `just_audio` / `audio_service` remain valid, as they are standard and compatible
- `dio` remains valid for generic HTTP requests
- `flutter_riverpod` remains valid for app state management
- `go_router` remains valid for navigation
- `app_links` remains valid for standard deep-link registration

## Graphics, audio, and fonts to remove

- Any visual asset copied from proprietary Liner branding or animation sequences
- Custom shader effects that replicated Liner visual identity
- Media assets or branded app icons tied to Liner

## Potentially problematic algorithms or subsystems

- Request signing and nonce/timestamp canonicalization
- Obfuscated key reconstruction
- Cover proxying and signed cover URLs
- Stream resolver and format negotiation tied to proprietary catalog services
- Anti-bot bypass logic and provider signatures
- Proprietary lyrics formats such as RichSync or QRC ad hoc stacks

## Liner references and risk classification

### SAFE
- Generic Flutter app scaffolding
- Standard networking, routing, and local storage
- Waveify-specific player logic and app state

### REPLACE
- Deep-link scheme, request signing, and API auth flow
- Cover and stream resolution utilities
- Catalog access layers that depended on external provider-specific contracts

### REMOVE
- `liner://` deep links and Liner naming
- `tryliner.fun` and `covers.tryliner.fun` defaults
- `LinerSigner`, request headers like `x-liner-*` and `RequestSigner`
- Any identifier, secret, or backend endpoint tied to Liner infrastructure

### REVIEW
- External media-provider integrations that need explicit permission and compatible licenses
- Any third-party backend services used for catalog, lyrics, or playback

## Notes

This private record is intentionally kept in the repository root for the remediation record but is not part of the public distribution set; the project is cleaned to use original Waveify code and standard-compatible dependencies only.
