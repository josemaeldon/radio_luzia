package br.com.cloudbrapp.radioluzia

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.media.AudioManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.MediaItem
import androidx.media3.common.AudioAttributes
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.io.File
import java.io.FileOutputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlin.math.min

private val Plum = Color(0xFF3B102F)
private val Wine = Color(0xFF7B194E)
private val Gold = Color(0xFFE9BA62)
private val Cream = Color(0xFFFFF5DD)

data class Track(val id: String, val title: String, val artist: String, val album: String, val art: String?, val elapsed: Double, val duration: Double)
data class Mount(val id: Int, val name: String, val url: String, val bitrate: Int, val format: String, val isDefault: Boolean)
data class Station(val name: String, val description: String, val timezone: String, val listenUrl: String, val publicUrl: String?, val requestsEnabled: Boolean, val mounts: List<Mount>)
data class RadioState(val station: Station? = null, val current: Track? = null, val next: Track? = null, val history: List<Track> = emptyList(), val listeners: Int = 0, val online: Boolean = false, val live: Boolean = false, val streamer: String = "", val isPlaying: Boolean = false, val connecting: Boolean = false, val selectedMount: Mount? = null, val error: String? = null)
data class RequestSong(val requestId: String, val title: String, val artist: String, val album: String, val art: String?)
data class Podcast(val id: String, val title: String, val art: String?)
data class PodcastEpisode(val id: String, val title: String, val download: String?)

