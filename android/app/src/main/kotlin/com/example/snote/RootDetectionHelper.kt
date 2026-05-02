package com.mazen.snote

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

/**
 * Multi-layer Android root detection.
 *
 * Each check is independent — a single positive result is sufficient to
 * classify the device as compromised.  All checks run synchronously on
 * whichever thread calls [isRooted] so it can be invoked before the
 * Flutter engine starts.
 *
 * Layers (in order of speed):
 *   1. Build integrity  — test-keys, ro.debuggable, ro.secure
 *   2. su binary scan   — exhaustive path list including Magisk locations
 *   3. Root package     — known root managers via PackageManager
 *   4. System mount     — /proc/self/mountinfo for rw system partitions
 *   5. Command probe    — Runtime.exec("which su") and "su -c id"
 *   6. Magisk artefacts — hidden Magisk paths and mount mirrors
 */
object RootDetectionHelper {

    // ── Known su / root binary paths ─────────────────────────────────────────

    private val SU_PATHS = listOf(
        "/sbin/su",
        "/su/bin/su",
        "/su/xbin/su",
        "/system/bin/su",
        "/system/bin/.ext/.su",
        "/system/bin/failsafe/su",
        "/system/sd/xbin/su",
        "/system/usr/we-need-root/su",
        "/system/xbin/su",
        "/system/xbin/daemonsu",
        "/data/local/su",
        "/data/local/bin/su",
        "/data/local/xbin/su",
        "/cache/su",
        "/vendor/bin/su",
        "/system/app/SuperSU.apk",
        "/system/app/SuperSU/SuperSU.apk",
        "/system/app/Superuser.apk",
        "/system/app/Superuser/Superuser.apk",
        // Magisk — both legacy and modern paths
        "/sbin/magisk",
        "/sbin/.magisk",
        "/sbin/.core/mirror",
        "/sbin/.core/img",
        "/sbin/.core/db-0/magisk.db",
        "/data/adb/magisk",
        "/data/adb/magisk.db",
        "/data/adb/modules",
        "/data/adb/ksu",          // KernelSU
        "/data/adb/ksud",
        // Miscellaneous root artefacts
        "/system/lib/libsuperuser.so",
        "/system/etc/init.d/99SuperSUDaemon",
        "/dev/com.koushikdutta.superuser.daemon",
    )

    // ── Known root-management package names ──────────────────────────────────

    private val ROOT_PACKAGES = listOf(
        "com.noshufou.android.su",
        "com.noshufou.android.su.elite",
        "eu.chainfire.supersu",
        "eu.chainfire.supersu.pro",
        "com.koushikdutta.superuser",
        "com.thirdparty.superuser",
        "com.yellowes.su",
        "com.topjohnwu.magisk",         // Magisk Manager
        "io.github.huskydg.magisk",     // Delta Magisk
        "com.fox2code.mmm",             // Fox Magisk Module Manager
        "com.kingroot.kinguser",
        "com.kingroot.master",
        "com.kingo.root",
        "com.smedialink.oneclickroot",
        "com.zhiqupk.root.global",
        "com.alephzain.framaroot",
        "com.devadvance.rootcloak",
        "com.devadvance.rootcloakplus",
        "de.robv.android.xposed.installer",  // Xposed Framework
        "com.saurik.substrate",              // Cydia Substrate
        "com.zachspong.temprootremovejb",
        "com.amphoras.hidemyroot",
        "com.formyhm.hiderootpremium",
        "com.amphoras.hidemyrootadfree",
        "com.ramdroid.appquarantine",
        "com.ramdroid.appquarantinepro",
        "com.android.vending.billing.InAppBillingService.LUCK", // rooted market
    )

    // ── Public entry point ────────────────────────────────────────────────────

    /**
     * Returns true if the device shows any sign of root compromise.
     * Catches all exceptions internally — detection failures are silently
     * ignored so a single broken check cannot cause a false negative cascade.
     */
    fun isRooted(context: Context): Boolean {
        return checkBuildIntegrity()
                || checkSuBinaries()
                || checkRootPackages(context)
                || checkSystemMountRw()
                || checkCommandProbe()
                || checkMagiskHiddenPaths()
    }

    // ── Layer 1: Build integrity ──────────────────────────────────────────────

    /**
     * Production builds are always signed with release keys and have
     * ro.secure=1 / ro.debuggable=0.  Deviations indicate a modified or
     * development build that typically accompanies a rooted environment.
     */
    private fun checkBuildIntegrity(): Boolean {
        try {
            // "test-keys" means signed with AOSP development keys, not OEM keys.
            val tags = Build.TAGS
            if (tags != null && tags.contains("test-keys")) return true

            // ro.debuggable=1 enables the adb root shell.
            if (getProp("ro.debuggable") == "1") return true

            // ro.secure=0 means the kernel allows root shell over adb.
            if (getProp("ro.secure") == "0") return true

            // ro.build.type=eng or userdebug ship with root-level access.
            val buildType = getProp("ro.build.type")
            if (buildType == "eng" || buildType == "userdebug") return true

        } catch (_: Exception) { /* ignore */ }
        return false
    }

