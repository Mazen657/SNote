package com.mazen.snote

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * FlutterFragmentActivity is required for the local_auth plugin's biometric
 * dialogs on Android.
 *
 * FLAG_SECURE is applied in onCreate so it covers every Activity lifecycle
 * state — including rotation, split-screen, and the recents thumbnail.
 * It blocks:
 *   - Manual screenshots (power + volume-down)
 *   - Screen-recording via the system recorder or third-party apps
 *   - The recents / recent-apps thumbnail preview
 */
class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableSecureWindow()
    }

    private fun enableSecureWindow() {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }
}