package com.gaut3.saga.nativebridge

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri

/**
 * Not a real provider: Android creates every declared provider when the
 * process starts, before Application.onCreate and before any Dart. That makes
 * it the one hook that runs on *every* start (an app update, a broadcast, the
 * widget's own button), which is when the widget must stop showing a "pause"
 * left by a process that died mid-play. Playing is held in memory only, so a
 * new process draws paused until Dart says otherwise.
 */
class WidgetProcessStart : ContentProvider() {
    override fun onCreate(): Boolean {
        context?.let { SagaWidget.render(it) }
        return true
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
                       selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?,
                        selectionArgs: Array<out String>?): Int = 0
}