class PodcastPlaybackService : MediaSessionService() {
    private lateinit var player: ExoPlayer
    private lateinit var session: MediaSession
    private lateinit var notificationManager: NotificationManager
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var artworkBitmap: android.graphics.Bitmap? = null

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(NotificationChannel(NOTIFICATION_CHANNEL_ID, "Reprodução da rádio", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Controles da Rádio Santa Luzia"
            setShowBadge(false)
        })
        player = ExoPlayer.Builder(this)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(androidx.media3.common.C.AUDIO_CONTENT_TYPE_MUSIC)
                    .setUsage(androidx.media3.common.C.USAGE_MEDIA)
                    .build(),
                true
            )
            .build()
        session = MediaSession.Builder(this, player).build()
        player.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) = updateNotification()
            override fun onMediaMetadataChanged(mediaMetadata: MediaMetadata) = updateNotification()
        })
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureForegroundNotification()
        when (intent?.action) {
            ACTION_PLAY_RADIO -> {
                val url = intent.getStringExtra(EXTRA_URL)
                if (!url.isNullOrEmpty()) {
                    val metadata = MediaMetadata.Builder()
                        .setTitle(intent.getStringExtra(EXTRA_TITLE) ?: "Rádio Santa Luzia")
                        .setArtist(intent.getStringExtra(EXTRA_ARTIST) ?: "Rádio Santa Luzia")
                        .setAlbumTitle(intent.getStringExtra(EXTRA_ALBUM))
                        .setArtworkUri(intent.getStringExtra(EXTRA_ARTWORK)?.let(Uri::parse))
                        .build()
                    loadArtwork(intent.getStringExtra(EXTRA_ARTWORK))
                    player.setMediaItem(MediaItem.Builder().setUri(url).setMediaMetadata(metadata).build())
                    player.prepare()
                    player.play()
                }
            }
            ACTION_PAUSE_RADIO -> player.pause()
            ACTION_TOGGLE_RADIO -> if (player.isPlaying) player.pause() else player.play()
            ACTION_PLAY -> {
                val url = intent.getStringExtra(EXTRA_URL)
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "Podcast"
                if (!url.isNullOrEmpty()) {
                    val metadata = androidx.media3.common.MediaMetadata.Builder()
                        .setTitle(title)
                        .setArtist("Rádio Santa Luzia • Podcasts")
                        .build()
                    player.setMediaItem(MediaItem.Builder().setUri(url).setMediaMetadata(metadata).build())
                    player.prepare()
                    player.play()
                }
            }
            ACTION_TOGGLE -> if (player.isPlaying) player.pause() else player.play()
        }
        return START_STICKY
    }

    private fun ensureForegroundNotification() {
        startForeground(NOTIFICATION_ID, buildNotification())
    }

    private fun updateNotification() {
        if (::notificationManager.isInitialized) notificationManager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): android.app.Notification {
        val metadata = player.mediaMetadata
        val title = metadata.title?.toString()?.ifBlank { "Rádio Santa Luzia" } ?: "Rádio Santa Luzia"
        val artist = metadata.artist?.toString()?.ifBlank { "Ao vivo" } ?: "Ao vivo"
        val toggleIntent = PendingIntent.getService(this, 1002, Intent(this, PodcastPlaybackService::class.java).apply { action = ACTION_TOGGLE_RADIO }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val contentIntent = PendingIntent.getActivity(this, 1003, Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val toggleIcon = if (player.isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.app_icon)
            .setContentTitle(title)
            .setContentText(artist)
            .setSubText("Rádio Santa Luzia")
            .setLargeIcon(artworkBitmap ?: BitmapFactory.decodeResource(resources, R.drawable.default_station_artwork))
            .setContentIntent(contentIntent)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setShowWhen(false)
            .addAction(NotificationCompat.Action(toggleIcon, if (player.isPlaying) "Pausar" else "Reproduzir", toggleIntent))
            .setStyle(MediaStyle().setMediaSession(session.sessionCompatToken).setShowActionsInCompactView(0))
            .build()
    }

    private fun loadArtwork(url: String?) {
        serviceScope.launch(Dispatchers.IO) {
            val loaded = runCatching { url?.takeIf { it.startsWith("http") }?.let { URL(it).openStream().use(BitmapFactory::decodeStream) } }.getOrNull()
            withContext(Dispatchers.Main) {
                artworkBitmap?.recycle()
                artworkBitmap = loaded
                updateNotification()
            }
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        player.pause()
        player.clearMediaItems()
        stopForeground(true)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession = session

    override fun onDestroy() {
        serviceScope.cancel()
        artworkBitmap?.recycle()
        session.release()
        player.release()
        super.onDestroy()
    }

    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "radio_playback"
        private const val NOTIFICATION_ID = 1001
        const val ACTION_PLAY_RADIO = "br.com.cloudbrapp.radioluzia.PLAY_RADIO"
        const val ACTION_PAUSE_RADIO = "br.com.cloudbrapp.radioluzia.PAUSE_RADIO"
        const val ACTION_TOGGLE_RADIO = "br.com.cloudbrapp.radioluzia.TOGGLE_RADIO"
        const val ACTION_PLAY = "br.com.cloudbrapp.radioluzia.PLAY_PODCAST"
        const val ACTION_TOGGLE = "br.com.cloudbrapp.radioluzia.TOGGLE_PODCAST"
        const val EXTRA_URL = "podcast_url"
        const val EXTRA_TITLE = "podcast_title"
        const val EXTRA_ARTIST = "media_artist"
        const val EXTRA_ALBUM = "media_album"
        const val EXTRA_ARTWORK = "media_artwork"
    }
}

private object RadioApi {
    private const val base = "https://webradio.cloudbr.app"
    private fun get(path: String): JSONObject = (URL(base + path).openConnection() as HttpURLConnection).run {
        connectTimeout = 15000; readTimeout = 15000; requestMethod = "GET"
        if (responseCode !in 200..299) error("Resposta inválida")
        inputStream.bufferedReader().use { JSONObject(it.readText()) }
    }
    fun nowPlaying(): JSONObject = get("/api/nowplaying/santaluziapgm")
    fun requests(): JSONArray = (URL("$base/api/station/2/requests").openConnection() as HttpURLConnection).run {
        connectTimeout = 15000; readTimeout = 15000
        inputStream.bufferedReader().use { JSONArray(it.readText()) }
    }
    fun requestSong(id: String): String = (URL("$base/api/station/2/request/$id").openConnection() as HttpURLConnection).run {
        requestMethod = "POST"; setRequestProperty("Accept", "application/json"); doOutput = true
        if (responseCode !in 200..299) error("Não foi possível enviar o pedido agora.")
        inputStream.bufferedReader().use { JSONObject(it.readText()).optString("message", "Pedido enviado para a programação.") }
    }
    fun podcasts(): JSONArray = getArray("/api/station/2/public/podcasts")
    fun episodes(id: String): JSONArray = getArray("/api/station/2/public/podcast/$id/episodes")
    private fun getArray(path: String): JSONArray = (URL(base + path).openConnection() as HttpURLConnection).run {
        connectTimeout = 15000; readTimeout = 15000; requestMethod = "GET"
        if (responseCode !in 200..299) error("Resposta inválida")
        inputStream.bufferedReader().use { JSONArray(it.readText()) }
    }
}

private fun JSONObject.text(key: String): String = optString(key, "")
private fun JSONObject.track(): Track {
    val song = optJSONObject("song") ?: JSONObject()
    return Track(song.text("id"), song.text("title").ifEmpty { song.text("text") }.ifEmpty { "Rádio Santa Luzia" }, song.text("artist").ifEmpty { "Paróquia Santa Luzia" }, song.text("album"), song.optString("art").takeIf { it.startsWith("http") }, optDouble("elapsed", 0.0), optDouble("duration", 0.0))
}
private fun parseMounts(array: JSONArray): List<Mount> = buildList {
    for (i in 0 until array.length()) array.optJSONObject(i)?.let { add(Mount(it.optInt("id"), it.text("name"), it.text("url"), it.optInt("bitrate"), it.text("format"), it.optBoolean("is_default"))) }
}
private fun parseState(json: JSONObject, previous: RadioState): RadioState {
    val stationJson = json.optJSONObject("station") ?: return previous
    val mounts = parseMounts(stationJson.optJSONArray("mounts") ?: JSONArray())
    val station = Station(stationJson.text("name"), stationJson.text("description"), stationJson.text("timezone"), stationJson.text("listen_url"), stationJson.optString("public_player_url").takeIf { it.startsWith("http") }, stationJson.optBoolean("requests_enabled"), mounts)
    val live = json.optJSONObject("live") ?: JSONObject()
    val current = json.optJSONObject("now_playing")?.track()
    val history = buildList { for (i in 0 until (json.optJSONArray("song_history")?.length() ?: 0)) add(json.getJSONArray("song_history").getJSONObject(i).track()) }
    val selected = previous.selectedMount?.let { mounts.firstOrNull { mount -> mount.id == it.id } } ?: mounts.firstOrNull { it.isDefault } ?: mounts.maxByOrNull { it.bitrate }
    return previous.copy(station = station, current = current, next = json.optJSONObject("playing_next")?.track(), history = history, listeners = json.optJSONObject("listeners")?.optInt("current") ?: 0, online = json.optBoolean("is_online"), live = live.optBoolean("is_live"), streamer = live.text("streamer_name"), selectedMount = selected)
}

class RadioViewModel : ViewModel() {
    var state by mutableStateOf(RadioState()); private set
    var requests by mutableStateOf<List<RequestSong>>(emptyList()); private set
    var requestsLoading by mutableStateOf(false); private set
    var podcasts by mutableStateOf<List<Podcast>>(emptyList()); private set
    var episodes by mutableStateOf<List<PodcastEpisode>>(emptyList()); private set
    var podcastPlayingId by mutableStateOf<String?>(null); private set
    var podcastPlaying by mutableStateOf(false); private set
    var podcastsLoading by mutableStateOf(false); private set
    private var userWantsPlayback = false
    init { refresh(); viewModelScope.launch { while (true) { delay(15000); refresh() } } }
    fun refresh() = viewModelScope.launch(Dispatchers.IO) { runCatching { RadioApi.nowPlaying() }.onSuccess { json -> state = parseState(json, state) }.onFailure { if (state.station == null) state = state.copy(error = "Não foi possível atualizar os dados da rádio.") } }
    fun clearError() { state = state.copy(error = null) }
    fun toggle(context: Context) { if (state.isPlaying || state.connecting) pause(context) else play(context) }
    fun play(context: Context) {
        val mount = state.selectedMount ?: state.station?.mounts?.firstOrNull() ?: return
        if (!state.online) { state = state.copy(error = "A rádio está fora do ar neste momento."); return }
        userWantsPlayback = true
        state = state.copy(isPlaying = true, connecting = false)
        ContextCompat.startForegroundService(context, Intent(context, PodcastPlaybackService::class.java).apply {
            action = PodcastPlaybackService.ACTION_PLAY_RADIO
            putExtra(PodcastPlaybackService.EXTRA_URL, mount.url)
            putExtra(PodcastPlaybackService.EXTRA_TITLE, state.current?.title ?: "Rádio Santa Luzia")
            putExtra(PodcastPlaybackService.EXTRA_ARTIST, state.current?.artist ?: "Rádio Santa Luzia")
            putExtra(PodcastPlaybackService.EXTRA_ALBUM, state.current?.album)
            putExtra(PodcastPlaybackService.EXTRA_ARTWORK, state.current?.art)
        })
    }
    fun pause(context: Context) { userWantsPlayback = false; context.startService(Intent(context, PodcastPlaybackService::class.java).apply { action = PodcastPlaybackService.ACTION_PAUSE_RADIO }); state = state.copy(isPlaying = false, connecting = false) }
    fun selectMount(mount: Mount, context: Context) { val wasPlaying = state.isPlaying || state.connecting; pause(context); state = state.copy(selectedMount = mount); if (wasPlaying) play(context) }
    fun loadRequests() = viewModelScope.launch(Dispatchers.IO) { requestsLoading = true; runCatching { RadioApi.requests() }.onSuccess { array -> requests = buildList { for (i in 0 until array.length()) array.optJSONObject(i)?.let { item -> val song = item.optJSONObject("song") ?: JSONObject(); add(RequestSong(item.text("request_id"), song.text("title").ifEmpty { song.text("text") }, song.text("artist"), song.text("album"), song.optString("art").takeIf { it.startsWith("http") })) } } }; requestsLoading = false }
    fun request(song: RequestSong, onResult: (String) -> Unit) = viewModelScope.launch(Dispatchers.IO) { runCatching { RadioApi.requestSong(song.requestId) }.onSuccess { onResult(it) }.onFailure { onResult(it.message ?: "Não foi possível enviar o pedido.") } }
    fun loadPodcasts() = viewModelScope.launch(Dispatchers.IO) { podcastsLoading = true; runCatching { RadioApi.podcasts() }.onSuccess { array -> podcasts = buildList { for (i in 0 until array.length()) array.optJSONObject(i)?.let { add(Podcast(it.text("id"), it.text("title"), it.optString("art").takeIf { value -> value.startsWith("http") })) } } }; podcastsLoading = false }
    fun loadEpisodes(podcast: Podcast) = viewModelScope.launch(Dispatchers.IO) { runCatching { RadioApi.episodes(podcast.id) }.onSuccess { array -> episodes = buildList { for (i in 0 until array.length()) array.optJSONObject(i)?.let { add(PodcastEpisode(it.text("id"), it.text("title"), it.optJSONObject("links")?.optString("download")?.takeIf { value -> value.startsWith("http") })) } } } }
    fun togglePodcast(context: Context, episode: PodcastEpisode) {
        val url = episode.download ?: return
        if (podcastPlayingId == episode.id) {
            context.startService(Intent(context, PodcastPlaybackService::class.java).apply { action = PodcastPlaybackService.ACTION_TOGGLE })
            podcastPlaying = !podcastPlaying
            return
        }
        userWantsPlayback = false
        context.startService(Intent(context, PodcastPlaybackService::class.java).apply { action = PodcastPlaybackService.ACTION_PAUSE_RADIO })
        state = state.copy(isPlaying = false, connecting = false)
        podcastPlayingId = episode.id
        podcastPlaying = true
        ContextCompat.startForegroundService(context, Intent(context, PodcastPlaybackService::class.java).apply {
            action = PodcastPlaybackService.ACTION_PLAY
            putExtra(PodcastPlaybackService.EXTRA_URL, url)
            putExtra(PodcastPlaybackService.EXTRA_TITLE, episode.title)
        })
    }
    fun share(context: Context) {
        viewModelScope.launch(Dispatchers.IO) {
            val track = state.current
            val artwork = runCatching {
                track?.art?.let { URL(it).openStream().use(BitmapFactory::decodeStream) }
            }.getOrNull()
            val shareBitmap = createShareArtwork(context, track, artwork)
            val shareDir = File(context.cacheDir, "share").apply { mkdirs() }
            val shareFile = File(shareDir, "radio-santa-luzia-${System.currentTimeMillis()}.png")
            FileOutputStream(shareFile).use { shareBitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            shareBitmap.recycle()
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", shareFile)
            withContext(Dispatchers.Main) {
                context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                    type = "image/png"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_TEXT, "Baixe o app Rádio Santa Luzia: $APP_STORE_URL")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }, "Compartilhar arte"))
            }
        }
    }
    fun openInstagram(context: Context) { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://instagram.com/santaluziapgm"))) }
    fun openWhatsApp(context: Context) { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://chat.whatsapp.com/C6FXTTNeetk4gMEX12uwNL?mode=gi_t"))) }
    override fun onCleared() { super.onCleared() }
}

private const val APP_STORE_URL = "https://play.google.com/store/apps/details?id=org.santaluzia.radio"

private fun createShareArtwork(context: Context, track: Track?, artwork: android.graphics.Bitmap?): android.graphics.Bitmap {
    val width = 1080
    val height = 1920
    val bitmap = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val background = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        shader = android.graphics.LinearGradient(0f, 0f, width.toFloat(), height.toFloat(), android.graphics.Color.rgb(21, 4, 16), android.graphics.Color.rgb(123, 25, 78), android.graphics.Shader.TileMode.CLAMP)
    }
    canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), background)

    val image = artwork ?: BitmapFactory.decodeResource(context.resources, R.drawable.default_station_artwork)
    val imageRect = RectF(64f, 64f, 1016f, 1016f)
    canvas.save()
    canvas.clipPath(android.graphics.Path().apply { addRoundRect(imageRect, 32f, 32f, android.graphics.Path.Direction.CW) })
    val scale = maxOf(imageRect.width() / image.width, imageRect.height() / image.height)
    val imageWidth = image.width * scale
    val imageHeight = image.height * scale
    canvas.drawBitmap(image, null, RectF(imageRect.centerX() - imageWidth / 2f, imageRect.centerY() - imageHeight / 2f, imageRect.centerX() + imageWidth / 2f, imageRect.centerY() + imageHeight / 2f), Paint(Paint.ANTI_ALIAS_FLAG))
    canvas.restore()

    val gold = android.graphics.Color.rgb(233, 186, 98)
    val white = android.graphics.Color.WHITE
    val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = gold; textSize = 24f; typeface = Typeface.DEFAULT_BOLD; letterSpacing = .12f }
    canvas.drawText("RÁDIO SANTA LUZIA", 64f, 1100f, labelPaint)
    val title = track?.title?.ifBlank { "Rádio Santa Luzia" } ?: "Rádio Santa Luzia"
    val artist = track?.artist?.ifBlank { "A luz que toca você" } ?: "A luz que toca você"
    val album = track?.album?.takeIf { it.isNotBlank() }
    drawWrappedText(canvas, title, 64f, 1160f, 952f, 44f, white, Typeface.DEFAULT_BOLD, 2)
    drawWrappedText(canvas, artist, 64f, 1280f, 952f, 30f, android.graphics.Color.argb(210, 255, 255, 255), Typeface.DEFAULT, 1)
    album?.let { drawWrappedText(canvas, it, 64f, 1332f, 952f, 22f, android.graphics.Color.argb(175, 255, 255, 255), Typeface.DEFAULT, 1) }
    val linkPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = gold; textSize = 18f; typeface = Typeface.DEFAULT }
    canvas.drawText(APP_STORE_URL, 64f, 1810f, linkPaint)
    return bitmap
}

