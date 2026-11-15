# WAVEIFY interface refresh

The implementation keeps Flutter, Riverpod, go_router, the existing Material icon
set and the audio controller. No dependency or audio engine was added.

## Visual decisions

- Near-black and midnight-blue canvas with a restrained radial wash. The default
  accent is pale blue; existing saved theme and brand choices remain available.
- Artwork colours come from the existing palette_generator dependency. Extraction
  uses a 64px image, eight colours and a three-second timeout, with the selected
  brand colour as fallback. Position ticks do not retrigger palette extraction.
- Shared design tokens own typography, colour foundations, radii and transition
  durations. GlassPanel supplies clipped blur and an independent readable tint;
  high-contrast mode uses an opaque surface without blur. Repeated list cards
  use tint only. The ambient background has no perpetual animation.
- Home displays actual mixes/history. The artwork carousel uses scale, perspective and opacity,
  explicit playback, swipe and labelled previous/next controls. Empty mixes have
  a disabled play action. No demonstration music or external artwork ships.
- The main listening scene uses a central, unframed cover, smaller tilted
  neighbours, soft shadows, and metadata below the artwork. Desktop
  navigation is an icon rail; the centred dock has a maximum width of 940px.
  Mix/history shelves remain below the scene instead of competing with it.
- The full player uses the same scene. Lyrics and speed/pitch remain available
  through labelled actions that open their existing controls in a sheet.
- Desktop navigation and mobile navigation expose the same existing routes.
  On mobile, Offline, Remote and Settings are in the More menu. The player dock
  occupies normal layout space above the navigation and respects safe areas.
- The mini-player opens the existing full player. Seek, volume, repeat, shuffle,
  queue, likes, lyrics and speed/pitch continue to use existing controllers.
  Cover failures and missing covers have a consistent visual fallback.
- Wallpaper and block customization remain connected. Buttons use Material focus,
  keyboard activation, tooltips and at least 48px icon-button touch targets.

## Repairs needed to make the existing interface usable

Fixed missing UI imports, invalid shell-escaped Dart strings in Library, missing
collection IDs in navigation, incorrect playlist model fields, duplicate queue
row keys and a downloads load that read Riverpod state before initialization.
The standalone scratch package write_temp is excluded from app analysis.
Fixed bounded desktop window dragging, wrapping search filters and library
actions, scrollable empty states and bounded mobile lyrics/speed panels.

## Verification

Run the standard suite with `flutter test` and static checks with
`flutter analyze --no-fatal-infos`. Existing advisory lints in networking/provider
code are outside this visual refresh.

`test/ui/redesign_test.dart` exercises real screens with an in-memory API,
session, downloads store and observable player. It checks 1440×1000, 390×844
and 320×640 layouts, dock separation, transport, full-player entry, queue,
keyboard activation and high-contrast fallback. Test fixtures include original abstract artwork rendered in memory and a
separate missing-cover check. No images are fetched from external services. They are not production data.

Optional local captures (not pixel-based CI assertions):

```sh
flutter test test/ui/redesign_test.dart --dart-define=CAPTURE_UI=true
```

Captures use the SDK's Roboto/Material fonts and are written to
`waveify-previews` under the system temporary directory. Override with
`--dart-define=UI_CAPTURE_DIR=/path/to/previews`. No iBaila assets are redistributed.
The reference page and one official promotional screenshot were inspected;
interactive browser tools were unavailable. Native playback, signing, system
blur performance and real backend/Supabase connectivity require a configured
device/build environment and are not established by widget tests.
