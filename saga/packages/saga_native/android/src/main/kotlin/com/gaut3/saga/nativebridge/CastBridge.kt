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
import com.google.android.gms.cast.MediaQueueData
import com.google.android.gms.cast.MediaQueueItem
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.common.images.WebImage
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * The Cast SDK bridge (`com.gaut3.saga/cast`). It used to live on MainActivity,
 * which broke two ways: `onDestroy` removed the session listener, so an
 * activity Android destroyed mid-cast took the session-end writeback with it
 * while the cached engine lived on; and an engine started without an activity
 * (the widget, a headset, the car) had no cast channel at all. Here the
 * listener is registered once per process, with the application context, and
 * events go to every engine attached.
 *
 * Dart's audio handler drives the TV through this: a queue load, transport
 * commands, and a status push (`onMediaStatus`) on every receiver change and
 * once a second while media is loaded.
 */
internal object CastBridge {
    private const val TAG = "SagaCast"
    private const val RECEIVER_ID = CastOptionsProvider.RECEIVER_ID

    // The queue position of each item rides in its media's customData, so a
    // status can name the item without the sender's paged queue cache. The
    // load id says which load the status belongs to: a status from the
    // previous book's queue must never be read as a place in the next one.
    private const val ITEM_INDEX_KEY = "sagaIndex"
    private const val LOAD_ID_KEY = "sagaLoad"
    private const val PROGRESS_INTERVAL_MS = 1000L

    private val channels = mutableListOf<MethodChannel>()
    private var castContext: CastContext? = null
    private var listening = false
    private var discovering = false
    private var watchedClient: RemoteMediaClient? = null

