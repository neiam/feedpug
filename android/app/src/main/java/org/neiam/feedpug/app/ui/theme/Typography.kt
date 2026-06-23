package org.neiam.feedpug.app.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import org.neiam.feedpug.app.R

/**
 * B612 is the typeface FeedPug's web frontend uses; bundling the same TTFs as
 * the sibling neiam Android apps keeps the products feeling like one family.
 */
val B612: FontFamily = FontFamily(
    Font(R.font.b612_regular, FontWeight.Normal),
    Font(R.font.b612_bold, FontWeight.Bold),
)

val FeedPugTypography: Typography = Typography().run {
    fun TextStyle.b612() = copy(fontFamily = B612)
    Typography(
        displayLarge = displayLarge.b612(),
        displayMedium = displayMedium.b612(),
        displaySmall = displaySmall.b612(),
        headlineLarge = headlineLarge.b612(),
        headlineMedium = headlineMedium.b612(),
        headlineSmall = headlineSmall.b612(),
        titleLarge = titleLarge.b612(),
        titleMedium = titleMedium.b612(),
        titleSmall = titleSmall.b612(),
        bodyLarge = bodyLarge.b612(),
        bodyMedium = bodyMedium.b612(),
        bodySmall = bodySmall.b612(),
        labelLarge = labelLarge.b612(),
        labelMedium = labelMedium.b612(),
        labelSmall = labelSmall.b612(),
    )
}
