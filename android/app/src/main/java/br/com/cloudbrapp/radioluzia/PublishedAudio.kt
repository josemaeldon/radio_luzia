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
