package com.mazen.snote

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes [RootDetectionHelper] to the Flutter/Dart layer via a MethodChannel.
 *
 * Channel name : "com.mazen.snote/root_detection"
 * Supported methods:
 *   - "isRooted"  → Boolean
 *
 * The check is intentionally synchronous from Dart's perspective.  Flutter
 * calls it with `await channel.invokeMethod<bool>('isRooted')` in main()
 * before any sensitive work begins, ensuring the result is available before
 * the first frame is rendered.
 */
class RootDetectionChannel(
    private val context: Context,
    private val messenger: io.flutter.plugin.common.BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.mazen.snote/root_detection"
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    fun register() {
        channel.setMethodCallHandler(this)
    }

    fun unregister() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isRooted" -> {
                // Run on the calling thread (Flutter's platform thread).
                // RootDetectionHelper is fast enough (<50 ms on cold path)
                // that posting to a background thread is unnecessary and would
                // add complexity with little gain.
                val rooted = RootDetectionHelper.isRooted(context)
                result.success(rooted)
            }
            else -> result.notImplemented()
        }
    }
}