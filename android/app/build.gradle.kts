plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.kataglyphis_inference_engine"
    // compileSdk = flutter.compileSdkVersion
    // ndkVersion = flutter.ndkVersion
    // These three must name components the CI image actually ships
    // (/opt/android-sdk: build-tools 36.0.0, platforms android-36,
    // ndk 29.0.14206865). The SDK directory is read-only there, so anything
    // else makes Gradle try to install it and fail with
    // "The SDK directory is not writable (/opt/android-sdk)".
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_21.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.kataglyphis_inference_engine"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // my native_code_plugin requires minSdkVersion 26.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    jvmToolchain(21)
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.3")
}
