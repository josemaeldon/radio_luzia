package br.com.cloudbrapp.radioluzia

import java.net.URI

data class PublishedAudio(
    val id: String, val title: String, val url: String, val type: String,
    val published: Boolean, val primary: Boolean,
)

/** The API's primary ID or a published episode ID is the only playback authority. */
object PublishedAudioSelection {
    fun select(contents: List<PublishedAudio>, primaryId: String?, episodeId: String? = null): PublishedAudio {
        val id = episodeId ?: primaryId ?: error("Nenhum principal publicado.")
        val content = contents.firstOrNull { it.id == id && it.published }
            ?: error("Conteúdo removido ou não publicado.")
        require(if (episodeId == null) content.primary && content.type in listOf("audio", "stream") else content.type == "audio")
        val uri = URI(content.url)
        require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null)
        return content
    }
}

/** A circular queue resolves episode identity before each transition. */
data class PrimaryPlaybackQueue(val contentId: String, val loop: Boolean, val items: List<PublishedAudio>) {
    init {
        require(items.isNotEmpty())
        items.forEach { item ->
            val uri = URI(item.url)
            require(item.type in listOf("audio", "stream") && uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null)
        }
    }
    fun select(currentId: String?, advancing: Boolean = false): PublishedAudio? {
        val index = items.indexOfFirst { it.id == currentId }
        if (index < 0) return items.first()
        if (!advancing) return items[index]
        return if (loop) items[(index + 1) % items.size] else null
    }
}
