import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/bridge/frb_generated.dart';
import 'src/notifications/device_badge.dart';
import 'src/notifications/local_notifications.dart';
import 'src/router/app_router.dart';
import 'src/state/wallet_store.dart';
import 'src/theme/app_theme.dart';
import 'src/theme/theme_store.dart';

// Entry point for the JamiiPay Flutter app (Android, iOS, and the web
// dashboard build target). All wallet/key logic is delegated to the Rust
// wallet-core crate via flutter_rust_bridge — see lib/src/bridge/.
//
// Screens under lib/src/{onboarding,wallet,recovery,search}/ are built to
// match designs/jammii-pay-mockup.html screen-for-screen; see that file for
// the design rationale behind each one.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await LocalNotifications.init();
  // A badge left over from a previous session is stale by definition —
  // the user opening the app *is* the acknowledgement.
  await DeviceBadge.clear();

  final themeStore = ThemeStore();
  await themeStore.load(); // applies the persisted palette before first frame

  runApp(JamiiPayApp(themeStore: themeStore));
}

class JamiiPayApp extends StatelessWidget {
  const JamiiPayApp({super.key, required this.themeStore});

  final ThemeStore themeStore;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WalletStore()),
        ChangeNotifierProvider.value(value: themeStore),
      ],
      // `Consumer` (not just wrapping MaterialApp once) is what makes theme
      // switches actually visible: AppColors' fields are mutated by
      // ThemeStore.setPreset, and every screen reads them as plain static
      // fields, not via an InheritedWidget — so the only way for a change
      // to show up is a real rebuild of the widget tree below here, which a
      // Consumer listening to ThemeStore's notifyListeners() forces.
      //
      // Deliberately NOT keying MaterialApp.router on `store.preset`: doing
      // so recreates the Router/Navigator from scratch, which wipes the
      // entire navigation stack (and any in-progress screen state — typed
      // amounts, half-filled forms) back to the initial route every time
      // appearance changes. Leaving the widget's identity stable lets the
      // Consumer's rebuild propagate straight down through the existing
      // Navigator — every route already on the stack re-reads the mutated
      // AppColors values and repaints in place — without touching what's
      // pushed or where the user currently is.
      child: Consumer<ThemeStore>(
        builder: (context, store, _) {
          return MaterialApp.router(
            title: 'JamiiPay',
            theme: buildAppTheme(),
            routerConfig: appRouter,
          );
        },
      ),
    );
  }
}
