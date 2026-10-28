import 'dart:convert';

import 'package:crypto/crypto.dart';

/// One-way hash for the PIN before it ever touches storage — even
/// `flutter_secure_storage`'s Keychain-backed store shouldn't need to hold
/// the raw PIN. `sha256` (no per-install salt) is proportionate here: the
/// hash never leaves the device, and the six-character keyspace is
/// protected by the platform's own Keychain access controls, not by this
/// hash's resistance to offline brute force.
String hashPin(String pin) => sha256.convert(utf8.encode(pin)).toString();
