plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    buildFeatures {
        resValues = true
    }
    namespace = "uz.savdoyordam.savdoyordam"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "uz.savdoyordam.savdoyordam"
        // Public Firebase app configuration; server credentials never enter the APK.
        resValue("string", "savdo_firebase_project", System.getenv("FIREBASE_PROJECT_ID") ?: "")
        resValue("string", "savdo_firebase_app", System.getenv("FIREBASE_APP_ID") ?: "")
        resValue("string", "savdo_firebase_key", System.getenv("FIREBASE_API_KEY") ?: "")
        resValue("string", "savdo_firebase_sender", System.getenv("FIREBASE_SENDER_ID") ?: "")
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release signing is configured by the operator; never reuse debug keys.
            signingConfig = null
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:35.1.0"))
    implementation("com.google.firebase:firebase-messaging")
}
