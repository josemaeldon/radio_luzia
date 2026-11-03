package br.com.cloudbrapp.radioluzia

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class PublishedAudioSelectionTest {
    private val original = PublishedAudio("1", "Original", "https://audio.example.com/one.mp3", "audio", true, true)

    @Test fun primaryChangesSelectTheNewPublishedURL() {
        assertEquals(original.url, PublishedAudioSelection.select(listOf(original), "1").url)
        val changed = original.copy(url = "https://audio.example.com/two.mp3")
        assertEquals(changed.url, PublishedAudioSelection.select(listOf(changed), "1").url)
        val second = changed.copy(id = "2")
        assertEquals("2", PublishedAudioSelection.select(listOf(original.copy(primary = false), second), "2").id)
    }

    @Test fun missingPrimaryNeverFallsBackToAnOldAudio() {
        assertThrows(IllegalStateException::class.java) { PublishedAudioSelection.select(listOf(original), null) }
        assertThrows(IllegalStateException::class.java) { PublishedAudioSelection.select(listOf(original), "99") }
    }

    @Test fun unpublishedOrRemovedEpisodesCannotPlay() {
        assertThrows(IllegalStateException::class.java) { PublishedAudioSelection.select(listOf(original.copy(published = false)), "1", "1") }
        assertThrows(IllegalStateException::class.java) { PublishedAudioSelection.select(emptyList(), "1", "1") }
        assertEquals(original.url, PublishedAudioSelection.select(listOf(original.copy(primary = false)), null, "1").url)
        val feedEpisode = original.copy(id = "9-episode-hash", primary = false)
        assertEquals(feedEpisode.url, PublishedAudioSelection.select(listOf(feedEpisode), null, feedEpisode.id).url)
    }

    @Test fun publicPagesFeedsAndInsecureURLsCannotBecomeAudio() {
        for (type in listOf("public_page", "podcast_feed")) {
            assertThrows(IllegalArgumentException::class.java) { PublishedAudioSelection.select(listOf(original.copy(type = type)), "1") }
        }
        assertThrows(IllegalArgumentException::class.java) { PublishedAudioSelection.select(listOf(original.copy(url = "http://audio.example.com/a.mp3")), "1") }
    }
}
