package com.gaut3.saga.nativebridge

import android.content.Context
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.cast.framework.media.CastMediaOptions

class CastOptionsProvider : OptionsProvider {
    companion object {
        // Default Media Receiver — plays audio without requiring a registered
        // app ID, and can't go "Page Not Found" when a custom receiver's host
        // moves (Audiobookshelf #1903).
        const val RECEIVER_ID = "CC1AD845"
    }

    override fun getCastOptions(context: Context): CastOptions {
        return CastOptions.Builder()
            .setReceiverApplicationId(RECEIVER_ID)
            // The SDK declares ReconnectionService with no foregroundServiceType,
            // which crashes on Android 14+ when it goes foreground (absorb #338).
            // Its job, keeping a backgrounded app alive to reconnect, is done by
            // Saga's own playback service while casting. Off, rather than
            // declaring it connectedDevice and adding two permissions for it.
            .setEnableReconnectionService(false)
            // No SDK notification and no SDK media session: Saga's own
            // playback service stands for the TV while casting, so the lock
            // screen, Bluetooth and the widget all reach one handler. With
            // these on, a cast showed two notifications (AntennaPod #5728).
            .setCastMediaOptions(
                CastMediaOptions.Builder()
                    .setNotificationOptions(null)
                    .setMediaSessionEnabled(false)
                    .build()
            )
            .build()
    }

    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? = null
}
