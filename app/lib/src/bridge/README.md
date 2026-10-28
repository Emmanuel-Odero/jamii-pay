# flutter_rust_bridge integration

This directory will hold the generated Dart bindings for `wallet-core`.

Once `wallet-core`'s public API (keys/address/signing) is stable enough to
freeze, generate bindings from the repo root:

```sh
cargo install flutter_rust_bridge_codegen
flutter_rust_bridge_codegen generate \
  --rust-input crates/wallet-core/src/lib.rs \
  --dart-output app/lib/src/bridge/generated.dart \
  --rust-root crates/wallet-core
```

Do not hand-edit generated output — change `wallet-core` and regenerate.
