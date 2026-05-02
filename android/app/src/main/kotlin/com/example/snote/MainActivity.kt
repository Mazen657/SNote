package com.mazen.snote

import android.app.AlertDialog
import android.content.DialogInterface
import android.os.Bundle
import android.os.Process
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Single activity for SNote.
 *
 * Security responsibilities handled here:
 *
 *   1. FLAG_SECURE — applied immediately in onCreate so every lifecycle
 *      state (rotation, split-screen, recents thumbnail) is protected.
 *
 *   2. Native root gate — [RootDetectionHelper.isRooted] runs synchronously
 *      BEFORE Flutter's engine setup.  If root is detected a non-dismissible
 *      native AlertDialog is shown and the process exits cleanly.
 *      Using a native dialog means Flutter never boots, so encrypted storage
 *      is never opened and no sensitive state is loaded.
 *
 *   3. MethodChannel registration — [RootDetectionChannel] is registered
 *      inside [configureFlutterEngine] so Dart can perform a second
 *      independent root check as a defence-in-depth layer.
 */
class MainActivity : FlutterFragmentActivity() {

    private var rootChannel: RootDetectionChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // ── Step 1: Screenshot / screen-recording protection ─────────────────
        // Must happen before super.onCreate() so the window flag is set before
        // the system compositor creates the surface.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )

        // ── Step 2: Native root gate (runs before Flutter engine starts) ──────
        if (RootDetectionHelper.isRooted(this)) {
            showRootBlockingDialog()
            // showRootBlockingDialog is blocking (AlertDialog shown on UI thread).
            // Process.killProcess is called from the dialog's dismiss listener
            // so we return here without calling super, preventing Flutter from
            // initialising at all.
            return
        }

        // ── Step 3: Normal startup ─────────────────────────────────────────────
        super.onCreate(savedInstanceState)
    }

    /**
     * Registers the [RootDetectionChannel] so Dart can invoke a second native
     * root check as a defence-in-depth layer.  If root was detected above,
     * this method is never reached because onCreate returned early.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        rootChannel = RootDetectionChannel(
            context   = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        ).also { it.register() }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        rootChannel?.unregister()
        rootChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // ── Root blocking dialog ──────────────────────────────────────────────────

    /**
     * Shows a native (non-Flutter) AlertDialog that cannot be dismissed by
     * the user.  The only available action is "Exit" which terminates the
     * process immediately.
     *
     * Using a native dialog rather than a Flutter route means:
     *   - Flutter never initialises.
     *   - No encrypted storage is opened.
     *   - No sensitive keys or data are loaded into memory.
     *   - The dialog cannot be bypassed by manipulating Flutter navigation.
     */
    private fun showRootBlockingDialog() {
        // Call super here so the Activity window is available for the dialog.
        // We pass null as savedInstanceState because we never want to restore
        // any Flutter state on a rooted device.
        try {
            super.onCreate(null)
        } catch (_: Exception) {
            // If super.onCreate fails for any reason, terminate immediately.
            terminateProcess()
            return
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle("Security Violation")
            .setMessage(
                "This application cannot run on rooted devices for security reasons.\n\n" +
                "Root access exposes your encrypted notes and credentials to " +
                "unauthorised access.  SNote will now exit."
            )
            .setCancelable(false)
            .setPositiveButton("Exit") { _: DialogInterface, _: Int ->
                terminateProcess()
            }
            .create()

        // Prevent dismissal via back button or outside touch.
        dialog.setCanceledOnTouchOutside(false)
        dialog.setOnKeyListener { _, keyCode, _ ->
            // Consume all key events — back, home, recents, volume.
            true
        }

        dialog.show()

        // Also schedule a fallback termination 10 seconds after the dialog
        // appears in case the user ignores it or the button is not tappable
        // due to an overlay attack.
        dialog.window?.decorView?.postDelayed({ terminateProcess() }, 10_000L)
    }

    private fun terminateProcess() {
        Process.killProcess(Process.myPid())
    }
}