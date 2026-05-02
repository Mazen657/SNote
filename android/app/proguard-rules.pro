# ── Flutter ───────────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# ── SNote native security classes ─────────────────────────────────────────────
# These must never be renamed or removed by R8 — they are referenced by name
# from the Flutter MethodChannel handler.
-keep class com.mazen.snote.RootDetectionHelper { *; }
-keep class com.mazen.snote.RootDetectionChannel { *; }
-keep class com.mazen.snote.MainActivity { *; }

# ── Hive ──────────────────────────────────────────────────────────────────────
-keep class com.hive.** { *; }
-keepattributes *Annotation*

# ── BouncyCastle / encrypt package ───────────────────────────────────────────
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# ── Kotlin ────────────────────────────────────────────────────────────────────
-keep class kotlin.** { *; }
-dontwarn kotlin.**
-keep class kotlinx.** { *; }
-dontwarn kotlinx.**

# ── Prevent reflection-based bypass of security checks ────────────────────────
# Obfuscate everything not explicitly kept so an attacker cannot easily locate
# and hook the root-detection methods by name.
-repackageclasses 'com.mazen.snote.obf'
-allowaccessmodification