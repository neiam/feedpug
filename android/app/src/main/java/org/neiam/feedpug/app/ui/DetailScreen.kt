package org.neiam.feedpug.app.ui

import android.content.Intent
import android.net.Uri
import android.webkit.WebView
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.coroutines.launch
import org.neiam.feedpug.app.data.FeedPugClient
import org.neiam.feedpug.app.data.Item
import org.neiam.feedpug.app.data.ReactBody
import org.neiam.feedpug.app.data.Reaction
import org.neiam.feedpug.app.data.TokenStore

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DetailScreen(
    tokens: TokenStore,
    itemId: Long,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val creds = remember { tokens.load() }
    val api = remember(creds) { creds?.let { FeedPugClient.build(it) } }
    val scope = rememberCoroutineScope()

    var item by remember { mutableStateOf<Item?>(null) }
    var palette by remember { mutableStateOf<List<Reaction>>(emptyList()) }
    var reactions by remember { mutableStateOf<Set<String>>(emptySet()) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(itemId) {
        api ?: return@LaunchedEffect
        try {
            val resp = api.item(itemId)
            item = resp.item
            reactions = resp.item.reactions.toSet()
            palette = api.reactions().reactions
            // Opening an entry marks it read, matching the web reader.
            api.runCatching { markRead(itemId) }
        } catch (e: Exception) {
            error = e.message
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(item?.feed?.title ?: "Entry", maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    item?.url?.let { url ->
                        IconButton(onClick = {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        }) { Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = "Open original") }
                    }
                },
            )
        },
    ) { padding ->
        val current = item
        if (current == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                if (error != null) Text("Couldn't load: $error", color = MaterialTheme.colorScheme.error)
                else CircularProgressIndicator()
            }
            return@Scaffold
        }

        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
            Text(
                current.title ?: "(untitled)",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(16.dp),
            )

            if (palette.isNotEmpty()) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    palette.forEach { r ->
                        FilterChip(
                            selected = reactions.contains(r.emoji),
                            onClick = {
                                scope.launch {
                                    val resp = api?.runCatching { react(itemId, ReactBody(r.emoji)) }?.getOrNull()
                                    if (resp != null) reactions = resp.reactions.toSet()
                                }
                            },
                            label = { Text(r.emoji) },
                        )
                    }
                }
            }

            // Render the (server-sanitized) HTML body in a WebView.
            AndroidView(
                factory = { ctx ->
                    WebView(ctx).apply {
                        settings.javaScriptEnabled = false
                        settings.loadWithOverviewMode = true
                    }
                },
                update = { web ->
                    val html = current.content ?: current.summary ?: ""
                    web.loadDataWithBaseURL(
                        current.feed?.siteUrl,
                        wrapHtml(html),
                        "text/html",
                        "utf-8",
                        null,
                    )
                },
                modifier = Modifier.fillMaxWidth().padding(8.dp),
            )
        }
    }
}

private fun wrapHtml(body: String): String =
    """
    <!DOCTYPE html><html><head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      body { font-family: sans-serif; line-height: 1.6; padding: 8px; word-wrap: break-word; }
      img { max-width: 100%; height: auto; }
      pre { white-space: pre-wrap; }
    </style></head><body>$body</body></html>
    """.trimIndent()
