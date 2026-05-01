# Flutter wrapper
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Hive
-keep class com.hive.** { *; }
-keepattributes *Annotation*

# PointyCastle / encrypt
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**