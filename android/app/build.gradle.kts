plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace  = "com.mazen.snote"
    compileSdk = 35
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.mazen.snote"
        minSdk = flutter.minSdkVersion
        targetSdk     = 35
        versionCode   = flutter.versionCode
        versionName   = flutter.versionName
    }

    buildTypes {
        debug {
            // Keep debug builds debuggable but do NOT disable security checks —
            // root detection runs in every build type.
            isDebuggable     = true
            isMinifyEnabled  = false
            isShrinkResources = false
        }
        release {
            isDebuggable      = false
            isMinifyEnabled   = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Prevent the APK from being backed up — backup could expose Hive data
    // or secure-storage entries on a compromised device.
    defaultConfig {
        manifestPlaceholders["allowBackup"] = "false"
    }
}

flutter {
    source = "../.."
}
