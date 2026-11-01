package com.gaut3.saga.nativebridge

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Saga's native code that has to exist on every Flutter engine: the widget and
 * the Cast bridge. A plugin, not channels on MainActivity, because audio_service
 * builds its own engine with no activity when the widget (or a notification, or
 * the car) cold-starts the app.
 */
class SagaNativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var castChannel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.gaut3.saga/widget")
        channel.setMethodCallHandler(this)
        castChannel = MethodChannel(binding.binaryMessenger, "com.gaut3.saga/cast")
        CastBridge.attach(context, castChannel)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        CastBridge.detach(castChannel)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "update" -> {
                val snapshot = call.argument<Map<String, Any?>>("snapshot") ?: emptyMap()
                val playing = call.argument<Boolean>("playing") ?: false
                SagaWidget.update(context, snapshot, playing)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
