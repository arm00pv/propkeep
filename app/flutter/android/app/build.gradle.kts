plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.propkeep.propkeep"
    compileSdk = 36  // Android 16 (latest available SDK)

    defaultConfig {
        applicationId = "com.propkeep.propkeep"
        minSdk = 34     // Android 14 (3 versions back: 14, 15, 16)
        targetSdk = 36  // Android 16
        versionCode = 2
        versionName = "1.2.0"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}