private fun drawWrappedText(canvas: Canvas, text: String, x: Float, baseline: Float, maxWidth: Float, textSize: Float, color: Int, typeface: Typeface, maxLines: Int) {
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; this.textSize = textSize; this.typeface = typeface }
    val words = text.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
    var line = ""
    var lineNumber = 0
    words.forEach { word ->
        val candidate = if (line.isEmpty()) word else "$line $word"
        if (paint.measureText(candidate) > maxWidth && line.isNotEmpty()) {
            canvas.drawText(line, x, baseline + lineNumber * (textSize + 8f), paint)
            lineNumber++
            line = word
        } else line = candidate
    }
    if (line.isNotEmpty() && lineNumber < maxLines) canvas.drawText(line, x, baseline + lineNumber * (textSize + 8f), paint)
}

@Composable private fun RemoteArtwork(url: String?, modifier: Modifier = Modifier) {
    val context = LocalContext.current; var bitmap by remember(url) { mutableStateOf<android.graphics.Bitmap?>(null) }
    LaunchedEffect(url) { bitmap = withContext(Dispatchers.IO) { runCatching { if (url != null) URL(url).openStream().use(BitmapFactory::decodeStream) else null }.getOrNull() } }
    if (bitmap != null) Image(bitmap!!.asImageBitmap(), "Capa da faixa", modifier, contentScale = ContentScale.Crop) else Image(androidx.compose.ui.res.painterResource(br.com.cloudbrapp.radioluzia.R.drawable.default_station_artwork), "Rádio Santa Luzia", modifier, contentScale = ContentScale.Crop)
}

