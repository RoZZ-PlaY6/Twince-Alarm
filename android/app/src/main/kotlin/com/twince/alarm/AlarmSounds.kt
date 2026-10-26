package com.twince.alarm

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.util.Log

object AlarmSounds {
    private var preview: MediaPlayer? = null

    fun list(context: Context): List<HashMap<String, String>> {
        val results = ArrayList<HashMap<String, String>>()
        results.add(
            hashMapOf(
                "name" to "Default alarm",
                "uri" to "",
            ),
        )
        val manager = RingtoneManager(context.applicationContext)
        manager.setType(RingtoneManager.TYPE_ALARM)
        val cursor = manager.cursor
        try {
            while (cursor.moveToNext()) {
                val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX) ?: "Alarm tone"
                val uri = manager.getRingtoneUri(cursor.position)?.toString() ?: continue
                results.add(hashMapOf("name" to title, "uri" to uri))
            }
        } finally {
            cursor.close()
        }
        return results
    }

    fun preview(context: Context, soundUri: String) {
        stop()
        val uri = if (soundUri.isBlank()) {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        } else {
            Uri.parse(soundUri)
        } ?: return
        val media = MediaPlayer()
        preview = media
        media.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        try {
            media.setDataSource(context.applicationContext, uri)
            media.setOnPreparedListener { it.start() }
            media.prepareAsync()
        } catch (error: Exception) {
            Log.e(AlarmContract.TAG, "Preview failed", error)
            media.release()
            if (preview === media) preview = null
        }
    }

    fun stop() {
        preview?.let { media ->
            media.setOnPreparedListener(null)
            try {
                if (media.isPlaying) media.stop()
            } catch (_: IllegalStateException) {
            }
            media.release()
        }
        preview = null
    }
}
