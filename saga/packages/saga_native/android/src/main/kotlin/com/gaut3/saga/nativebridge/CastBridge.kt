package com.gaut3.saga.nativebridge

import android.content.Context
import android.net.Uri
import android.util.Log
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
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Cast SDK bridge (`com.gaut3.saga/cast`). It used to live on MainActivity,
 * which broke two ways: `onDestroy` removed the session listener, so an
 * activity Android destroyed mid-cast took the session-end writeback with it
 * while the cached engine lived on; and an engine started without an activity
 * (the widget, a headset, the car) had no cast channel at all. Here the
 * listener is registered once per process, with the application context, and
 * events go to every engine attached.
 */
internal object CastBridge {
    private const val TAG = "SagaCast"
    private const val RECEIVER_ID = CastOptionsProvider.RECEIVER_ID

    private val channels = mutableListOf<MethodChannel>()
    private var castContext: CastContext? = null
    private var listening = false
    private var discovering = false

    private val castSelector: MediaRouteSelector = MediaRouteSelector.Builder()
        .addControlCategory(CastMediaControlIntent.categoryForCast(RECEIVER_ID))
        .build()

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) {
            send("onSessionStateChanged", mapOf("connected" to true))
        }
        override fun onSessionEnded(session: CastSession, error: Int) {
            // "ended" marks this as a terminal state, not a failure: the SDK
            // reports a non-zero reason code even for deliberate disconnects,
            // which should be logged but never shown to the user as an error.
            send("onSessionStateChanged", sessionPayload(false, error) + mapOf("ended" to true))
        }
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            send("onSessionStateChanged", mapOf("connected" to true))
        }
        override fun onSessionSuspended(session: CastSession, reason: Int) {}
        // Failures must reach Dart too — with the SDK's error code, so the UI
        // can say *why* instead of silently returning to the device list.
        override fun onSessionStartFailed(session: CastSession, error: Int) {
            send("onSessionStateChanged", sessionPayload(false, error))
        }
        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            send("onSessionStateChanged", sessionPayload(false, error))
        }
        override fun onSessionStarting(session: CastSession) {}
        override fun onSessionResuming(session: CastSession, sessionId: String) {}
        override fun onSessionEnding(session: CastSession) {}
    }

    // Streams the live Cast device list to Dart while the cast sheet is open.
    private val discoveryCallback = object : MediaRouter.Callback() {
        override fun onRouteAdded(router: MediaRouter, route: MediaRouter.RouteInfo) =
            publishRoutes(router)
        override fun onRouteRemoved(router: MediaRouter, route: MediaRouter.RouteInfo) =
            publishRoutes(router)
        override fun onRouteChanged(router: MediaRouter, route: MediaRouter.RouteInfo) =
            publishRoutes(router)
    }

    /** Called on the main thread from the plugin, for every engine. */
    fun attach(context: Context, channel: MethodChannel) {
        channels.add(channel)
        channel.setMethodCallHandler { call, result -> onMethodCall(context, call, result) }
        if (listening) return
        castContext = try {
            CastContext.getSharedInstance(context)
        } catch (e: Exception) {
            // No Play services (de-Googled phones): casting is simply absent.
            Log.w(TAG, "no CastContext: $e")
            null
        }
        castContext?.sessionManager?.addSessionManagerListener(
            sessionListener, CastSession::class.java
        )
        // Never removed: the listener lives as long as the process, which is
        // the point (see the class comment).
        listening = true
    }

    fun detach(channel: MethodChannel) {
        channel.setMethodCallHandler(null)
        channels.remove(channel)
    }

    private fun send(method: String, args: Any?) {
        for (ch in channels.toList()) ch.invokeMethod(method, args)
    }

    private fun publishRoutes(router: MediaRouter) {
        val routes = router.routes
            .filter { !it.isDefault && it.matchesSelector(castSelector) }
            .map { mapOf("id" to it.id, "name" to it.name) }
        send("onRoutesChanged", routes)
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

    private fun onMethodCall(context: Context, call: MethodCall, result: MethodChannel.Result) {
        val router = MediaRouter.getInstance(context)
        when (call.method) {
            "startDiscovery" -> {
                if (!discovering) {
                    discovering = true
                    router.addCallback(
                        castSelector,
                        discoveryCallback,
                        MediaRouter.CALLBACK_FLAG_REQUEST_DISCOVERY or
                            MediaRouter.CALLBACK_FLAG_PERFORM_ACTIVE_SCAN
                    )
                }
                publishRoutes(router)
                result.success(null)
            }
            "stopDiscovery" -> {
                if (discovering) {
                    discovering = false
                    router.removeCallback(discoveryCallback)
                }
                result.success(null)
            }
            "selectRoute" -> {
                val id = call.argument<String>("id")
                val route = router.routes.firstOrNull { it.id == id }
                if (route == null) {
                    result.error("NO_ROUTE", "Device is no longer available", null)
                } else {
                    router.selectRoute(route)
                    result.success(null)
                }
            }
            "loadMedia" -> {
                val url = call.argument<String>("url")
                val title = call.argument<String>("title") ?: ""
                val artist = call.argument<String>("artist") ?: ""
                val artwork = call.argument<String>("artwork") ?: ""
                val contentType = call.argument<String>("contentType") ?: "audio/mpeg"
                val positionMs = call.argument<Int>("positionMs") ?: 0
                if (url == null) {
                    result.error("NO_URL", "url is required", null)
                } else {
                    loadMedia(url, title, artist, artwork, contentType, positionMs.toLong())
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
                    castContext?.sessionManager?.currentCastSession?.isConnected ?: false
                result.success(connected)
            }
            else -> result.notImplemented()
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