@Composable fun RadioApp(vm: RadioViewModel = androidx.lifecycle.viewmodel.compose.viewModel()) {
    val state = vm.state; val context = LocalContext.current; var dialog by remember { mutableStateOf<String?>(null) }
    Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(Color(0xFF150410), Plum, Color.Black)))) {
        LazyColumn(
            Modifier.statusBarsPadding(),
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 10.dp, bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            item { Header(state, onDetails = { dialog = "details" }, onRequests = { dialog = "requests" }, onPodcasts = { dialog = "podcasts" }, onQuality = { dialog = "quality" }, onInstagram = { vm.openInstagram(context) }, onWhatsApp = { vm.openWhatsApp(context) }) }
            item { Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) { RemoteArtwork(state.current?.art, Modifier.size(340.dp).clip(RoundedCornerShape(28.dp))); Spacer(Modifier.height(22.dp)); Text(state.current?.title ?: "Rádio Santa Luzia", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center); Text(state.current?.artist ?: "A luz que toca você", color = Color.White.copy(.68f), fontSize = 16.sp, textAlign = TextAlign.Center); if (!state.current?.album.isNullOrEmpty()) Text(state.current!!.album, color = Gold.copy(.8f), fontSize = 12.sp) } }
            item { Controls(state, vm, context) }
            state.next?.let { next -> item { TrackCard("A SEGUIR", next, Icons.Default.SkipNext) } }
            if (state.history.isNotEmpty()) item { Column(Modifier.card()) { Text("TOCOU RECENTEMENTE", color = Color.White.copy(.7f), fontWeight = FontWeight.Bold, letterSpacing = 1.sp); state.history.take(5).forEach { TrackLine(it) } } }
        }
    }
    state.error?.let { message -> AlertDialog(onDismissRequest = vm::clearError, confirmButton = { TextButton(onClick = vm::clearError) { Text("OK") } }, title = { Text("Rádio Santa Luzia") }, text = { Text(message) }) }
    when (dialog) { "details" -> DetailsDialog(state) { dialog = null }; "quality" -> QualityDialog(state, vm, context) { dialog = null }; "requests" -> RequestsDialog(vm) { dialog = null }; "podcasts" -> PodcastsDialog(vm, context) { dialog = null } }
}

