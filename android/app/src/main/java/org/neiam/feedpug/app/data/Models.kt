package org.neiam.feedpug.app.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ProfileResponse(val user: User)

@Serializable
data class User(val id: String, val email: String)

@Serializable
data class Feed(
    val id: String,
    val title: String? = null,
    val url: String? = null,
    @SerialName("site_url") val siteUrl: String? = null,
    val status: String? = null,
)

@Serializable
data class Item(
    val id: String,
    val title: String? = null,
    val url: String? = null,
    val summary: String? = null,
    val content: String? = null,
    val author: String? = null,
    @SerialName("published_at") val publishedAt: String? = null,
    @SerialName("sort_at") val sortAt: String? = null,
    val read: Boolean = false,
    val reactions: List<String> = emptyList(),
    val feed: Feed? = null,
)

@Serializable
data class TimelineResponse(
    val items: List<Item>,
    @SerialName("next_before") val nextBefore: String? = null,
)

@Serializable
data class ItemResponse(val item: Item)

@Serializable
data class Source(
    val key: String,
    val label: String,
    val kind: String,
    @SerialName("feed_count") val feedCount: Int,
)

@Serializable
data class SourcesResponse(val sources: List<Source>)

@Serializable
data class Reaction(
    val id: String,
    val emoji: String,
    val label: String? = null,
    val position: Int = 0,
)

@Serializable
data class ReactionsResponse(val reactions: List<Reaction>)

@Serializable
data class Slice(
    val id: String,
    val name: String,
    @SerialName("source_keys") val sourceKeys: List<String> = emptyList(),
    @SerialName("unread_only") val unreadOnly: Boolean = false,
    @SerialName("reaction_emoji") val reactionEmoji: String? = null,
)

@Serializable
data class SlicesResponse(val slices: List<Slice>)

@Serializable
data class ReactBody(val emoji: String)

@Serializable
data class ReactResponse(val state: String, val reactions: List<String>)

@Serializable
data class OkResponse(val ok: Boolean = true)
