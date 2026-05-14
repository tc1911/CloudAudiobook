package com.cloudaudiobook.cloud_audiobook

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.support.v4.media.MediaMetadataCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var mediaSession: MediaSessionCompat? = null
    private var isPlaying = false
    private val CHANNEL = "com.cloudaudiobook/media"
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "cloud_audiobook_playback"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initMediaSession()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateMetadata" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val coverPath = call.argument<String>("coverPath")
                    updateMetadata(title, artist, coverPath)
                    result.success(null)
                }
                "updatePlaybackState" -> {
                    val playing = call.argument<Boolean>("playing") ?: false
                    val position = (call.argument<Number>("position")?.toLong() ?: 0L)
                    val duration = (call.argument<Number>("duration")?.toLong() ?: 0L)
                    updatePlaybackState(playing, position, duration)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "播放控制",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "云听书播放控制"
            setShowBadge(false)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun initMediaSession() {
        val callback = object : MediaSessionCompat.Callback() {
            override fun onPlay() {
                val pos = mediaSession?.controller?.playbackState?.position ?: 0L
                updatePlaybackState(true, pos, 0)
                MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onPlay", null)
            }
            override fun onPause() {
                val pos = mediaSession?.controller?.playbackState?.position ?: 0L
                updatePlaybackState(false, pos, 0)
                MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onPause", null)
            }
            override fun onSkipToNext() {
                MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onNext", null)
            }
            override fun onSkipToPrevious() {
                MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onPrev", null)
            }
        }

        mediaSession = MediaSessionCompat(this, "CloudAudiobook").apply {
            setCallback(callback)
            setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                     MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)
            isActive = true
        }

        updatePlaybackState(false, 0, 0)
        updateNotification()
    }

    private fun updateMetadata(title: String, artist: String, coverPath: String?) {
        val builder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
        if (coverPath != null) {
            try {
                val cover = BitmapFactory.decodeFile(coverPath)
                if (cover != null) builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, cover)
            } catch (_: Exception) {}
        }
        mediaSession?.setMetadata(builder.build())
        updateNotification()
    }

    private var currentDuration: Long = 0

    private fun updatePlaybackState(playing: Boolean, position: Long, duration: Long) {
        isPlaying = playing
        if (duration > 0) currentDuration = duration
        val state = if (playing) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED
        val builder = PlaybackStateCompat.Builder()
            .setState(state, position, 1.0f)
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_STOP
            )
        if (currentDuration > 0) {
            builder.setBufferedPosition(currentDuration)
        }
        mediaSession?.setPlaybackState(builder.build())
        // Also save duration in metadata
        mediaSession?.controller?.metadata?.let {
            val newMeta = MediaMetadataCompat.Builder(it)
            if (currentDuration > 0) newMeta.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, currentDuration)
            mediaSession?.setMetadata(newMeta.build())
        }
        updateNotification()
    }

    private fun updateNotification() {
        val session = mediaSession ?: return
        val metadata = session.controller.metadata
        val playbackState = session.controller.playbackState
        val title = metadata?.getString(MediaMetadataCompat.METADATA_KEY_TITLE) ?: "云听书"
        val artist = metadata?.getString(MediaMetadataCompat.METADATA_KEY_ARTIST) ?: ""
        val isPlaying = playbackState?.state == PlaybackStateCompat.STATE_PLAYING

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        // Try to load cover art
        val coverArt = metadata?.getBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART)

        // Format time for notification
        val pos = playbackState?.position ?: 0
        val dur = (metadata?.getLong(MediaMetadataCompat.METADATA_KEY_DURATION) ?: 0)
        val timeText = if (dur > 0) {
            "${formatTime(pos)} / ${formatTime(dur)}"
        } else ""

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(if (isPlaying) "正在播放 · $artist" else "已暂停 · $artist")
            .setSubText(timeText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setLargeIcon(coverArt)
            .setContentIntent(pendingIntent)
            .setStyle(androidx.media.app.NotificationCompat.MediaStyle()
                .setMediaSession(session.sessionToken)
                .setShowActionsInCompactView(0, 1, 2))
            .addAction(android.R.drawable.ic_media_previous, "上一集", null)
            .addAction(
                if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (isPlaying) "暂停" else "播放",
                null
            )
            .addAction(android.R.drawable.ic_media_next, "下一集", null)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(isPlaying)
            .build()

        NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, notification)
    }

    private fun formatTime(ms: Long): String {
        val totalSec = ms / 1000
        val min = totalSec / 60
        val sec = totalSec % 60
        return "${min}:${sec.toString().padStart(2, '0')}"
    }

    override fun onDestroy() {
        NotificationManagerCompat.from(this).cancel(NOTIFICATION_ID)
        mediaSession?.release()
        super.onDestroy()
    }
}
