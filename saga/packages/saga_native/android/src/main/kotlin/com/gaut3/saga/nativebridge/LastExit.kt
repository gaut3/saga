package com.gaut3.saga.nativebridge

import android.app.ActivityManager
import android.app.ActivityManager.RunningAppProcessInfo
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Why Saga's previous process ended, as Android recorded it, for the
 * diagnostics log. A native crash or the system killing the app leaves no
 * line of Saga's own: the log just shows a second launch, and "the book
 * paused by itself" can't be told from a crash or a kill (#32).
 *
 * One line, about Saga's own process only: the reason, what the process was
 * doing (playing in the foreground service, cached, on screen), when, and
 * its memory. Never the crash or ANR trace.
 */
object LastExit {
    fun describe(context: Context): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val info = am.getHistoricalProcessExitReasons(null, 0, 5)
                .firstOrNull { it.processName == context.packageName }
                ?: return null
            val at = SimpleDateFormat("MM-dd HH:mm:ss", Locale.US).format(Date(info.timestamp))
            buildString {
                append(reason(info.reason))
                // The signal or exit code: 9 is a kill, 11 a segfault.
                if (info.status != 0) append(" (status ${info.status})")
                append(" at $at, was ${importance(info.importance)}")
                if (info.rss > 0) append(", ${info.rss / 1024} MB")
                info.description?.takeIf { it.isNotBlank() }?.let {
                    append(": ${it.take(80)}")
                }
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun reason(code: Int) = when (code) {
        ApplicationExitInfo.REASON_EXIT_SELF -> "exited itself"
        ApplicationExitInfo.REASON_SIGNALED -> "killed by a signal"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "killed for memory"
        ApplicationExitInfo.REASON_CRASH -> "crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "native crash"
        ApplicationExitInfo.REASON_ANR -> "not responding (ANR)"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "failed to start"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "permission changed"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "killed for resource use"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "closed by the user"
        ApplicationExitInfo.REASON_USER_STOPPED -> "user stopped"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "a dependency died"
        ApplicationExitInfo.REASON_OTHER -> "killed by the system"
        // FREEZER (14) and later reasons, without needing their API level.
        else -> "reason $code"
    }

    private fun importance(code: Int) = when (code) {
        RunningAppProcessInfo.IMPORTANCE_FOREGROUND -> "on screen"
        RunningAppProcessInfo.IMPORTANCE_FOREGROUND_SERVICE -> "in the foreground service"
        RunningAppProcessInfo.IMPORTANCE_VISIBLE -> "visible"
        RunningAppProcessInfo.IMPORTANCE_PERCEPTIBLE -> "perceptible"
        RunningAppProcessInfo.IMPORTANCE_SERVICE -> "a background service"
        RunningAppProcessInfo.IMPORTANCE_TOP_SLEEPING -> "on screen, phone asleep"
        RunningAppProcessInfo.IMPORTANCE_CACHED -> "cached"
        else -> "importance $code"
    }
}
