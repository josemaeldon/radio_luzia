package br.com.cloudbrapp.radioluzia

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
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

    override fun onCreate() {
        super.onCreate()
        player = ExoPlayer.Builder(this).build()
        session = MediaSession.Builder(this, player).build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_PLAY) {
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
        return START_STICKY
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession = session

    override fun onDestroy() {
        session.release()
        player.release()
        super.onDestroy()
    }

    companion object {
        const val ACTION_PLAY = "br.com.cloudbrapp.radioluzia.PLAY_PODCAST"
        const val EXTRA_URL = "podcast_url"
        const val EXTRA_TITLE = "podcast_title"
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
    var podcastsLoading by mutableStateOf(false); private set
    private var player: ExoPlayer? = null
    private var userWantsPlayback = false
    init { refresh(); viewModelScope.launch { while (true) { delay(15000); refresh() } } }
    fun refresh() = viewModelScope.launch(Dispatchers.IO) { runCatching { RadioApi.nowPlaying() }.onSuccess { json -> state = parseState(json, state) }.onFailure { if (state.station == null) state = state.copy(error = "Não foi possível atualizar os dados da rádio.") } }
    fun clearError() { state = state.copy(error = null) }
    fun toggle(context: Context) { if (state.isPlaying || state.connecting) pause() else play(context) }
    fun play(context: Context) {
        val mount = state.selectedMount ?: state.station?.mounts?.firstOrNull() ?: return
        if (!state.online) { state = state.copy(error = "A rádio está fora do ar neste momento."); return }
        userWantsPlayback = true; state = state.copy(connecting = true)
        if (player?.isPlaying == true) return
        player?.release()
        player = ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(mount.url))
            addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    when (playbackState) {
                        Player.STATE_BUFFERING -> state = state.copy(connecting = true, isPlaying = false)
                        Player.STATE_READY -> state = state.copy(isPlaying = true, connecting = false)
                        Player.STATE_IDLE -> if (userWantsPlayback) state = state.copy(connecting = true)
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    state = state.copy(isPlaying = false, connecting = false, error = "A transmissão foi interrompida.")
                }
            })
            playWhenReady = true
            prepare()
        }
    }
    fun pause() { userWantsPlayback = false; player?.pause(); state = state.copy(isPlaying = false, connecting = false) }
    fun selectMount(mount: Mount, context: Context) { val wasPlaying = state.isPlaying || state.connecting; pause(); state = state.copy(selectedMount = mount); if (wasPlaying) play(context) }
    fun loadRequests() = viewModelScope.launch(Dispatchers.IO) { requestsLoading = true; runCatching { RadioApi.requests() }.onSuccess { array -> requests = buildList { for (i in 0 until array.length()) array.optJSONObject(i)?.let { item -> val song = item.optJSONObject("song") ?: JSONObject(); add(RequestSong(item.text("request_id"), song.text("title").ifEmpty { song.text("text") }, song.text("artist"), song.text("album"), song.optString("art").takeIf { it.startsWith("http") })) } } }; requestsLoading = false }
    fun request(song: RequestSong, onResult: (String) -> Unit) = viewModelScope.launch(Dispatchers.IO) { runCatching { RadioApi.requestSong(song.requestId) }.onSuccess { onResult(it) }.onFailure { onResult(it.message ?: "Não foi possível enviar o pedido.") } }
    fun loadPodcasts() = viewModelScope.launch(Dispatchers.IO) { podcastsLoading = true; runCatching { RadioApi.podcasts() }.onSuccess { array -> podcasts = buildList { for (i in 0 until array.length()) array.optJSONObject(i)?.let { add(Podcast(it.text("id"), it.text("title"), it.optString("art").takeIf { value -> value.startsWith("http") })) } } }; podcastsLoading = false }
    fun loadEpisodes(podcast: Podcast) = viewModelScope.launch(Dispatchers.IO) { runCatching { RadioApi.episodes(podcast.id) }.onSuccess { array -> episodes = buildList { for (i in 0 until array.length()) array.optJSONObject(i)?.let { add(PodcastEpisode(it.text("id"), it.text("title"), it.optJSONObject("links")?.optString("download")?.takeIf { value -> value.startsWith("http") })) } } } }
    fun playPodcast(context: Context, episode: PodcastEpisode) {
        val url = episode.download ?: return
        userWantsPlayback = false
        player?.release()
        player = null
        context.startService(Intent(context, PodcastPlaybackService::class.java).apply {
            action = PodcastPlaybackService.ACTION_PLAY
            putExtra(PodcastPlaybackService.EXTRA_URL, url)
            putExtra(PodcastPlaybackService.EXTRA_TITLE, episode.title)
        })
    }
    fun share(context: Context) { val url = state.station?.publicUrl ?: state.station?.listenUrl ?: return; context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, "Ouça Rádio Santa Luzia: $url") }, "Compartilhar rádio")) }
    fun openInstagram(context: Context) { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://instagram.com/santaluziapgm"))) }
    fun openWhatsApp(context: Context) { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://chat.whatsapp.com/C6FXTTNeetk4gMEX12uwNL?mode=gi_t"))) }
    override fun onCleared() { player?.release(); super.onCleared() }
}

@Composable private fun RemoteArtwork(url: String?, modifier: Modifier = Modifier) {
    val context = LocalContext.current; var bitmap by remember(url) { mutableStateOf<android.graphics.Bitmap?>(null) }
    LaunchedEffect(url) { bitmap = withContext(Dispatchers.IO) { runCatching { if (url != null) URL(url).openStream().use(BitmapFactory::decodeStream) else null }.getOrNull() } }
    if (bitmap != null) Image(bitmap!!.asImageBitmap(), "Capa da faixa", modifier, contentScale = ContentScale.Crop) else Image(androidx.compose.ui.res.painterResource(br.com.cloudbrapp.radioluzia.R.drawable.default_station_artwork), "Rádio Santa Luzia", modifier, contentScale = ContentScale.Crop)
}

@Composable fun RadioApp(vm: RadioViewModel = androidx.lifecycle.viewmodel.compose.viewModel()) {
    val state = vm.state; val context = LocalContext.current; var dialog by remember { mutableStateOf<String?>(null) }
    Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(Color(0xFF150410), Plum, Color.Black)))) {
        LazyColumn(contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 40.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
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

@Composable private fun Header(state: RadioState, onDetails: () -> Unit, onRequests: () -> Unit, onPodcasts: () -> Unit, onQuality: () -> Unit, onInstagram: () -> Unit, onWhatsApp: () -> Unit) { Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { IconButton(onClick = onDetails) { Icon(Icons.Default.Info, "Detalhes", tint = Color.White) }; Spacer(Modifier.weight(1f)); IconButton(onClick = onInstagram, modifier = Modifier.semantics { contentDescription = "Instagram da rádio" }) { InstagramMark() }; IconButton(onClick = onWhatsApp, modifier = Modifier.semantics { contentDescription = "Grupo da rádio no WhatsApp" }) { WhatsAppMark() }; if (state.station?.requestsEnabled == true) IconButton(onClick = onRequests) { Icon(Icons.Default.QueueMusic, "Pedir música", tint = Color.White) }; IconButton(onClick = onPodcasts) { Icon(Icons.Default.Mic, "Podcasts", tint = Color.White) }; IconButton(onClick = onQuality) { Icon(Icons.Default.Tune, "Qualidade", tint = Color.White) }; }; Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) { Text(state.station?.name?.uppercase() ?: "PARÓQUIA SANTA LUZIA", color = Cream.copy(.84f), fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp); Row(verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(7.dp).clip(CircleShape).background(if (state.online) Color.Green else Color(0xFFFF9800))); Spacer(Modifier.width(7.dp)); Text(if (state.live) "Ao vivo com ${state.streamer.ifEmpty { "programa ao vivo" }}" else if (state.online) "No ar agora" else "Verificando sinal…", color = Color.White.copy(.64f), fontSize = 12.sp) } } }

