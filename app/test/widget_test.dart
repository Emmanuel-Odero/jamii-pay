import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:jamiipay/main.dart';
import 'package:jamiipay/src/theme/theme_store.dart';

import 'fake_secure_storage.dart';

void main() {
  // Both storage backends are device-keyed (Keychain/Keystore, NSUserDefaults)
  // with no implementation on the test host:
  // - ThemeStore constructs a SharedPreferencesAsync, whose constructor
  //   throws when no async platform is registered.
  // - _Bootstrap.restoreSession() reads secure storage, whose method
  //   channel never responds in tests (future hangs -> stuck on loader).
  // In-memory fakes keep the suite hermetic.
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStoragePlatform.instance = FakeSecureStorage();
  });

  testWidgets('JamiiPayApp renders the onboarding welcome screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(JamiiPayApp(themeStore: ThemeStore()));
    await tester.pumpAndSettle();

    expect(find.text('Pay simple.\nLive easy.'), findsOneWidget);
    expect(find.text('Create my wallet'), findsOneWidget);
  });
}
