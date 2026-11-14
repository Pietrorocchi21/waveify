# Waveify — Istruzioni per Codex

## Panoramica
Waveify è un music player multipiattaforma (mobile, desktop, web) con account sincronizzato via Supabase.
- **Nome pacchetto**: waveify
- **Target**: Android, iOS, Web, Windows, macOS, Linux
- **Architettura**: Clean Architecture + Riverpod (state) + go_router (routing)

## Stack Tecnologico

| Area | Tecnologia | Versione |
|------|------------|----------|
| Framework | Flutter | 3.24.x |
| Linguaggio | Dart | 3.5.x |
| State Management | flutter_riverpod | 2.6.x |
| Routing | go_router | 14.6.x |
| Networking | dio | 5.7.x |
| Audio | just_audio + media_kit (libmpv) | 0.9.x / 1.2.x |
| Background Audio | audio_service + audio_session | 0.18.x / 0.1.x |
| Storage | shared_preferences, flutter_secure_storage | 2.3.x / 9.2.x |
| Backend | Supabase (PostgreSQL + Auth + Realtime) | 2.18.x |
| Desktop Window | bitsdojo_window, window_manager | 0.1.x / 0.4.x |
| Hotkeys | hotkey_manager | 0.2.x |
| Auto-update | auto_updater, in_app_update | 1.0.x / 4.2.x |
| Shaders | flutter_shaders | 0.1.x |
| CI/CD | GitHub Actions | - |

## Comandi Utili

`ash
# Dipendenze
flutter pub get
flutter pub upgrade

# Sviluppo
flutter run -d chrome          # Web
flutter run -d windows         # Windows
flutter run -d macos           # macOS
flutter run -d linux           # Linux
flutter run -d android         # Android (device/emulatore)
flutter run -d ios             # iOS (richiede macOS)

# Analisi & Formattazione
flutter analyze
dart format --set-exit-if-changed .

# Test
flutter test
flutter test --coverage

# Build Release
flutter build apk --release              # Android APK
flutter build appbundle --release        # Android AAB (Play Store)
flutter build web --release              # Web (build/web/)
flutter build windows --release          # Windows (build/windows/runner/Release/)
flutter build macos --release            # macOS (build/macos/Build/Products/Release/)
flutter build linux --release            # Linux (build/linux/x64/release/bundle/)

# Auto-updater appcast
python tool/generate_appcast.py

# Icone launcher
flutter pub run flutter_launcher_icons:main

# Supabase (locale via CLI)
supabase start           # Avvia stack locale (Docker)
supabase db push         # Applica migrazioni
supabase db diff         # Genera nuova migrazione
supabase gen types typescript --project-id <ref> > lib/supabase_types.dart
`

## Convenzioni Progetto

### Git & Branch
- **Main branch**: main (protection: required PR review + CI pass)
- **Feature branch**: eat/<scope>/<short-desc> (es. eat/audio/background-playback)
- **Fix branch**: ix/<scope>/<short-desc> (es. ix/ui/shader-crash-web)
- **Chore branch**: chore/<scope>/<short-desc> (es. chore/deps/update-riverpod)

### Commit Messages (Conventional Commits + Scope)
`
feat(audio): add background playback with audio_service
fix(ui): resolve shader compilation error on web
docs(readme): update build instructions for linux
chore(deps): upgrade flutter to 3.24.3
refactor(state): migrate provider to riverpod 2.6
perf(shader): optimize cover_ambient.frag for mobile GPU
`

### Pull Requests
- Titolo: [SCOPE] Descrizione (es. [audio] Add background playback support)
- Descrizione: Cosa + Perché + Come testare (device/simulatore)
- Checklist: lutter analyze ✓, lutter test ✓, dart format ✓
- Richiesti: Almeno 1 review + CI verde (tutte piattaforme target)
- Squash merge su main

## Struttura Cartelle Chiave

