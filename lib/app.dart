import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/i18n/translator.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/app_providers.dart';
import 'app/router.dart';

/// The root widget of the app.
class WaveifyApp extends ConsumerWidget {
  const WaveifyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Waveify',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: settings.themeMode,
      theme: AppTheme.light(settings.accentVariant),
      darkTheme: AppTheme.dark(settings.accentVariant),
      locale: Locale(settings.locale),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: [for (final code in supportedLocales) Locale(code)],
    );
  }
}
