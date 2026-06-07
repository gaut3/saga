package com.gaut3.saga

import android.app.AlertDialog
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    private val castChannel = "com.gaut3.saga/cast"
    private var channel: MethodChannel? = null
    private var castContext: CastContext? = null

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) {
            channel?.invokeMethod("onSessionStateChanged", mapOf("connected" to true))
        }
        override fun onSessionEnded(session: CastSession, error: Int) {
            channel?.invokeMethod("onSessionStateChanged", mapOf("connected" to false))
        }
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            channel?.invokeMethod("onSessionStateChanged", mapOf("connected" to true))
        }
        override fun onSessionSuspended(session: CastSession, reason: Int) {}
        override fun onSessionStartFailed(session: CastSession, error: Int) {}
        override fun onSessionResumeFailed(session: CastSession, error: Int) {}
        override fun onSessionStarting(session: CastSession) {}
        override fun onSessionResuming(session: CastSession, sessionId: String) {}
        override fun onSessionEnding(session: CastSession) {}
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        castContext = try {
            CastContext.getSharedInstance(this)
        } catch (e: Exception) {
            null
        }
        castContext?.sessionManager?.addSessionManagerListener(
            sessionListener, CastSession::class.java
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            AlertDialog.Builder(this)
                .setTitle("Playback controls")
                .setMessage(
                    "Saga shows a notification with playback controls so you can pause, " +
                    "skip, and see what's playing from your lock screen and notification shade. " +
                    "Without it, the notification may not appear reliably."
                )
                .setPositiveButton("Allow") { _, _ ->
                    requestPermissions(
                        arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 0
                    )
                }
                .setNegativeButton("Not now", null)
                .show()
        }
    }

    override fun onDestroy() {
        castContext?.sessionManager?.removeSessionManagerListener(
            sessionListener, CastSession::class.java
        )
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, castChannel
        ).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "openDevicePicker" -> {
                        openDevicePicker()
                        result.success(null)
                    }
                    "loadMedia" -> {
                        val url = call.argument<String>("url")
                        val title = call.argument<String>("title") ?: ""
                        val artist = call.argument<String>("artist") ?: ""
                        val positionMs = call.argument<Int>("positionMs") ?: 0
                        if (url == null) {
                            result.error("NO_URL", "url is required", null)
                        } else {
                            loadMedia(url, title, artist, positionMs.toLong())
                            result.success(null)
                        }
                    }
                    "stopCasting" -> {
                        castContext?.sessionManager?.endCurrentSession(true)
                        result.success(null)
                    }
                    "getSessionState" -> {
                        val connected =
                            castContext?.sessionManager?.currentCastSession?.isConnected
                                ?: false
                        result.success(connected)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun openDevicePicker() {
        val mediaRouter = MediaRouter.getInstance(this)
        val selector = MediaRouteSelector.Builder()
            .addControlCategory(CastMediaControlIntent.categoryForCast("CC1AD845"))
            .build()

        // Trigger active discovery so devices show up
        mediaRouter.addCallback(
            selector,
            object : MediaRouter.Callback() {},
            MediaRouter.CALLBACK_FLAG_REQUEST_DISCOVERY or
                    MediaRouter.CALLBACK_FLAG_PERFORM_ACTIVE_SCAN
        )

        val routes = mediaRouter.routes.filter {
            !it.isDefault && it.matchesSelector(selector)
        }

        runOnUiThread {
            if (routes.isEmpty()) {
                AlertDialog.Builder(this)
                    .setTitle("Cast")
                    .setMessage("No Cast devices found. Make sure the device is on the same network, then try again.")
                    .setPositiveButton("OK", null)
                    .show()
            } else {
                val names = routes.map { it.name }.toTypedArray()
                AlertDialog.Builder(this)
                    .setTitle("Cast to device")
                    .setItems(names) { _, i -> mediaRouter.selectRoute(routes[i]) }
                    .setNegativeButton("Cancel", null)
                    .show()
            }
        }
    }

    private fun loadMedia(url: String, title: String, artist: String, positionMs: Long) {
        val session = castContext?.sessionManager?.currentCastSession ?: return
        val client = session.remoteMediaClient ?: return

        val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK).apply {
            putString(MediaMetadata.KEY_TITLE, title)
            putString(MediaMetadata.KEY_ARTIST, artist)
        }
        val mediaInfo = MediaInfo.Builder(url)
            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setContentType("audio/mpeg")
            .setMetadata(metadata)
            .build()
        val request = MediaLoadRequestData.Builder()
            .setMediaInfo(mediaInfo)
            .setCurrentTime(positionMs)
            .setAutoplay(true)
            .build()
        client.load(request)
    }
}
