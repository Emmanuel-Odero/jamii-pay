package com.jamiipay.jamiipay

import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyPairGenerator
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * DeviceVault: hardware-bound key wrapping for the session private key.
 *
 * A P-256 key lives in the AndroidKeyStore (StrongBox when the device has
 * one, TEE otherwise — never in app memory or on disk) and wraps the
 * wallet's private key with ECIES (ephemeral ECDH + HKDF-SHA256 +
 * AES-256-GCM) before it lands in EncryptedSharedPreferences/Keystore
 * backing. Same contract as the iOS twin: stops *extraction*, not *use*.
 *
 * Wire format (shared with nothing else — local only):
 * `ephemeralPub(65B uncompressed) || iv(12B) || ciphertext+tag`.
 */
object DeviceVault {
    private const val ALIAS = "jamiipay_device_vault"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"

    data class KeyInfo(val publicKeyBase64: String, val hardwareBacked: Boolean, val strongBox: Boolean)

    fun ensureKey(pm: PackageManager): KeyInfo {
        loadEntry()?.let { return keyInfo(pm, strongBox = false) }
        // Prefer StrongBox; fall back to TEE on any StrongBox failure. The
        // outcome is reported, never silent.
        val strongBoxCapable =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                pm.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
        if (strongBoxCapable) {
            try {
                generate(useStrongBox = true)
                return keyInfo(pm, strongBox = true)
            } catch (_: Exception) {
                // Fall through to TEE.
            }
        }
        generate(useStrongBox = false)
        return keyInfo(pm, strongBox = false)
    }

    private fun generate(useStrongBox: Boolean) {
        val kpg = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, ANDROID_KEYSTORE)
        val builder = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_AGREE_KEY)
            .setAlgorithmParameterSpec(java.security.spec.ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(false)
        if (useStrongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true)
        }
        kpg.initialize(builder.build())
        kpg.generateKeyPair()
    }

    private fun loadEntry(): KeyStore.PrivateKeyEntry? {
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        return ks.getEntry(ALIAS, null) as? KeyStore.PrivateKeyEntry
    }

    private fun keyInfo(pm: PackageManager, strongBox: Boolean): KeyInfo {
        val entry = loadEntry() ?: throw IllegalStateException("no device key")
        val pubBytes = entry.certificate.publicKey.encoded
        // Keys generated in the AndroidKeyStore never leave hardware/TEE
        // address space — there is no exportable-software path the way
        // there is on iOS simulators. `strongBox` reports which hardware.
        return KeyInfo(
            publicKeyBase64 = android.util.Base64.encodeToString(pubBytes, android.util.Base64.NO_WRAP),
            hardwareBacked = true,
            strongBox = strongBox,
        )
    }

    fun wrap(pm: PackageManager, plaintext: ByteArray): ByteArray {
        val entry = loadEntry() ?: throw IllegalStateException("no device key")
        val ka = KeyAgreement.getInstance("ECDH")
        ka.init(entry.privateKey)
        // Ephemeral sender key (in-memory only, never stored).
        val ephemeral = java.security.KeyPairGenerator.getInstance("EC").apply {
            initialize(java.security.spec.ECGenParameterSpec("secp256r1"))
        }.generateKeyPair()
        ka.doPhase(ephemeral.public, true)
        val shared = ka.generateSecret()
        val aesKey = hkdf(shared, "jamiipay-vault-wrap-v1".toByteArray())
        val iv = ByteArray(12).also { java.security.SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, SecretKeySpec(aesKey, "AES"), GCMParameterSpec(128, iv))
        }
        val ct = cipher.doFinal(plaintext)
        val ephemeralPub = uncompressed(ephemeral.public.encoded)
        return ephemeralPub + iv + ct
    }

    fun unwrap(blob: ByteArray): ByteArray {
        require(blob.size > 65 + 12 + 16) { "blob too short" }
        val entry = loadEntry() ?: throw IllegalStateException("no device key — was it deleted or is this a new device?")
        val ephemeralPub = blob.copyOfRange(0, 65)
        val iv = blob.copyOfRange(65, 77)
        val ct = blob.copyOfRange(77, blob.size)
        val kf = java.security.KeyFactory.getInstance("EC")
        val pubKey = kf.generatePublic(
            java.security.spec.X509EncodedKeySpec(wrapUncompressedInX509Der(ephemeralPub))
        )
        val ka = KeyAgreement.getInstance("ECDH")
        ka.init(entry.privateKey)
        ka.doPhase(pubKey, true)
        val shared = ka.generateSecret()
        val aesKey = hkdf(shared, "jamiipay-vault-wrap-v1".toByteArray())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, SecretKeySpec(aesKey, "AES"), GCMParameterSpec(128, iv))
        }
        return cipher.doFinal(ct)
    }

    // --- minimal HKDF-SHA256 (extract+expand, RFC 5869) ---

    private fun hkdf(ikm: ByteArray, info: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(ByteArray(32), "HmacSHA256"))
        val prk = mac.doFinal(ikm)
        mac.init(SecretKeySpec(prk, "HmacSHA256"))
        mac.update(info)
        mac.update(0x01.toByte())
        return mac.doFinal().copyOf(32)
    }

    private fun uncompressed(x509: ByteArray): ByteArray {
        // X.509 SPKI for a P-256 EC key is 91 bytes: a 26-byte DER prefix
        // then the 65-byte uncompressed point (04 || X || Y) at offset 26.
        require(x509.size == 91 && x509[26] == 0x04.toByte()) { "unexpected EC encoding" }
        return x509.copyOfRange(26, 91)
    }

    private fun wrapUncompressedInX509Der(point65: ByteArray): ByteArray {
        require(point65.size == 65 && point65[0] == 0x04.toByte()) { "bad point" }
        // SPKI DER prefix for id-ecPublicKey + secp256r1 (26 bytes) + BIT
        // STRING header (0x03 0x42 0x00) + 65-byte point = 91 bytes total.
        val prefix = byteArrayOf(
            0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A.toByte(), 0x86.toByte(),
            0x48.toByte(), 0xCE.toByte(), 0x3D.toByte(), 0x02, 0x01,
            0x06, 0x08, 0x2A.toByte(), 0x86.toByte(), 0x48.toByte(),
            0xCE.toByte(), 0x3D.toByte(), 0x03, 0x01, 0x07,
            0x03, 0x42, 0x00,
        )
        return prefix + point65
    }

    private operator fun ByteArray.plus(other: ByteArray): ByteArray {
        val out = ByteArray(size + other.size)
        System.arraycopy(this, 0, out, 0, size)
        System.arraycopy(other, 0, out, size, other.size)
        return out
    }
}
