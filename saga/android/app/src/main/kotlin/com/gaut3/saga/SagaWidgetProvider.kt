package com.gaut3.saga

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.KeyEvent
import android.widget.RemoteViews
import com.ryanheise.audioservice.AudioService

/**
 * Home-screen widget. 1.2.0 spike: one play button, to prove a press on a dead
 * process reaches Dart (audio_service patch #3) before the resume-card layout
 * is built on top of it.
 *
 * Play goes straight to [AudioService] as a foreground start carrying a media
 * button, so it takes the same path as the notification's play: Dart's
 * `play()`, which restores the last book when none is loaded.
 */
class SagaWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = RemoteViews(context.packageName, R.layout.saga_widget)
        views.setOnClickPendingIntent(R.id.saga_widget_play, playIntent(context))
        manager.updateAppWidget(ids, views)
    }

    private fun playIntent(context: Context): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(context, AudioService::class.java)
            // The "bypass" keycode is audio_service's explicit play (onPlay);
            // a genuine KEYCODE_MEDIA_PLAY is treated as a click and toggles.
            putExtra(
                Intent.EXTRA_KEY_EVENT,
                KeyEvent(KeyEvent.ACTION_DOWN, AudioService.KEYCODE_BYPASS_PLAY),
            )
        }
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(context, 0, intent, flags)
        } else {
            PendingIntent.getService(context, 0, intent, flags)
        }
    }
}
