package org.neiam.feedpug.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.MarkEmailUnread
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.neiam.feedpug.app.data.FeedPugClient
import org.neiam.feedpug.app.data.Item
import org.neiam.feedpug.app.data.Slice
import org.neiam.feedpug.app.data.TokenStore
import org.neiam.feedpug.app.ui.theme.ALL_THEMES
import org.neiam.feedpug.app.ui.theme.AppTheme
import org.neiam.feedpug.app.ui.theme.LocalAppTheme

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimelineScreen(
    tokens: TokenStore,
    currentTheme: AppTheme,
    onPickTheme: (AppTheme) -> Unit,
    onOpenItem: (Long) -> Unit,
    onUnpair: () -> Unit,
) {
    val creds = remember { tokens.load() }
    val api = remember(creds) { creds?.let { FeedPugClient.build(it) } }
    val scope = rememberCoroutineScope()

    var items by remember { mutableStateOf<List<Item>>(emptyList()) }
    var nextBefore by remember { mutableStateOf<String?>(null) }
    var unreadOnly by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var sourcesCsv by remember { mutableStateOf<String?>(null) }
    var reactionEmoji by remember { mutableStateOf<String?>(null) }
    var activeSliceId by remember { mutableStateOf<Long?>(null) }
    var slices by remember { mutableStateOf<List<Slice>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun load(reset: Boolean) {
        api ?: return
        loading = true
        error = null
        try {
            val before = if (reset) null else nextBefore
            val resp = api.timeline(
                before = before,
                unread = if (unreadOnly) "true" else null,
                sources = sourcesCsv,
                reaction = reactionEmoji,
                q = query.ifBlank { null },
            )
            items = if (reset) resp.items else items + resp.items
            nextBefore = resp.nextBefore
        } catch (e: Exception) {
            error = e.message
        } finally {
            loading = false
        }
    }

    fun setUnread(item: Item) {
        scope.launch {
            api?.runCatching { markUnread(item.id) }
            items = items.map { if (it.id == item.id) it.copy(read = false) else it }
        }
    }

    fun applySlice(slice: Slice) {
        sourcesCsv = slice.sourceKeys.joinToString(",").ifBlank { null }
        unreadOnly = slice.unreadOnly
        reactionEmoji = slice.reactionEmoji
        activeSliceId = slice.id
    }

    fun clearFilters() {
        sourcesCsv = null
        unreadOnly = false
        reactionEmoji = null
        activeSliceId = null
    }

    LaunchedEffect(Unit) {
        api?.runCatching { slices() }?.getOrNull()?.let { slices = it.slices }
    }

    // Filter changes reload immediately; a non-empty search query is debounced.
    LaunchedEffect(query, unreadOnly, sourcesCsv, reactionEmoji) {
        if (query.isNotBlank()) kotlinx.coroutines.delay(300)
        load(reset = true)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "FEEDPUG",
                        color = LocalAppTheme.current.accent,
                        fontWeight = FontWeight.Bold,
                    )
                },
                actions = {
                    FilterChip(
                        selected = unreadOnly,
                        onClick = {
                            unreadOnly = !unreadOnly
                            activeSliceId = null
                        },
                        label = { Text("Unread") },
                    )
                    IconButton(onClick = {
                        scope.launch {
                            api?.runCatching { readAll(sourcesCsv) }
                            load(reset = true)
                        }
                    }) { Icon(Icons.Default.DoneAll, contentDescription = "Mark all read") }
                    IconButton(onClick = { scope.launch { load(reset = true) } }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                    ThemeMenu(currentTheme = currentTheme, onPickTheme = onPickTheme)
                    IconButton(onClick = onUnpair) {
                        Icon(Icons.AutoMirrored.Filled.Logout, contentDescription = "Unpair")
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text("Search entries…") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
            )

            if (slices.isNotEmpty()) {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    item {
                        FilterChip(
                            selected = activeSliceId == null,
                            onClick = { clearFilters() },
                            label = { Text("All") },
                        )
                    }
                    items(slices, key = { it.id }) { slice ->
                        FilterChip(
                            selected = activeSliceId == slice.id,
                            onClick = { applySlice(slice) },
                            label = { Text(slice.name) },
                        )
                    }
                }
            }

            Box(Modifier.fillMaxSize()) {
                if (error != null && items.isEmpty()) {
                    Text(
                        "Couldn't load: $error",
                        modifier = Modifier.align(Alignment.Center).padding(24.dp),
                        color = MaterialTheme.colorScheme.error,
                    )
                } else {
                    LazyColumn(Modifier.fillMaxSize()) {
                        items(items, key = { it.id }) { item ->
                            SwipeableTimelineRow(
                                item = item,
                                onOpen = { onOpenItem(item.id) },
                                onMarkUnread = { setUnread(item) },
                            )
                            HorizontalDivider()
                        }
                        if (nextBefore != null) {
                            item {
                                TextButton(
                                    onClick = { scope.launch { load(reset = false) } },
                                    modifier = Modifier.fillMaxWidth().padding(8.dp),
                                ) { Text(if (loading) "Loading…" else "Load more") }
                            }
                        }
                    }
                }

                if (loading && items.isEmpty()) {
                    CircularProgressIndicator(Modifier.align(Alignment.Center))
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeableTimelineRow(item: Item, onOpen: () -> Unit, onMarkUnread: () -> Unit) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            // Swipe-left triggers the action but the row never leaves the list.
            if (value == SwipeToDismissBoxValue.EndToStart) onMarkUnread()
            false
        },
    )

    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = false,
        enableDismissFromEndToStart = true,
        backgroundContent = {
            Row(
                Modifier
                    .fillMaxSize()
                    .background(MaterialTheme.colorScheme.primaryContainer)
                    .padding(horizontal = 20.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.End,
            ) {
                Icon(Icons.Default.MarkEmailUnread, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Mark unread", style = MaterialTheme.typography.labelLarge)
            }
        },
        content = {
            Surface(color = MaterialTheme.colorScheme.background) {
                TimelineRow(item, onOpen)
            }
        },
    )
}

@Composable
private fun TimelineRow(item: Item, onClick: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                item.title ?: "(untitled)",
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = if (item.read) FontWeight.Normal else FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            if (item.reactions.isNotEmpty()) {
                Text(item.reactions.joinToString(""), style = MaterialTheme.typography.bodyMedium)
            }
        }
        Spacer(Modifier.height(2.dp))
        Text(
            listOfNotNull(item.feed?.title ?: item.feed?.url, item.publishedAt?.take(10))
                .joinToString(" · "),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun ThemeMenu(currentTheme: AppTheme, onPickTheme: (AppTheme) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) {
            Icon(Icons.Default.Palette, contentDescription = "Theme")
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            ALL_THEMES.forEach { theme ->
                DropdownMenuItem(
                    text = { Text(theme.name) },
                    leadingIcon = {
                        if (theme.key == currentTheme.key) {
                            Icon(Icons.Default.DoneAll, contentDescription = null)
                        }
                    },
                    onClick = {
                        onPickTheme(theme)
                        open = false
                    },
                )
            }
        }
    }
}
