package org.neiam.feedpug.app.data

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Persists the (base URL, API token) pair from the pairing flow into
 * EncryptedSharedPreferences. The pair is the only authentication state the
 * app holds.
 */
class TokenStore(context: Context) {
    private val prefs by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "feedpug_secure",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    fun save(baseUrl: String, token: String) {
        prefs.edit()
            .putString(KEY_BASE_URL, baseUrl.trimEnd('/'))
            .putString(KEY_TOKEN, token)
            .apply()
    }

    fun load(): Credentials? {
        val base = prefs.getString(KEY_BASE_URL, null) ?: return null
        val token = prefs.getString(KEY_TOKEN, null) ?: return null
        return Credentials(base, token)
    }

    fun clear() = prefs.edit().clear().apply()

    data class Credentials(val baseUrl: String, val token: String)

    companion object {
        private const val KEY_BASE_URL = "base_url"
        private const val KEY_TOKEN = "token"
    }
}