`
waveify/
├── lib/                    # Codice Dart principale
│   ├── app/                # App root, routing, theme
│   ├── core/               # Core: config, constants, errors, utils
│   ├── features/           # Feature modules (clean architecture)
│   │   ├── audio/          # Player, playlist, background, equalizer
│   │   ├── auth/           # Supabase auth, onboarding
│   │   ├── library/        # Local library, metadata, covers
│   │   ├── remote/         # Multi-device control (Supabase Realtime)
│   │   ├── settings/       # Preferences, theme, equalizer
│   │   └── sync/           # Account sync, backup, restore
│   ├── models/             # Data models (Freezed/JSON serializable)
│   ├── services/           # Servizi trasversali (Supabase, Storage, Network)
│   └── main.dart           # Entry point
├── shaders/                # Fragment shaders (.frag)
│   └── cover_ambient.frag
├── assets/                 # Asset statici
│   ├── images/
│   └── locales/            # i18n (ARB files)
├── supabase/               # Migrazioni SQL Supabase
│   └── migrations/
├── tool/                   # Script build/utility (Python)
│   ├── generate_appcast.py
│   └── add_missing_translations.py
├── .github/workflows/      # CI/CD
├── .codex/config.toml      # Config Codex Cloud (questo repo)
├── AGENTS.md               # Questo file
├── .env.example            # Template variabili d'ambiente
├── pubspec.yaml
├── analysis_options.yaml   # Linter rules
└── README.md
`

## Variabili d'Ambiente (da Secret Manager Cloud)

| Variabile | Descrizione | Obbligatoria |
|-----------|-------------|--------------|
| SUPABASE_URL | https://<project-ref>.supabase.co | **Sì** |
| SUPABASE_ANON_KEY | Chiave anonima (pubblica) | **Sì** |
| SUPABASE_SERVICE_ROLE_KEY | Chiave service role (solo admin/CI) | Solo CI |
| SUPABASE_ACCESS_TOKEN | Personal Access Token Supabase (per MCP) | Solo MCP |
| SUPABASE_PROJECT_REF | Project reference (es. bcdefghijklmnop) | **Sì** |
| WAVEIFY_DEV_SECRET | Secret per JWT dev / firme locali | Solo dev |
| API_URL | Backend API custom (se non Supabase diretto) | Opzionale |
| COVERS_PROXY_URL | Proxy per copertine album (CORS) | Opzionale |

> **MAI** committare .env reale. Il file .env.example è il template.

## Tool Preferiti

- **Editor locale**: VS Code + Flutter/Dart extensions + Riverpod snippets
- **Editor Cloud**: Codex Cloud (browser/mobile)
- **Debug**: VS Code debugger + lutter run + DevTools (browser)
- **Audio testing**: Device fisico (Bluetooth, cuffie, background)
- **Shader testing**: lutter run -d chrome --web-renderer canvaskit + DevTools
- **Database**: Supabase Dashboard (Table Editor, Logs, Realtime)
- **CI**: GitHub Actions (matrix: android, ios, web, windows, macos, linux)

## Cosa NON Fare

- ❌ Non committare .env, *.log, uild/, .dart_tool/, *.g.dart, *.freezed.dart, *.gr.dart (generated)
- ❌ Non pushare SUPABASE_SERVICE_ROLE_KEY, WAVEIFY_DEV_SECRET, chiavi reali
- ❌ Non modificare pubspec.yaml versione senza tag git corrispondente
- ❌ Non aggiungere dipendenze native (FFI/Rust/C++) senza aggiornare CI matrix
- ❌ Non disabilitare lutter analyze / dart format in CI
- ❌ Non fare force-push su main
- ❌ Non hardcodare URL Supabase / API nel codice (usa env / config)

## Testing

`ash
# Unit + Widget tests
flutter test

# Integration tests (richiede device/emulatore)
flutter test integration_test/

# Coverage report
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html

# Static analysis
flutter analyze --fatal-infos --fatal-warnings
`

## CI/CD (GitHub Actions - da configurare in .github/workflows/)

Workflow suggeriti:
| File | Trigger | Job |
|------|---------|-----|
| ci.yml | PR, push main | analyze, test, format (matrix: ubuntu-latest) |
| uild-android.yml | tag * | build APK + AAB, upload artifact |
| uild-ios.yml | tag * | build IPA (macOS runner), upload artifact |
| uild-web.yml | tag * | build web, deploy Firebase/Vercel/Netlify |
| uild-desktop.yml | tag * | build windows/macos/linux, upload artifacts |
| supabase-migrations.yml | push main | supabase db push su progetto staging/prod |

## Shader (fragment) - Note Speciali

- File: shaders/cover_ambient.frag
- Testare su: Chrome (CanvasKit), Windows (ANGLE), macOS (Metal), Linux (Vulkan), Mobile (OpenGL ES)
- lutter_shaders package gestisce compilazione runtime
- Modifiche shader → testare su tutte le piattaforme target prima di merge

## i18n / Localizzazione

- File ARB in ssets/locales/ (intl_<locale>.arb)
- Aggiungere stringhe: lutter gen-l10n (configurato in pubspec.yaml)
- Script helper: python tool/add_missing_translations.py

---

*Ultimo aggiornamento: 2026-11-14*
*Versione: 1.0*