@Composable private fun InstagramMark() { Box(Modifier.size(24.dp).border(1.8.dp, Color.White, RoundedCornerShape(7.dp)), contentAlignment = Alignment.Center) { Box(Modifier.size(9.dp).border(1.8.dp, Color.White, CircleShape)); Box(Modifier.size(3.dp).clip(CircleShape).background(Color.White).align(Alignment.TopEnd).offset((-4).dp, 5.dp)) } }

@Composable private fun WhatsAppMark() { Box(Modifier.size(24.dp).clip(CircleShape).background(Gold), contentAlignment = Alignment.Center) { Icon(Icons.Default.Chat, null, tint = Plum, modifier = Modifier.size(20.dp)); Icon(Icons.Default.Call, null, tint = Gold, modifier = Modifier.size(10.dp).rotate(-35f)) } }

@Composable private fun Controls(state: RadioState, vm: RadioViewModel, context: Context) { Column(Modifier.card(), horizontalAlignment = Alignment.CenterHorizontally) { LinearProgressIndicator(progress = { if ((state.current?.duration ?: 0.0) > 0) ((state.current?.elapsed ?: 0.0) / state.current!!.duration).toFloat() else 0f }, color = Gold, trackColor = Color.White.copy(.12f), modifier = Modifier.fillMaxWidth()); Spacer(Modifier.height(18.dp)); Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(24.dp)) { IconButton(onClick = { }) { Icon(Icons.Default.VolumeDown, "Volume", tint = Color.White.copy(.58f)) }; FilledIconButton(onClick = { vm.toggle(context) }, modifier = Modifier.size(78.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = Gold)) { if (state.connecting) CircularProgressIndicator(color = Plum) else Icon(if (state.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, "Ouvir rádio", tint = Plum, modifier = Modifier.size(36.dp)) }; IconButton(onClick = { vm.share(context) }) { Icon(Icons.Default.Share, "Compartilhar", tint = Color.White.copy(.8f)) } }; Spacer(Modifier.height(12.dp)); Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Default.GraphicEq, null, tint = Color.White.copy(.62f), modifier = Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text(if (state.connecting) "Conectando ao vivo…" else if (state.isPlaying) "Transmitindo ao vivo" else "Pronta para ouvir", color = Color.White.copy(.62f), fontSize = 12.sp); state.selectedMount?.let { Text(" • ${it.bitrate} kbps", color = Color.White.copy(.62f), fontSize = 12.sp) } } } }

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
                        ListItem(
                            headlineContent = { Text(episode.title) },
                            leadingContent = { IconButton(onClick = { vm.playPodcast(context, episode) }) { Icon(Icons.Default.PlayCircle, "Reproduzir") } }
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

class MainActivity : ComponentActivity() { override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState); setContent { MaterialTheme(colorScheme = darkColorScheme(primary = Gold, background = Color(0xFF150410), surface = Color(0xFF2D1025), onSurface = Color.White)) { RadioApp() } } } }
