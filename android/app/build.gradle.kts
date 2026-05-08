import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.malody_catch_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    val keyProperties = Properties()
    val keyPropertiesFile = rootProject.file("key.properties")
    val hasReleaseKeyProperties = keyPropertiesFile.exists()
    if (hasReleaseKeyProperties) {
        keyProperties.load(keyPropertiesFile.inputStream())
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.malody_catch_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        if (hasReleaseKeyProperties) {
            signingConfigs {
                create("release") {
                    storeFile = file(keyProperties["storeFile"] as String)
                    storePassword = keyProperties["storePassword"] as String
                    keyAlias = keyProperties["keyAlias"] as String
                    keyPassword = keyProperties["keyPassword"] as String
                }
            }
        }
        release {
            // Use release keystore when key.properties is configured.
            signingConfig = if (hasReleaseKeyProperties) {
                signingConfigs.getByName("release")
            } else {
                // Fallback for local non-distribution release builds.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