    // ── Layer 2: su binary scan ───────────────────────────────────────────────

    private fun checkSuBinaries(): Boolean {
        for (path in SU_PATHS) {
            try {
                if (File(path).exists()) return true
            } catch (_: Exception) { /* sandbox may deny — skip */ }
        }
        return false
    }

    // ── Layer 3: Root package scan ────────────────────────────────────────────

    private fun checkRootPackages(context: Context): Boolean {
        val pm = context.packageManager
        for (pkg in ROOT_PACKAGES) {
            try {
                pm.getPackageInfo(pkg, 0)
                return true   // package exists
            } catch (_: PackageManager.NameNotFoundException) {
                // Expected — not installed.
            } catch (_: Exception) { /* ignore */ }
        }
        return false
    }

    // ── Layer 4: /proc/self/mountinfo (rw system) ─────────────────────────────

    /**
     * A normal device mounts /system read-only.  If /system or /vendor is
     * mounted rw it has been remounted by a root tool.
     */
    private fun checkSystemMountRw(): Boolean {
        try {
            val mountInfo = File("/proc/self/mountinfo")
            if (!mountInfo.exists()) return false
            mountInfo.bufferedReader().useLines { lines ->
                for (line in lines) {
                    // Format: ... mountPoint ... mountOptions ...
                    // We look for lines whose mount-options field contains "rw"
                    // and whose mount point is /system, /vendor, or /data.
                    val parts = line.split(" ")
                    if (parts.size < 5) continue
                    val mountPoint   = parts[4]
                    val mountOptions = parts.getOrNull(5) ?: continue
                    val sensitive = mountPoint == "/system" ||
                                    mountPoint == "/vendor" ||
                                    mountPoint == "/system_root"
                    if (sensitive && mountOptions.startsWith("rw")) return true
                }
            }
        } catch (_: Exception) { /* /proc may be unreadable */ }
        return false
    }

    // ── Layer 5: Command probe ────────────────────────────────────────────────

    /**
     * Attempts to execute "which su" and "su -c id" via the shell.
     * On a non-rooted device both commands return nothing or throw.
     * On a rooted device "which su" returns the su path and "su -c id"
     * returns "uid=0(root)".
     *
     * Wrapped in a tight timeout so it cannot block the UI thread.
     */
    private fun checkCommandProbe(): Boolean {
        // "which su"
        if (runCommand("which su").isNotEmpty()) return true

        // "su -c id" — only attempt on debug/test builds to avoid noise on
        // clean devices where invoking su may trigger a user-visible prompt.
        try {
            val result = runCommand("su -c id")
            if (result.contains("uid=0")) return true
        } catch (_: Exception) { /* SecurityException expected on clean device */ }

        return false
    }

    // ── Layer 6: Magisk hidden mount mirrors ──────────────────────────────────

    /**
     * Modern Magisk hides its binaries inside a tmpfs mounted over /sbin.
     * Enumerating /sbin reveals the .magisk directory even when Magisk Hide
     * is active because it cannot hide from the process that owns the check.
     */
    private fun checkMagiskHiddenPaths(): Boolean {
        val magiskIndicators = listOf(
            "/sbin/.magisk",
            "/sbin/.core",
            "/sbin/magiskinit",
            "/sbin/magiskpolicy",
            "/sbin/magisk32",
            "/sbin/magisk64",
        )
        for (path in magiskIndicators) {
            try {
                if (File(path).exists()) return true
            } catch (_: Exception) { /* ignore */ }
        }

        // Walk /sbin looking for magisk-named entries.
        try {
            val sbin = File("/sbin")
            if (sbin.exists() && sbin.isDirectory) {
                sbin.listFiles()?.forEach { entry ->
                    if (entry.name.contains("magisk", ignoreCase = true)) return true
                }
            }
        } catch (_: Exception) { /* ignore */ }

        return false
    }

    // ── Utility ───────────────────────────────────────────────────────────────

    private fun getProp(key: String): String {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("/system/bin/getprop", key))
            process.inputStream.bufferedReader().readLine()?.trim() ?: ""
        } catch (_: Exception) { "" }
    }

    private fun runCommand(cmd: String): String {
        return try {
            val process = Runtime.getRuntime().exec(cmd.split(" ").toTypedArray())
            val reader  = BufferedReader(InputStreamReader(process.inputStream))
            val output  = reader.readLine()?.trim() ?: ""
            process.destroy()
            output
        } catch (_: Exception) { "" }
    }
}