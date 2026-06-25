package org.neiam.feedpug.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import org.neiam.feedpug.app.data.PairPayload
import org.neiam.feedpug.app.data.ThemeStore
import org.neiam.feedpug.app.data.TokenStore
import org.neiam.feedpug.app.ui.DetailScreen
import org.neiam.feedpug.app.ui.PairScreen
import org.neiam.feedpug.app.ui.TimelineScreen
import org.neiam.feedpug.app.ui.theme.ALL_THEMES
import org.neiam.feedpug.app.ui.theme.AppTheme
import org.neiam.feedpug.app.ui.theme.FeedPugTheme
import org.neiam.feedpug.app.ui.theme.appThemeByKey

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val tokens = TokenStore(this)
        val themeStore = ThemeStore(this)
        val deepLink = intent?.let(::extractPairPayload)

        setContent {
            var theme by remember {
                mutableStateOf(themeStore.themeKey?.let(::appThemeByKey) ?: ALL_THEMES.first())
            }
            FeedPugTheme(theme = theme) {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    FeedPugApp(
                        tokens = tokens,
                        initialDeepLink = deepLink,
                        currentTheme = theme,
                        onPickTheme = { picked ->
                            theme = picked
                            themeStore.themeKey = picked.key
                        },
                    )
                }
            }
        }
    }

    private fun extractPairPayload(intent: Intent): PairPayload? {
        if (intent.action != Intent.ACTION_VIEW) return null
        return PairPayload.parse(intent.data?.toString())
    }
}

@Composable
fun FeedPugApp(
    tokens: TokenStore,
    initialDeepLink: PairPayload?,
    currentTheme: AppTheme,
    onPickTheme: (AppTheme) -> Unit,
) {
    val nav = rememberNavController()
    val start = remember(initialDeepLink, tokens) {
        when {
            initialDeepLink != null -> "pair?prefilled=true"
            tokens.load() != null -> "timeline"
            else -> "pair"
        }
    }

    NavHost(navController = nav, startDestination = start) {
        composable("pair") {
            PairScreen(prefilled = null, tokens = tokens, onPaired = {
                nav.navigate("timeline") { popUpTo(0) }
            })
        }
        composable("pair?prefilled=true") {
            PairScreen(prefilled = initialDeepLink, tokens = tokens, onPaired = {
                nav.navigate("timeline") { popUpTo(0) }
            })
        }
        composable("timeline") {
            TimelineScreen(
                tokens = tokens,
                currentTheme = currentTheme,
                onPickTheme = onPickTheme,
                onOpenItem = { id -> nav.navigate("detail/$id") },
                onUnpair = {
                    tokens.clear()
                    nav.navigate("pair") { popUpTo(0) }
                },
            )
        }
        composable(
            "detail/{id}",
            arguments = listOf(navArgument("id") { type = NavType.StringType }),
        ) { backStack ->
            val id = backStack.arguments?.getString("id") ?: ""
            DetailScreen(tokens = tokens, itemId = id, onBack = { nav.popBackStack() })
        }
    }
}