@Composable
private fun Header(state: RadioState, onDetails: () -> Unit, onRequests: () -> Unit, onPodcasts: () -> Unit, onQuality: () -> Unit, onInstagram: () -> Unit, onWhatsApp: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        HeaderAction("Detalhes da rádio", onDetails) { Icon(Icons.Default.Info, null, tint = Color.White) }
        Spacer(Modifier.weight(1f))
        HeaderAction("Instagram da rádio", onInstagram) { InstagramMark() }
        HeaderAction("Grupo da rádio no WhatsApp", onWhatsApp) { WhatsAppMark() }
        if (state.station?.requestsEnabled == true) HeaderAction("Pedir música", onRequests) { Icon(Icons.Default.QueueMusic, null, tint = Color.White) }
        HeaderAction("Podcasts", onPodcasts) { Icon(Icons.Default.Mic, null, tint = Color.White) }
        HeaderAction("Qualidade da transmissão", onQuality) { Icon(Icons.Default.Tune, null, tint = Color.White) }
    }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(state.station?.name?.uppercase() ?: "PARÓQUIA SANTA LUZIA", color = Cream.copy(.84f), fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(7.dp).clip(CircleShape).background(if (state.online) Color.Green else Color(0xFFFF9800)))
            Spacer(Modifier.width(7.dp))
            Text(if (state.live) "Ao vivo com ${state.streamer.ifEmpty { "programa ao vivo" }}" else if (state.online) "No ar agora" else "Verificando sinal…", color = Color.White.copy(.64f), fontSize = 12.sp)
        }
    }
}

