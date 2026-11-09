package com.gaut3.saga

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

/**
 * Serves the cover cache to Android Auto, read-only, as `content://` URIs.
 *
 * Auto draws the browse tree in its own process and only loads artwork through
 * a content resolver: a `file://` path into Saga's private storage names a file
 * it can't open, so every shelf showed blank tiles. The covers themselves stay
 * where `ArtworkCache` writes them; this only opens them for reading.
 *
 * Exported, because the readers (Android Auto, the media-resumption card,
 * whatever head unit) aren't ours to list and hold no permission of ours. What
 * that exposes is a cover picture to an app that already knows its name, and
 * the names are only handed out through the browse tree, which any app can
 * read already. Nothing else is reachable: one path segment, the cache's own
 * filename shape, no `..`, no other directory, no writes.
 *
 * The authority is `ArtworkCache.sharedAuthority` on the Dart side.
 */
class CoverProvider : ContentProvider() {

    override fun onCreate() = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw SecurityException("Covers are read-only")
        val name = uri.pathSegments.singleOrNull()
        if (name == null || !COVER_NAME.matches(name)) throw FileNotFoundException()
        // path_provider's getApplicationDocumentsDirectory() on Android.
        val dir = File(context!!.getDir("flutter", Context.MODE_PRIVATE), "artwork_cache")
        // Open what the cache holds, not a path built from the caller's name:
        // a second guard behind the regex, and the one CodeQL can see.
        val file = dir.listFiles { f -> f.isFile && f.name == name }?.singleOrNull()
            ?: throw FileNotFoundException()
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String? = null

    override fun query(
        uri: Uri, projection: Array<String>?, selection: String?,
        selectionArgs: Array<String>?, sortOrder: String?,
    ): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun update(
        uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<String>?,
    ) = 0

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?) = 0

    private companion object {
        /** `ArtworkCache._filename`: a 32-bit hash in hex, then `.art`. */
        val COVER_NAME = Regex("^[0-9a-f]{1,8}\\.art$")
    }
}
