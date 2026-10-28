package com.jamiipay.jamiipay

import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jamiipay/device_vault")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "generateKey", "getPublicKey" -> {
                            val info = DeviceVault.ensureKey(packageManager)
                            result.success(
                                mapOf(
                                    "publicKeyBase64" to info.publicKeyBase64,
                                    "enclave" to info.hardwareBacked,
                                    "strongBox" to info.strongBox,
                                )
                            )
                        }
                        "wrap" -> {
                            val dataB64 = call.argument<String>("dataBase64")
                                ?: return@setMethodCallHandler result.error("BAD_ARGS", "wrap needs dataBase64", null)
                            val blob = DeviceVault.wrap(
                                packageManager,
                                Base64.decode(dataB64, Base64.DEFAULT),
                            )
                            result.success(
                                mapOf("blobBase64" to Base64.encodeToString(blob, Base64.NO_WRAP))
                            )
                        }
                        "unwrap" -> {
                            val blobB64 = call.argument<String>("blobBase64")
                                ?: return@setMethodCallHandler result.error("BAD_ARGS", "unwrap needs blobBase64", null)
                            val data = DeviceVault.unwrap(
                                Base64.decode(blobB64, Base64.DEFAULT)
                            )
                            result.success(
                                mapOf("dataBase64" to Base64.encodeToString(data, Base64.NO_WRAP))
                            )
                        }
                        "setBadge" -> {
                            // Android 8+ shows a dot for high-importance
                            // notifications on its own; explicit counts are
                            // launcher-dependent, so this is a no-op that
                            // reports success to keep Dart code uniform.
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("VAULT_ERROR", e.message, null)
                }
            }
    }
}
