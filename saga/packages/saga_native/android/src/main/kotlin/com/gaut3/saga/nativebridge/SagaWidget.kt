package com.gaut3.saga.nativebridge

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import androidx.core.os.BundleCompat
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.min

/** The home-screen widget. Everything it draws comes from [SagaWidget]. */
class SagaWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        // Placed, after an app update, after a reboot (no periodic updates).
        for (id in ids) SagaWidget.noteSize(context, manager, id, "update")
        SagaWidget.render(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context, manager: AppWidgetManager, id: Int, options: Bundle,
    ) {
        SagaWidget.noteSize(context, manager, id, "resize")
        // Below Android 12 the layout is picked by size, so a resize redraws.
        SagaWidget.render(context)
    }
}

/**
 * Draws the widget from the snapshot Dart writes (`SagaWidgetBridge.update`).
 *
 * The snapshot is display-only: strings already formatted by the app, a
 * progress value and a local cover path. Nothing here reads it back to play or
 * restore anything; positions live in Hive, and the buttons only name a book
 * for the app to resume. "Playing" is never stored: it lives in [playing], in
 * memory, so a process that dies takes it along and the next one draws paused.
 */
internal object SagaWidget {
    private const val TAG = "SagaWidget"
    private const val PREFS = "saga_widget"

    // audio_service's custom-action start (SAGA PATCH in AudioService).
    private const val AUDIO_SERVICE = "com.ryanheise.audioservice.AudioService"
    private const val ACTION_CUSTOM = "com.ryanheise.audioservice.action.CUSTOM"
    private const val EXTRA_NAME = "com.ryanheise.audioservice.extra.CUSTOM_ACTION_NAME"
    private const val EXTRA_EXTRAS = "com.ryanheise.audioservice.extra.CUSTOM_ACTION_EXTRAS"

    // Distinct request codes: PendingIntents that differ only in extras are
    // the same PendingIntent, and FLAG_UPDATE_CURRENT would overwrite one
    // button's book with another's.
    private const val RC_OPEN = 1
    private const val RC_PLAY = 2
    private const val RC_PAUSE = 3
    private const val RC_BACK = 4
    private const val RC_FORWARD = 5

    private const val LARGE_MIN_WIDTH_DP = 250
    private const val LARGE_COVER_DP = 200

    // One row: anything shorter than this takes a strip, not the small card.
    // A row is ~100dp on a large phone, but Kvaesitso sometimes draws the
    // widget over its frame's padding too, ~116dp, and at 110 that flipped the
    // row to the small card, cut off. The small card needs more than that
    // anyway. The cover is as tall as the row.
    private const val STRIP_MAX_HEIGHT_DP = 130
    private const val STRIP_COVER_DP = 130

    // A row this tall takes the two-tier strip: title at full width, the
    // buttons beneath (10dp + two lines of text + a 48dp button row).
    private const val STRIP_TALL_MIN_HEIGHT_DP = 96

    // The cover alone above the footer: a narrow widget this tall (a 2x2 on
    // most phones), where the small card left a gap above its time left; and
    // any widget this tall, where the 4x2 card's square cover, growing with
    // its height, pushed the title out. Decoded at up to 320dp.
    private const val POSTER_NARROW_MIN_HEIGHT_DP = 190
    private const val POSTER_MIN_HEIGHT_DP = 250
    private const val POSTER_COVER_DP = 320

    private val executor = Executors.newSingleThreadExecutor()

    @Volatile
    private var playing = false

    fun update(context: Context, snapshot: Map<String, Any?>, playing: Boolean) {
        this.playing = playing
        val editor = prefs(context).edit().clear()
        for ((key, value) in snapshot) {
            when (value) {
                is String -> editor.putString(key, value)
                is Int -> editor.putInt(key, value)
                is Long -> editor.putInt(key, value.toInt())
                is Boolean -> editor.putBoolean(key, value)
            }
        }
        editor.apply()
        render(context)
    }

