package org.neiam.feedpug.app.data

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Persists the user's theme preference (a key into `ALL_THEMES`). Kept in a
 * separate prefs file from credentials so unpairing doesn't reset the theme.
 */
class ThemeStore(context: Context) {
    private val prefs by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "feedpug_prefs",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    var themeKey: String?
        get() = prefs.getString(KEY_THEME, null)
        set(value) {
            prefs.edit().also { e ->
                if (value == null) e.remove(KEY_THEME) else e.putString(KEY_THEME, value)
            }.apply()
        }

    companion object {
        private const val KEY_THEME = "theme_key"
    }
}