@Composable
private fun HeaderAction(label: String, onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(
        Modifier
            .size(48.dp)
            .clickable(onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center
    ) { content() }
}

@Composable private fun InstagramMark() { Box(Modifier.size(24.dp).border(1.8.dp, Color.White, RoundedCornerShape(7.dp)), contentAlignment = Alignment.Center) { Box(Modifier.size(9.dp).border(1.8.dp, Color.White, CircleShape)); Box(Modifier.size(3.dp).clip(CircleShape).background(Color.White).align(Alignment.TopEnd).offset((-4).dp, 5.dp)) } }

@Composable private fun WhatsAppMark() { Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) { Box(Modifier.size(24.dp).border(1.8.dp, Color.White, RoundedCornerShape(7.dp))); Icon(Icons.Default.Call, null, tint = Color.White, modifier = Modifier.size(10.dp).rotate(-35f)) } }

@Composable
private fun Controls(state: RadioState, vm: RadioViewModel, context: Context) {
    val track = state.current
    var elapsed by remember(track?.id, track?.elapsed) { mutableDoubleStateOf(track?.elapsed ?: 0.0) }
    val audioManager = remember(context) { context.getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    val maxVolume = remember { audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC) }
    var volume by remember { mutableFloatStateOf(audioManager.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() / maxVolume) }

    DisposableEffect(audioManager) {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                volume = (audioManager.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() / maxVolume).coerceIn(0f, 1f)
            }
        }
        context.contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, observer)
        onDispose { context.contentResolver.unregisterContentObserver(observer) }
    }

    LaunchedEffect(track?.id, track?.elapsed, state.isPlaying) {
        elapsed = track?.elapsed ?: 0.0
        while (true) {
            delay(1000)
            if (state.isPlaying && track != null) {
                elapsed = (elapsed + 1.0).coerceAtMost(track.duration)
            }
        }
    }

    val duration = track?.duration ?: 0.0
    val remaining = (duration - elapsed).coerceAtLeast(0.0)
    Column(Modifier.card(), horizontalAlignment = Alignment.CenterHorizontally) {
        LinearProgressIndicator(
            progress = { if (duration > 0) (elapsed / duration).toFloat().coerceIn(0f, 1f) else 0f },
            color = Gold,
            trackColor = Color.White.copy(.12f),
            modifier = Modifier.fillMaxWidth()
        )
        Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(formatDuration(elapsed), color = Color.White.copy(.56f), fontSize = 12.sp)
            Text("-${formatDuration(remaining)}", color = Color.White.copy(.56f), fontSize = 12.sp)
        }
        Spacer(Modifier.height(18.dp))
        Box(Modifier.fillMaxWidth().height(78.dp)) {
            FilledIconButton(
                onClick = { vm.toggle(context) },
                modifier = Modifier.size(78.dp).align(Alignment.Center),
                colors = IconButtonDefaults.filledIconButtonColors(containerColor = Gold)
            ) {
                if (state.connecting) CircularProgressIndicator(color = Plum)
                else Icon(if (state.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, "Ouvir rádio", tint = Plum, modifier = Modifier.size(36.dp))
            }
            IconButton(onClick = { vm.share(context) }, modifier = Modifier.align(Alignment.CenterEnd)) {
                Icon(Icons.Default.Share, "Compartilhar", tint = Color.White.copy(.8f))
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.VolumeDown, "Diminuir volume", tint = Color.White.copy(.62f), modifier = Modifier.size(18.dp))
            Slider(
                value = volume,
                onValueChange = {
                    volume = it
                    audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, (it * maxVolume).toInt(), 0)
                },
                modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                colors = SliderDefaults.colors(thumbColor = Gold, activeTrackColor = Gold, inactiveTrackColor = Color.White.copy(.16f))
            )
            Icon(Icons.Default.VolumeUp, "Aumentar volume", tint = Color.White.copy(.62f), modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.GraphicEq, null, tint = Color.White.copy(.62f), modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text(if (state.connecting) "Conectando ao vivo…" else if (state.isPlaying) "Transmitindo ao vivo" else "Pronta para ouvir", color = Color.White.copy(.62f), fontSize = 12.sp)
            state.selectedMount?.let { Text(" • ${it.bitrate} kbps", color = Color.White.copy(.62f), fontSize = 12.sp) }
        }
    }
}