    /** Redraws every placed widget, off the main thread (covers decode). */
    fun render(context: Context) {
        val app = context.applicationContext
        executor.execute {
            try {
                renderNow(app)
            } catch (e: Exception) {
                Log.w(TAG, "render failed: $e")
            }
        }
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // The sizes launchers report, for the diagnostics log: on Android 12+ the
    // launcher picks the layout from them, and one (Kvaesitso) was seen to
    // change the layout over an app update with nothing else to go on. Kept
    // apart from [PREFS], which every update clears. Sizes only, no names.
    private const val LOG_PREFS = "saga_widget_log"
    private const val LOG_MAX_LINES = 20

    fun noteSize(context: Context, manager: AppWidgetManager, id: Int, reason: String) {
        try {
            val o = manager.getAppWidgetOptions(id)
            fun dp(key: String) = o.getInt(key)
            var line = "widget $id $reason: " +
                "w ${dp(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)}–" +
                "${dp(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)} × " +
                "h ${dp(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)}–" +
                "${dp(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)}dp"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val sizes = BundleCompat.getParcelableArrayList(
                    o, AppWidgetManager.OPTION_APPWIDGET_SIZES, SizeF::class.java)
                if (sizes != null) {
                    line += ", sizes " + sizes.joinToString(" ") {
                        "${it.width.toInt()}×${it.height.toInt()}"
                    }
                }
            }
            val time = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US)
                .format(java.util.Date())
            val log = context.getSharedPreferences(LOG_PREFS, Context.MODE_PRIVATE)
            val lines = log.getString("lines", "")!!.split('\n').filter { it.isNotEmpty() }
            log.edit().putString("lines", (lines + "$time $line").takeLast(LOG_MAX_LINES)
                .joinToString("\n")).apply()
        } catch (e: Exception) {
            Log.w(TAG, "noteSize failed: $e")
        }
    }

    /** The size lines noted since the last call, oldest first; clears them. */
    fun takeLog(context: Context): List<String> {
        val log = context.getSharedPreferences(LOG_PREFS, Context.MODE_PRIVATE)
        val lines = log.getString("lines", "")!!.split('\n').filter { it.isNotEmpty() }
        if (lines.isNotEmpty()) log.edit().remove("lines").apply()
        return lines
    }

    private fun renderNow(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, SagaWidgetProvider::class.java))
        if (ids.isEmpty()) return
        val p = prefs(context)
        when (p.getString("state", "empty")) {
            "book" -> renderBook(context, manager, ids, p, withCovers = true)
            "signedOut" -> renderEmpty(context, manager, ids, Palette(p), signedOut = true)
            else -> renderEmpty(context, manager, ids, Palette(p), signedOut = false)
        }
    }

    /** The empty or signed-out card, as one row or as the full card. */
    private fun renderEmpty(
        context: Context, manager: AppWidgetManager, ids: IntArray,
        palette: Palette, signedOut: Boolean,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            manager.updateAppWidget(ids, RemoteViews(mapOf(
                SizeF(110f, 40f) to emptyViews(context, palette, signedOut, R.layout.saga_widget_empty_strip),
                SizeF(110f, STRIP_MAX_HEIGHT_DP.toFloat()) to
                    emptyViews(context, palette, signedOut, R.layout.saga_widget_empty),
            )))
            return
        }
        for (id in ids) {
            val maxHeight = manager.getAppWidgetOptions(id)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
            val layout = if (maxHeight in 1 until STRIP_MAX_HEIGHT_DP) {
                R.layout.saga_widget_empty_strip
            } else {
                R.layout.saga_widget_empty
            }
            manager.updateAppWidget(id, emptyViews(context, palette, signedOut, layout))
        }
    }

    private fun renderBook(
        context: Context, manager: AppWidgetManager, ids: IntArray,
        p: SharedPreferences, withCovers: Boolean,
    ) {
        val density = context.resources.displayMetrics.density
        val palette = Palette(p)
        // Large draws at up to ~200dp (the card is as tall as the launcher
        // makes it), so decode for that, not the handoff's 124dp.
        val source = if (withCovers) loadSquare(p.getString("cover", null), (POSTER_COVER_DP * density).toInt()) else null
        // Small: inset cover, all corners at the 8dp cover radius. Large: flush
        // to the card's corner, so only the top-left is rounded, at the card's.
        // No cover: the mark stands in, in the theme's colours.
        // Strip: flush to the row's left edge like the mini player's cover, so
        // the left corners take the card's radius.
        val small = source?.let { rounded(it, (52 * density).toInt(), 8 * density, Corners.ALL) }
            ?: mark(palette, (52 * density).toInt())
        val large = source?.let { rounded(it, (LARGE_COVER_DP * density).toInt(), 14 * density, Corners.TOP_LEFT) }
            ?: mark(palette, (LARGE_COVER_DP * density).toInt())
        val strip = source?.let { rounded(it, (STRIP_COVER_DP * density).toInt(), 14 * density, Corners.LEFT) }
            ?: mark(palette, (STRIP_COVER_DP * density).toInt())
        val poster = source?.let { rounded(it, (POSTER_COVER_DP * density).toInt(), 12 * density, Corners.ALL) }
            ?: mark(palette, (POSTER_COVER_DP * density).toInt())
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // The launcher draws the largest of these that fits, and the
                // smallest when none does: a one-row widget is under
                // STRIP_MAX_HEIGHT_DP, so it gets a strip.
                val views = RemoteViews(mapOf(
                    SizeF(110f, 40f) to bookViews(context, p, palette, R.layout.saga_widget_strip, strip),
                    SizeF(110f, STRIP_TALL_MIN_HEIGHT_DP.toFloat()) to
                        bookViews(context, p, palette, R.layout.saga_widget_strip_tall, strip),
                    SizeF(110f, STRIP_MAX_HEIGHT_DP.toFloat()) to
                        bookViews(context, p, palette, R.layout.saga_widget_small, small),
                    SizeF(LARGE_MIN_WIDTH_DP.toFloat(), 150f) to bookViews(context, p, palette, R.layout.saga_widget_large, large),
                    // Twice: the launcher picks the largest *area* that fits,
                    // so the narrow key loses to the 4x2 card on a wide widget
                    // until the wide key, from 250dp, outweighs it.
                    // Narrow: no "Resume" beside the icon. Between two
                    // 56dp arrows on a 2x2 it wrapped to three lines.
                    SizeF(110f, POSTER_NARROW_MIN_HEIGHT_DP.toFloat()) to
                        bookViews(context, p, palette, R.layout.saga_widget_poster, poster)
                            .apply { setViewVisibility(R.id.saga_widget_play_label, View.GONE) },
                    SizeF(LARGE_MIN_WIDTH_DP.toFloat(), POSTER_MIN_HEIGHT_DP.toFloat()) to
                        bookViews(context, p, palette, R.layout.saga_widget_poster, poster),
                ))
                manager.updateAppWidget(ids, views)
            } else {
                for (id in ids) {
                    val options = manager.getAppWidgetOptions(id)
                    val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                    // In portrait the launcher's height is the max one.
                    val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
                    val views = when {
                        maxHeight >= POSTER_MIN_HEIGHT_DP ->
                            bookViews(context, p, palette, R.layout.saga_widget_poster, poster)
                        maxHeight in 1 until STRIP_TALL_MIN_HEIGHT_DP ->
                            bookViews(context, p, palette, R.layout.saga_widget_strip, strip)
                        maxHeight in 1 until STRIP_MAX_HEIGHT_DP ->
                            bookViews(context, p, palette, R.layout.saga_widget_strip_tall, strip)
                        minWidth >= LARGE_MIN_WIDTH_DP ->
                            bookViews(context, p, palette, R.layout.saga_widget_large, large)
                        maxHeight >= POSTER_NARROW_MIN_HEIGHT_DP ->
                            bookViews(context, p, palette, R.layout.saga_widget_poster, poster)
                                .apply { setViewVisibility(R.id.saga_widget_play_label, View.GONE) }
                        else -> bookViews(context, p, palette, R.layout.saga_widget_small, small)
                    }
                    manager.updateAppWidget(id, views)
                }
            }
        } catch (e: IllegalArgumentException) {
            // Over the launcher's bitmap memory limit (Auxio hit this): draw
            // the card without covers rather than not at all.
            if (!withCovers) throw e
            Log.w(TAG, "cover over the bitmap limit, drawing without: $e")
            renderBook(context, manager, ids, p, withCovers = false)
        }
    }

    private fun bookViews(
        context: Context, p: SharedPreferences, palette: Palette, layout: Int, cover: Bitmap,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, layout)
        palette.applyChrome(v)
        v.setTextColor(R.id.saga_widget_title, palette.fg)
        v.setTextColor(R.id.saga_widget_chapter, palette.fgMuted)
        v.setTextColor(R.id.saga_widget_time_left, palette.fg)
        v.setTextColor(R.id.saga_widget_percent, palette.fgSubtle)
        v.setInt(R.id.saga_widget_play_icon, "setColorFilter", palette.accentFg)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            v.setColorStateList(R.id.saga_widget_bar, "setProgressTintList",
                ColorStateList.valueOf(palette.bar))
            v.setColorStateList(R.id.saga_widget_bar, "setProgressBackgroundTintList",
                ColorStateList.valueOf(palette.track))
        }
        val book = p.getString("bookKey", null)
        v.setTextViewText(R.id.saga_widget_title, p.getString("title", ""))
        val chapter = p.getString("chapter", null)
        if (chapter == null) {
            v.setViewVisibility(R.id.saga_widget_chapter, View.GONE)
        } else {
            v.setViewVisibility(R.id.saga_widget_chapter, View.VISIBLE)
            v.setTextViewText(R.id.saga_widget_chapter, chapter)
        }
        v.setTextViewText(R.id.saga_widget_time_left, p.getString("timeLeft", ""))
        v.setTextViewText(R.id.saga_widget_percent, p.getString("percent", ""))
        v.setProgressBar(R.id.saga_widget_bar, 1000, p.getInt("progress", 0), false)
        v.setImageViewBitmap(R.id.saga_widget_cover, cover)

        val back = p.getInt("skipBack", 30)
        val forward = p.getInt("skipForward", 30)
        // Skip is drawn as in the player: an arrow with the seconds inside,
        // in the footer's ink (every layout's buttons sit on the footer).
        val ink = palette.accentFg
        v.setTextViewText(R.id.saga_widget_back_num, "$back")
        v.setTextViewText(R.id.saga_widget_forward_num, "$forward")
        for (id in intArrayOf(R.id.saga_widget_back_num, R.id.saga_widget_forward_num)) {
            v.setTextColor(id, ink)
        }
        for (id in intArrayOf(R.id.saga_widget_back_icon, R.id.saga_widget_forward_icon)) {
            v.setInt(id, "setColorFilter", ink)
        }
        v.setContentDescription(R.id.saga_widget_back_btn,
            context.getString(R.string.saga_widget_skip_back, back))
        v.setContentDescription(R.id.saga_widget_forward_btn,
            context.getString(R.string.saga_widget_skip_forward, forward))
        // The app badge, as Audible and Spotify carry theirs.
        v.setInt(R.id.saga_widget_badge, "setColorFilter", palette.fg)

        val playing = this.playing
        v.setImageViewResource(R.id.saga_widget_play_icon,
            if (playing) R.drawable.saga_widget_pause else R.drawable.saga_widget_play)
        val label = context.getString(if (playing) R.string.saga_widget_pause else R.string.saga_widget_resume)
        v.setContentDescription(R.id.saga_widget_play_pause, label)
        if (layout == R.layout.saga_widget_large || layout == R.layout.saga_widget_poster) {
            v.setTextViewText(R.id.saga_widget_play_label, label)
            v.setTextColor(R.id.saga_widget_play_label, palette.accentFg)
        }
        // Views a layout lacks (title, chapter, badge, time left, %, bar)
        // ignore what's set on them above: a RemoteViews action on a missing
        // id does nothing.

        v.setOnClickPendingIntent(R.id.saga_widget_body, openApp(context))
        v.setOnClickPendingIntent(R.id.saga_widget_play_pause,
            if (playing) serviceAction(context, RC_PAUSE, "widgetPause", null, null)
            else serviceAction(context, RC_PLAY, "widgetPlay", book, null))
        v.setOnClickPendingIntent(R.id.saga_widget_back_btn,
            serviceAction(context, RC_BACK, "widgetSkip", book, forward = false))
        v.setOnClickPendingIntent(R.id.saga_widget_forward_btn,
            serviceAction(context, RC_FORWARD, "widgetSkip", book, forward = true))
        return v
    }

    private fun emptyViews(
        context: Context, palette: Palette, signedOut: Boolean, layout: Int,
    ): RemoteViews {
        // The strip has no footer or action button; what's set on them here
        // does nothing there (a RemoteViews action on a missing id is a no-op).
        val v = RemoteViews(context.packageName, layout)
        palette.applyChrome(v)
        v.setTextColor(R.id.saga_widget_empty_title, palette.fg)
        v.setTextColor(R.id.saga_widget_empty_subtitle, palette.fgMuted)
        v.setTextColor(R.id.saga_widget_empty_action, palette.accentFg)
        val density = context.resources.displayMetrics.density
        v.setImageViewBitmap(R.id.saga_widget_empty_mark, mark(palette, (52 * density).toInt()))
        if (signedOut) {
            v.setTextViewText(R.id.saga_widget_empty_title, context.getString(R.string.saga_widget_signed_out_title))
            v.setTextViewText(R.id.saga_widget_empty_subtitle, context.getString(R.string.saga_widget_signed_out_subtitle))
            v.setTextViewText(R.id.saga_widget_empty_action, context.getString(R.string.saga_widget_signed_out_action))
        }
        val open = openApp(context)
        v.setOnClickPendingIntent(R.id.saga_widget_body, open)
        v.setOnClickPendingIntent(R.id.saga_widget_empty_action, open)
        return v
    }

    private fun openApp(context: Context): PendingIntent? {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return null
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(context, RC_OPEN, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** A foreground start of audio_service carrying a custom action for Dart. */
    private fun serviceAction(
        context: Context, requestCode: Int, name: String, book: String?, forward: Boolean?,
    ): PendingIntent {
        val extras = Bundle().apply {
            book?.let { putString("book", it) }
            forward?.let { putBoolean("forward", it) }
        }
        val intent = Intent(ACTION_CUSTOM).apply {
            component = ComponentName(context.packageName, AUDIO_SERVICE)
            putExtra(EXTRA_NAME, name)
            putExtra(EXTRA_EXTRAS, extras)
        }
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(context, requestCode, intent, flags)
        } else {
            PendingIntent.getService(context, requestCode, intent, flags)
        }
    }

    /**
     * The app's theme, sent by Dart with every snapshot (Dart reads the stored
     * theme itself, so a headless engine gets it right too). Ink when absent.
     */
    private class Palette(p: SharedPreferences) {
        val surface = p.getInt("colorSurface", 0xFF261B16.toInt())
        val track = p.getInt("colorTrack", 0xFF2F221C.toInt())
        val fg = p.getInt("colorFg", 0xFFF4EAD8.toInt())
        val fgMuted = p.getInt("colorFgMuted", 0xA6F4EAD8.toInt())
        val fgSubtle = p.getInt("colorFgSubtle", 0x84F4EAD8.toInt())
        val bar = p.getInt("colorBar", 0xFFE0A050.toInt())
        val footer = p.getInt("colorFooter", 0xFFE0A050.toInt())
        val accentFg = p.getInt("colorAccentFg", 0xFF1E1410.toInt())
        val markSide = p.getInt("colorMarkSide", 0xFFF4EAD8.toInt())
        val markMiddle = p.getInt("colorMarkMiddle", 0xFFE0A050.toInt())

        /** Card and footer are white shapes, tinted: remotable on every API. */
        fun applyChrome(v: RemoteViews) {
            v.setInt(R.id.saga_widget_bg, "setColorFilter", surface)
            v.setInt(R.id.saga_widget_footer_bg, "setColorFilter", footer)
        }
    }

    /** The 4-spine mark (brand/assets/svg/mark, 200 box) in the theme's colours. */
    private fun mark(palette: Palette, sizePx: Int): Bitmap {
        val out = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val scale = sizePx / 200f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        // x, y, height; every spine is 22 wide with radius 5.
        val spines = listOf(
            Triple(41f, 48f, 104f), Triple(73f, 38f, 124f),
            Triple(105f, 56f, 88f), Triple(137f, 46f, 108f),
        )
        spines.forEachIndexed { i, (x, y, h) ->
            paint.color = if (i == 1) palette.markMiddle else palette.markSide
            canvas.drawRoundRect(
                RectF(x * scale, y * scale, (x + 22f) * scale, (y + h) * scale),
                5f * scale, 5f * scale, paint)
        }
        return out
    }

    /** The cover file, decoded no larger than needed and cropped square. */
    private fun loadSquare(path: String?, targetPx: Int): Bitmap? {
        if (path == null || !File(path).isFile) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            var sample = 1
            while (min(bounds.outWidth, bounds.outHeight) / (sample * 2) >= targetPx) sample *= 2
            val bitmap = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
                inSampleSize = sample
            }) ?: return null
            val side = min(bitmap.width, bitmap.height)
            Bitmap.createBitmap(bitmap, (bitmap.width - side) / 2, (bitmap.height - side) / 2, side, side)
        } catch (e: Throwable) {
            // A damaged file or no memory: the mark stands in for the cover.
            Log.w(TAG, "cover decode failed: $e")
            null
        }
    }

    private enum class Corners { ALL, TOP_LEFT, LEFT }

    private fun rounded(src: Bitmap, sizePx: Int, radiusPx: Float, corners: Corners): Bitmap {
        val scaled = Bitmap.createScaledBitmap(src, sizePx, sizePx, true)
        val out = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            shader = BitmapShader(scaled, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        }
        val rect = RectF(0f, 0f, sizePx.toFloat(), sizePx.toFloat())
        // Pairs, clockwise from top-left: top-left, top-right, bottom-right,
        // bottom-left.
        val r = radiusPx
        val radii = when (corners) {
            Corners.ALL -> FloatArray(8) { r }
            Corners.TOP_LEFT -> floatArrayOf(r, r, 0f, 0f, 0f, 0f, 0f, 0f)
            Corners.LEFT -> floatArrayOf(r, r, 0f, 0f, 0f, 0f, r, r)
        }
        Canvas(out).drawPath(Path().apply { addRoundRect(rect, radii, Path.Direction.CW) }, paint)
        return out
    }
}