    private val castSelector: MediaRouteSelector = MediaRouteSelector.Builder()
        .addControlCategory(CastMediaControlIntent.categoryForCast(RECEIVER_ID))
        .build()

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) {
            watch(session)
            send("onSessionStateChanged", connectedPayload(session))
        }
        override fun onSessionEnded(session: CastSession, error: Int) {
            unwatch()
            // "ended" marks this as a terminal state, not a failure: the SDK
            // reports a non-zero reason code even for deliberate disconnects,
            // which should be logged but never shown to the user as an error.
            send("onSessionStateChanged", sessionPayload(false, error) + mapOf("ended" to true))
        }
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            watch(session)
            send("onSessionStateChanged", connectedPayload(session))
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

    private val mediaCallback = object : RemoteMediaClient.Callback() {
        override fun onStatusUpdated() = publishStatus()
        override fun onQueueStatusUpdated() = publishStatus()
    }

    private val progressListener =
        RemoteMediaClient.ProgressListener { _, _ -> publishStatus() }

    // Streams the live Cast device list to Dart while the device sheet is open.
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
        // A session the SDK resumed before this engine attached.
        currentSession()?.let { watch(it) }
        // Never removed: the listener lives as long as the process, which is
        // the point (see the class comment).
        listening = true
    }

    fun detach(channel: MethodChannel) {
        channel.setMethodCallHandler(null)
        channels.remove(channel)
    }

    private fun currentSession(): CastSession? =
        castContext?.sessionManager?.currentCastSession

    private fun client(): RemoteMediaClient? = currentSession()?.remoteMediaClient

    private fun watch(session: CastSession) {
        val client = session.remoteMediaClient ?: return
        if (client === watchedClient) return
        unwatch()
        client.registerCallback(mediaCallback)
        client.addProgressListener(progressListener, PROGRESS_INTERVAL_MS)
        watchedClient = client
    }

    private fun unwatch() {
        watchedClient?.let {
            it.unregisterCallback(mediaCallback)
            it.removeProgressListener(progressListener)
        }
        watchedClient = null
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

    private fun publishStatus() {
        statusMap()?.let { send("onMediaStatus", it) }
    }

    // The device's name is for the device sheet and the Device button only.
    // It's someone's room or their own name: Dart never logs it.
    private fun connectedPayload(session: CastSession): Map<String, Any?> =
        mapOf("connected" to true, "deviceName" to session.castDevice?.friendlyName)

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

    private fun statusMap(): Map<String, Any?>? {
        val session = currentSession() ?: return null
        val client = session.remoteMediaClient ?: return null
        val s = client.mediaStatus ?: return null
        return mapOf(
            "state" to when (s.playerState) {
                MediaStatus.PLAYER_STATE_IDLE -> "idle"
                MediaStatus.PLAYER_STATE_PLAYING -> "playing"
                MediaStatus.PLAYER_STATE_PAUSED -> "paused"
                MediaStatus.PLAYER_STATE_BUFFERING -> "buffering"
                MediaStatus.PLAYER_STATE_LOADING -> "loading"
                else -> "unknown"
            },
            "idleReason" to when (s.idleReason) {
                MediaStatus.IDLE_REASON_FINISHED -> "finished"
                MediaStatus.IDLE_REASON_CANCELED -> "cancelled"
                MediaStatus.IDLE_REASON_INTERRUPTED -> "interrupted"
                MediaStatus.IDLE_REASON_ERROR -> "error"
                else -> "none"
            },
            "item" to itemIndex(s),
            "load" to (customData(s)?.optString(LOAD_ID_KEY, "") ?: ""),
            "positionMs" to client.approximateStreamPosition,
            "rate" to s.playbackRate,
            "deviceVolume" to session.volume,
            "deviceName" to session.castDevice?.friendlyName,
        )
    }

    /** The playing item's customData: from its media, else its queue entry. */
    private fun customData(s: MediaStatus): JSONObject? =
        s.mediaInfo?.customData?.takeIf { it.has(ITEM_INDEX_KEY) }
            ?: s.getQueueItemById(s.currentItemId)?.media?.customData

    /** The playing item's queue index, or -1 when the status doesn't say. */
    private fun itemIndex(s: MediaStatus): Int =
        customData(s)?.optInt(ITEM_INDEX_KEY, -1) ?: -1

    /** The receiver's item id for queue index [index], or null if unknown. */
    private fun itemIdAt(client: RemoteMediaClient, index: Int): Int? {
        client.mediaStatus?.queueItems?.firstOrNull {
            it.media?.customData?.optInt(ITEM_INDEX_KEY, -1) == index
        }?.let { return it.itemId }
        val id = client.mediaQueue.itemIdAtIndex(index)
        return if (id == MediaQueueItem.INVALID_ITEM_ID) null else id
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
            "loadQueue" -> loadQueue(call, result)
            "play" -> command(result) { it.play() }
            "pause" -> command(result) { it.pause() }
            "seek" -> {
                val ms = call.argument<Number>("positionMs")?.toLong() ?: 0L
                command(result) {
                    it.seek(MediaSeekOptions.Builder().setPosition(ms).build())
                }
            }
            "jump" -> {
                val index = call.argument<Int>("index") ?: -1
                val ms = call.argument<Number>("positionMs")?.toLong() ?: 0L
                val client = client()
                val id = client?.let { itemIdAt(it, index) }
                if (client == null || id == null) {
                    // Dart reloads the queue at the target instead.
                    result.success(false)
                } else {
                    client.queueJumpToItem(id, ms, null)
                    result.success(true)
                }
            }
            "setRate" -> {
                val rate = call.argument<Double>("rate") ?: 1.0
                command(result) { it.setPlaybackRate(rate) }
            }
            "setStreamVolume" -> {
                val v = call.argument<Double>("volume") ?: 1.0
                command(result) { it.setStreamVolume(v.coerceIn(0.0, 1.0)) }
            }
            "setDeviceVolume" -> {
                val v = call.argument<Double>("volume") ?: 0.5
                try {
                    currentSession()?.volume = v.coerceIn(0.0, 1.0)
                } catch (e: Exception) {
                    Log.w(TAG, "setDeviceVolume failed: $e")
                }
                result.success(null)
            }
            "getStatus" -> result.success(statusMap())
            "stopCasting" -> {
                castContext?.sessionManager?.endCurrentSession(true)
                result.success(null)
            }
            "getSessionState" -> {
                val session = currentSession()
                if (session?.isConnected == true) {
                    watch(session)
                    result.success(connectedPayload(session))
                } else {
                    result.success(mapOf("connected" to false))
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Runs a transport command; false when there's no session to send it to. */
    private fun command(result: MethodChannel.Result, block: (RemoteMediaClient) -> Unit) {
        val client = client()
        if (client == null) {
            result.success(false)
            return
        }
        try {
            block(client)
            result.success(true)
        } catch (e: Exception) {
            Log.w(TAG, "cast command failed: $e")
            result.success(false)
        }
    }

    /**
     * Loads the whole book as one queue, one item per file, so the receiver
     * moves from file to file on its own (one file per cast was the pre-1.2
     * bug). Answers whether the receiver accepted the load.
     */
    private fun loadQueue(call: MethodCall, result: MethodChannel.Result) {
        val client = client()
        if (client == null) {
            result.success(false)
            return
        }
        val raw = call.argument<List<Map<String, Any?>>>("items").orEmpty()
        val title = call.argument<String>("title") ?: ""
        val artist = call.argument<String>("artist") ?: ""
        val artwork = call.argument<String>("artwork") ?: ""
        val startIndex = call.argument<Int>("startIndex") ?: 0
        val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
        val autoplay = call.argument<Boolean>("autoplay") ?: true
        val rate = call.argument<Double>("rate") ?: 1.0
        val loadId = call.argument<String>("loadId") ?: ""

        val items = raw.mapIndexed { i, item ->
            val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK).apply {
                putString(MediaMetadata.KEY_TITLE, title)
                putString(MediaMetadata.KEY_ARTIST, artist)
                (item["trackTitle"] as? String)?.let {
                    putString(MediaMetadata.KEY_ALBUM_TITLE, it)
                }
                if (artwork.isNotEmpty()) addImage(WebImage(Uri.parse(artwork)))
            }
            val info = MediaInfo.Builder(item["url"] as String)
                .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
                .setContentType(item["contentType"] as? String ?: "audio/mpeg")
                .setMetadata(metadata)
                .setCustomData(JSONObject().put(ITEM_INDEX_KEY, i).put(LOAD_ID_KEY, loadId))
                .apply {
                    (item["durationMs"] as? Number)?.toLong()?.takeIf { it > 0 }
                        ?.let { setStreamDuration(it) }
                }
                .build()
            MediaQueueItem.Builder(info)
                .setAutoplay(true)
                .setPreloadTime(20.0)
                .build()
        }
        if (items.isEmpty() || startIndex !in items.indices) {
            result.success(false)
            return
        }
        val queue = MediaQueueData.Builder()
            .setItems(items)
            .setQueueType(MediaQueueData.MEDIA_QUEUE_TYPE_AUDIO_BOOK)
            .setStartIndex(startIndex)
            .build()
        val request = MediaLoadRequestData.Builder()
            .setQueueData(queue)
            .setCurrentTime(positionMs)
            .setAutoplay(autoplay)
            .setPlaybackRate(rate)
            .build()
        try {
            client.load(request).setResultCallback { r ->
                if (!r.status.isSuccess) Log.w(TAG, "queue load failed: ${r.status}")
                result.success(r.status.isSuccess)
            }
        } catch (e: Exception) {
            Log.w(TAG, "queue load threw: $e")
            result.success(false)
        }
    }
}