private fun formatDuration(seconds: Double): String {
    val total = seconds.toInt().coerceAtLeast(0)
    return "${total / 60}:${(total % 60).toString().padStart(2, '0')}"
}

@Composable private fun TrackCard(label: String, track: Track, icon: androidx.compose.ui.graphics.vector.ImageVector) { Column(Modifier.card()) { Row(verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = Gold, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(8.dp)); Text(label, color = Gold, fontWeight = FontWeight.Bold, letterSpacing = 1.sp, fontSize = 12.sp) }; TrackLine(track) } }
@Composable private fun TrackLine(track: Track) { Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { RemoteArtwork(track.art, Modifier.size(48.dp).clip(RoundedCornerShape(10.dp))); Spacer(Modifier.width(12.dp)); Column { Text(track.title, color = Color.White, maxLines = 1); Text(track.artist, color = Color.White.copy(.62f), fontSize = 12.sp, maxLines = 1) } } }
private fun Modifier.card() = this.fillMaxWidth().background(Color.White.copy(.08f), RoundedCornerShape(24.dp)).padding(20.dp)

@Composable private fun QualityDialog(state: RadioState, vm: RadioViewModel, context: Context, close: () -> Unit) { AlertDialog(onDismissRequest = close, title = { Text("Qualidade do áudio") }, text = { Column { state.station?.mounts?.forEach { mount -> Row(Modifier.fillMaxWidth().clickable { vm.selectMount(mount, context); close() }.padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(mount.name); Text("${mount.format.uppercase()} • ${mount.bitrate} kbps", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }; if (state.selectedMount?.id == mount.id) Icon(Icons.Default.CheckCircle, null, tint = Gold) } } } }, confirmButton = { TextButton(onClick = close) { Text("Fechar") } }) }
@Composable private fun DetailsDialog(state: RadioState, close: () -> Unit) { AlertDialog(onDismissRequest = close, title = { Text("Sobre a transmissão") }, text = { Column { state.station?.let { Text("${it.name}\n${it.description}\nFuso: ${it.timezone}\nOuvintes agora: ${state.listeners}\nStatus: ${if (state.online) "No ar" else "Fora do ar"}", lineHeight = 22.sp) }; Spacer(Modifier.height(12.dp)); Text("Metadados instantâneos via WebSocket\nÁudio Icecast em segundo plano\nControles de reprodução no Android", lineHeight = 22.sp) } }, confirmButton = { TextButton(onClick = close) { Text("OK") } }) }

