package org.neiam.feedpug.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider

/**
 * Applies a FeedPug palette + B612 typography. `theme` is also provided via
 * `LocalAppTheme` so screens can read bespoke colours that don't map cleanly
 * onto Material's slot system.
 */
@Composable
fun FeedPugTheme(theme: AppTheme, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalAppTheme provides theme) {
        MaterialTheme(
            colorScheme = theme.toColorScheme(),
            typography = FeedPugTypography,
            content = content,
        )
    }
}
