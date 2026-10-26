package com.twince.alarm

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log

/**
 * Loops the selected alarm tone on the alarm stream and pulses the vibrator
 * until [stop] is called.
 */
class AlarmSoundPlayer(context: Context) {
    private val appContext = context.applicationContext
    private val audioManager = appContext.getSystemService(AudioManager::class.java)
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var focusRequest: AudioFocusRequest? = null
    private var playing = false

    val isPlaying: Boolean
        get() = playing

    fun start(soundUri: String, vibrate: Boolean) {
        stop()
        requestFocus()
        startPlayer(resolveUri(soundUri), allowFallback = true)
        if (vibrate) startVibration()
    }

    fun stop() {
        playing = false
        player?.let { media ->
            media.setOnPreparedListener(null)
            media.setOnErrorListener(null)
            try {
                if (media.isPlaying) media.stop()
            } catch (_: IllegalStateException) {
            }
            media.release()
        }
        player = null
        vibrator?.cancel()
        vibrator = null
        abandonFocus()
    }

    private fun startPlayer(uri: Uri, allowFallback: Boolean) {
        val media = MediaPlayer()
        player = media
        media.setAudioAttributes(alarmAttributes())
        media.setOnErrorListener { _, what, extra ->
            Log.e(AlarmContract.TAG, "Alarm tone error what=$what extra=$extra")
            playing = false
            true
        }
        try {
            media.setDataSource(appContext, uri)
            media.isLooping = true
            media.setOnPreparedListener {
                if (player !== media) return@setOnPreparedListener
                try {
                    it.start()
                    playing = true
                } catch (_: IllegalStateException) {
                }
            }
            media.prepareAsync()
        } catch (error: Exception) {
            Log.e(AlarmContract.TAG, "Unable to play alarm tone $uri", error)
            media.release()
            if (player === media) player = null
            val fallback = defaultUri()
            if (allowFallback && uri != fallback) {
                startPlayer(fallback, allowFallback = false)
            }
        }
    }

    private fun startVibration() {
        val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            appContext.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            appContext.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        vibrator = vib
        val pattern = longArrayOf(0, 520, 240, 520, 240, 860)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vib.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vib.vibrate(pattern, 0)
        }
    }

    private fun resolveUri(soundUri: String): Uri {
        if (soundUri.isBlank()) return defaultUri()
        return try {
            Uri.parse(soundUri)
        } catch (_: Exception) {
            defaultUri()
        }
    }

    private fun defaultUri(): Uri {
        return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: Settings.System.DEFAULT_ALARM_ALERT_URI
    }

    private fun alarmAttributes(): AudioAttributes {
        return AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
    }

    private fun requestFocus() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(alarmAttributes())
            .setAcceptsDelayedFocusGain(false)
            .setWillPauseWhenDucked(false)
            .build()
        focusRequest = request
        audioManager.requestAudioFocus(request)
    }

    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        focusRequest = null
    }
}
