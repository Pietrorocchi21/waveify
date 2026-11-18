import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waveify/core/providers/app_providers.dart';
import 'package:waveify/core/storage/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'language switches with translations loaded and survives restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final settings = container.read(settingsProvider.notifier);
      await settings.init();
      expect(
        container.read(translatorProvider)('settings.language.label'),
        'Language',
      );

      await settings.setLocale('it');
      expect(
        container.read(translatorProvider)('settings.language.label'),
        'Lingua',
      );
      expect((await AppSettings.load()).locale, 'it');

      await settings.setLocale('invalid');
      expect(container.read(localeProvider), 'it');
    },
  );
}
