package com.ryanheise.just_audio;

import android.content.Context;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * JustAudioPlugin
 */
public class JustAudioPlugin implements FlutterPlugin {
    private MethodChannel channel;
    private MainMethodCallHandler methodCallHandler;
    // Saga: global RMS channel for the real-loudness visualizer. Registered at
    // attach (not per-player) so Dart can listen at app start, before any player
    // connects. Emitted by AudioPlayer's TeeAudioProcessor.
    static BetterEventChannel rmsEventChannel;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        Context applicationContext = binding.getApplicationContext();
        BinaryMessenger messenger = binding.getBinaryMessenger();
        methodCallHandler = new MainMethodCallHandler(applicationContext, messenger);

        channel = new MethodChannel(messenger, "com.ryanheise.just_audio.methods");
        channel.setMethodCallHandler(methodCallHandler);
        rmsEventChannel = new BetterEventChannel(messenger, "com.ryanheise.just_audio.rms");
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        methodCallHandler.dispose();
        methodCallHandler = null;

        channel.setMethodCallHandler(null);
        rmsEventChannel = null;
    }
}
