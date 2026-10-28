# JamiiPay — Flutter app

Android, iOS, and web dashboard from one codebase. Wallet/key logic lives in
`../crates/wallet-core` and is bound in via `flutter_rust_bridge` (see
`lib/src/bridge/README.md`).

## First-time setup (Flutter isn't installed on this machine yet)

```sh
# install Flutter (macOS): https://docs.flutter.dev/get-started/install/macos
flutter doctor

cd app
flutter create --org com.jamiipay --platforms android,ios,web .
flutter pub get
flutter run -d chrome   # web dashboard
```

`flutter create .` will fill in `android/`, `ios/`, and `web/` platform
folders in place — they're intentionally not checked in yet since they're
generated and machine/SDK-version specific.
