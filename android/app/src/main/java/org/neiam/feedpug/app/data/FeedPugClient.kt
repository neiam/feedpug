package org.neiam.feedpug.app.data

import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query
import java.util.concurrent.TimeUnit

interface FeedPugApi {
    @GET("api/profile")
    suspend fun profile(): ProfileResponse

    @GET("api/timeline")
    suspend fun timeline(
        @Query("before") before: String? = null,
        @Query("unread") unread: String? = null,
        @Query("sources") sources: String? = null,
        @Query("reaction") reaction: String? = null,
        @Query("q") q: String? = null,
        @Query("limit") limit: Int? = null,
    ): TimelineResponse

    @POST("api/timeline/read_all")
    suspend fun readAll(@Query("sources") sources: String? = null): OkResponse

    @GET("api/items/{id}")
    suspend fun item(@Path("id") id: Long): ItemResponse

    @POST("api/items/{id}/read")
    suspend fun markRead(@Path("id") id: Long): OkResponse

    @POST("api/items/{id}/unread")
    suspend fun markUnread(@Path("id") id: Long): OkResponse

    @POST("api/items/{id}/reactions")
    suspend fun react(@Path("id") id: Long, @Body body: ReactBody): ReactResponse

    @GET("api/sources")
    suspend fun sources(): SourcesResponse

    @GET("api/slices")
    suspend fun slices(): SlicesResponse

    @GET("api/reactions")
    suspend fun reactions(): ReactionsResponse
}

object FeedPugClient {
    private val json = Json { ignoreUnknownKeys = true }

    fun build(creds: TokenStore.Credentials): FeedPugApi {
        val ok = OkHttpClient.Builder()
            .addInterceptor { chain ->
                val req = chain.request().newBuilder()
                    .addHeader("Authorization", "Bearer ${creds.token}")
                    .addHeader("Accept", "application/json")
                    .build()
                chain.proceed(req)
            }
            .addInterceptor(HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BASIC
            })
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()

        val baseUrl = if (creds.baseUrl.endsWith("/")) creds.baseUrl else "${creds.baseUrl}/"
        return Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(ok)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(FeedPugApi::class.java)
    }
}