@Composable
private fun RequestsDialog(vm: RadioViewModel, close: () -> Unit) {
    var search by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    var visible by remember { mutableStateOf(30) }
    LaunchedEffect(Unit) { vm.loadRequests() }
    val filtered = vm.requests.filter {
        search.isBlank() || listOf(it.title, it.artist, it.album).any { text -> text.contains(search, true) }
    }
    AlertDialog(
        onDismissRequest = close,
        title = { Text("Peça sua música") },
        text = {
            LazyColumn(Modifier.heightIn(max = 520.dp)) {
                item {
                    OutlinedTextField(search, { search = it }, label = { Text("Música, artista ou álbum") }, singleLine = true)
                    Spacer(Modifier.height(8.dp))
                }
                if (vm.requestsLoading) {
                    item { CircularProgressIndicator() }
                } else {
                    items(filtered.take(visible)) { song ->
                        Row(
                            Modifier.fillMaxWidth().clickable { vm.request(song) { message = it } }.padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RemoteArtwork(song.art, Modifier.size(44.dp).clip(RoundedCornerShape(8.dp)))
                            Spacer(Modifier.width(10.dp))
                            Column(Modifier.weight(1f)) {
                                Text(song.title, maxLines = 1)
                                Text(song.artist, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                            }
                            Icon(Icons.Default.AddCircle, null, tint = Gold)
                        }
                        if (song == filtered.getOrNull(visible - 5)) visible += 30
                    }
                }
                message?.let { item { Text(it, color = Gold, modifier = Modifier.padding(top = 8.dp)) } }
            }
        },
        confirmButton = { TextButton(onClick = close) { Text("Fechar") } }
    )
}

@Composable
private fun PodcastsDialog(vm: RadioViewModel, context: Context, close: () -> Unit) {
    var selected by remember { mutableStateOf<Podcast?>(null) }
    LaunchedEffect(Unit) { vm.loadPodcasts() }
    AlertDialog(
        onDismissRequest = close,
        title = { Text(selected?.title ?: "Podcasts") },
        text = {
            LazyColumn(Modifier.heightIn(max = 520.dp)) {
                if (selected == null) {
                    if (vm.podcastsLoading) item { CircularProgressIndicator() }
                    items(vm.podcasts) { podcast ->
                        Row(
                            Modifier.fillMaxWidth().clickable { selected = podcast; vm.loadEpisodes(podcast) }.padding(vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RemoteArtwork(podcast.art, Modifier.size(48.dp).clip(RoundedCornerShape(8.dp)))
                            Spacer(Modifier.width(10.dp))
                            Text(podcast.title, Modifier.weight(1f))
                            Icon(Icons.Default.ChevronRight, null)
                        }
                    }
                } else {
                        items(vm.episodes) { episode ->
                        val isPlaying = vm.podcastPlayingId == episode.id && vm.podcastPlaying
                        ListItem(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { vm.togglePodcast(context, episode) },
                            headlineContent = { Text(episode.title) },
                            leadingContent = { Icon(if (isPlaying) Icons.Default.PauseCircle else Icons.Default.PlayCircle, if (isPlaying) "Pausar" else "Reproduzir") }
                        )
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = close) { Text("Fechar") } },
        dismissButton = {
            if (selected != null) {
                TextButton(onClick = { selected = null }) { Text("Podcasts") }
            }
        }
    )
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme(colorScheme = darkColorScheme(primary = Gold, background = Color(0xFF150410), surface = Color(0xFF2D1025), onSurface = Color.White)) { RadioApp() } }
        if (android.os.Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    override fun onDestroy() {
        if (isFinishing) stopService(Intent(this, PodcastPlaybackService::class.java))
        super.onDestroy()
    }
}
