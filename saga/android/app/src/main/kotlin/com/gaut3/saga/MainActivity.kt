package com.gaut3.saga

import android.app.AlertDialog
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.annotation.RequiresApi
import android.view.Surface
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    // Cast lives in the saga_native plugin (CastBridge), so it survives this
    // activity and exists on engines that never had one.

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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

    // Scroll-time frame-rate vote (see lib/core/scroll_frame_rate.dart). Flutter
    // renders into one SurfaceView that never states a rate, so adaptive-
    // refresh phones give it the "normal" rate — 60 Hz on a 120 Hz Pixel.
    // Voting on that surface while a list moves lifts it to the display's top
    // rate; a vote of 0 withdraws it. Android clamps the vote to the user's
    // cap (Smooth display off, Battery Saver), so it never overrides them.
    private fun setFrameRateBoost(boost: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val surface = findSurfaceView(window.decorView)?.holder?.surface ?: return
        if (!surface.isValid) return
        try {
            surface.setFrameRate(
                if (boost) maxRefreshRate() else 0f,
                Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
            )
        } catch (e: Exception) {
            // A surface torn down between the check and the call; the next
            // scroll votes again.
        }
    }

    // API 30+ only, like its one caller (Surface.setFrameRate is API 30):
    // the pre-30 branch through the deprecated windowManager.defaultDisplay
    // could never run, and only drew a CodeQL alert (#15).
    @RequiresApi(Build.VERSION_CODES.R)
    private fun maxRefreshRate(): Float {
        val d = display ?: return 120f
        return d.supportedModes.maxOfOrNull { it.refreshRate } ?: 120f
    }

    private fun findSurfaceView(view: View): SurfaceView? {
        if (view is SurfaceView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findSurfaceView(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "com.gaut3.saga/frame_rate"
        ).setMethodCallHandler { call, result ->
            if (call.method == "setBoost") {
                setFrameRateBoost(call.arguments as? Boolean ?: false)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
