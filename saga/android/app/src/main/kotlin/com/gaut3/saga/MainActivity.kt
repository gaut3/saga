package com.gaut3.saga

import android.app.AlertDialog
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.CastStatusCodes
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.common.images.WebImage
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    private val castChannel = "com.gaut3.saga/cast"
    private var channel: MethodChannel? = null
    private var castContext: CastContext? = null
    private var discovering = false

    private val castSelector: MediaRouteSelector = MediaRouteSelector.Builder()
        .addControlCategory(CastMediaControlIntent.categoryForCast("CC1AD845"))
        .build()

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) {
            channel?.invokeMethod("onSessionStateChanged", mapOf("connected" to true))
        }
        override fun onSessionEnded(session: CastSession, error: Int) {
            channel?.invokeMethod("onSessionStateChanged", sessionPayload(false, error))
        }
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            channel?.invokeMethod("onSessionStateChanged", mapOf("connected" to true))
        }
        override fun onSessionSuspended(session: CastSession, reason: Int) {}
        // Failures must reach Dart too — with the SDK's error code, so the UI
        // can say *why* instead of silently returning to the device list.
        override fun onSessionStartFailed(session: CastSession, error: Int) {
            channel?.invokeMethod("onSessionStateChanged", sessionPayload(false, error))
        }
        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            channel?.invokeMethod("onSessionStateChanged", sessionPayload(false, error))
        }
        override fun onSessionStarting(session: CastSession) {}
        override fun onSessionResuming(session: CastSession, sessionId: String) {}
        override fun onSessionEnding(session: CastSession) {}
    }

    // Streams the live Cast device list to Dart while the cast sheet is open.
    private val discoveryCallback = object : MediaRouter.Callback() {
        override fun onRouteAdded(router: MediaRouter, route: MediaRouter.RouteInfo) =
            publishRoutes()
        override fun onRouteRemoved(router: MediaRouter, route: MediaRouter.RouteInfo) =
            publishRoutes()
        override fun onRouteChanged(router: MediaRouter, route: MediaRouter.RouteInfo) =
            publishRoutes()
    }

    private fun publishRoutes() {
        val routes = MediaRouter.getInstance(this).routes
            .filter { !it.isDefault && it.matchesSelector(castSelector) }
            .map { mapOf("id" to it.id, "name" to it.name) }
        channel?.invokeMethod("onRoutesChanged", routes)
    }

    // Session-state payload; carries the Cast SDK error code + name when the
    // transition was caused by a failure (error 0 = normal end, omitted).
    private fun sessionPayload(connected: Boolean, error: Int): Map<String, Any> {
        return if (error == CastStatusCodes.SUCCESS) {
            mapOf("connected" to connected)
        } else {
            mapOf(
                "connected" to connected,
                "errorCode" to error,
                "errorMessage" to CastStatusCodes.getStatusCodeString(error),
            )
        }
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
                    "startDiscovery" -> {
                        if (!discovering) {
                            discovering = true
                            MediaRouter.getInstance(this).addCallback(
                                castSelector,
                                discoveryCallback,
                                MediaRouter.CALLBACK_FLAG_REQUEST_DISCOVERY or
                                        MediaRouter.CALLBACK_FLAG_PERFORM_ACTIVE_SCAN
                            )
                        }
                        publishRoutes()
                        result.success(null)
                    }
                    "stopDiscovery" -> {
                        if (discovering) {
                            discovering = false
                            MediaRouter.getInstance(this).removeCallback(discoveryCallback)
                        }
                        result.success(null)
                    }
                    "selectRoute" -> {
                        val id = call.argument<String>("id")
                        val route = MediaRouter.getInstance(this).routes
                            .firstOrNull { it.id == id }
                        if (route == null) {
                            result.error("NO_ROUTE", "Device is no longer available", null)
                        } else {
                            MediaRouter.getInstance(this).selectRoute(route)
                            result.success(null)
                        }
                    }
                    "loadMedia" -> {
                        val url = call.argument<String>("url")
                        val title = call.argument<String>("title") ?: ""
                        val artist = call.argument<String>("artist") ?: ""
                        val artwork = call.argument<String>("artwork") ?: ""
                        val contentType =
                            call.argument<String>("contentType") ?: "audio/mpeg"
                        val positionMs = call.argument<Int>("positionMs") ?: 0
                        if (url == null) {
                            result.error("NO_URL", "url is required", null)
                        } else {
                            loadMedia(url, title, artist, artwork, contentType,
                                positionMs.toLong())
                            result.success(null)
                        }
                    }
                    "getCastPosition" -> {
                        val pos = castContext?.sessionManager?.currentCastSession
                            ?.remoteMediaClient?.approximateStreamPosition ?: 0L
                        result.success(pos)
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

    private fun loadMedia(
        url: String,
        title: String,
        artist: String,
        artwork: String,
        contentType: String,
        positionMs: Long,
    ) {
        val session = castContext?.sessionManager?.currentCastSession ?: return
        val client = session.remoteMediaClient ?: return

        val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK).apply {
            putString(MediaMetadata.KEY_TITLE, title)
            putString(MediaMetadata.KEY_ARTIST, artist)
            if (artwork.isNotEmpty()) addImage(WebImage(Uri.parse(artwork)))
        }
        val mediaInfo = MediaInfo.Builder(url)
            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setContentType(contentType)
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
