import java.util.Properties
import java.io.FileInputStream
import java.security.MessageDigest
import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:34.7.0"))


    // TODO: Add the dependencies for Firebase products you want to use
    // When using the BoM, don't specify versions in Firebase dependencies
    implementation("com.google.firebase:firebase-analytics")


    // Add the dependencies for any other desired Firebase products
    // https://firebase.google.com/docs/android/setup#available-libraries
}

// ---- Release signing (reads android/key.properties) ----
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "moe.herz.verhaaarm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "moe.herz.verhaaarm"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only created if key.properties exists; otherwise builds still work (debug signing).
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            // 2) Install alongside release + different launcher name
            applicationIdSuffix = ".debug"
            resValue("string", "app_name", "Verhåårm-Debug")
        }

        release {
            // 3) Use your release keystore if configured, else fall back to debug signing
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

// ---- 1) Rename the APK files after Flutter/Gradle builds them ----
// Result (in build/app/outputs/flutter-apk/):
//   verhaarm-release-<version>.apk
//   verhaarm-debug-release-<version>.apk
afterEvaluate {
    val vName = android.defaultConfig.versionName ?: "0.0.0"
    val vCode = android.defaultConfig.versionCode ?: 0
    val vFull = "$vName+$vCode"

    fun writeSha1(file: File) {
        val digest = MessageDigest.getInstance("SHA-1")
        file.inputStream().use { input ->
            val buf = ByteArray(1024 * 1024)
            while (true) {
                val r = input.read(buf)
                if (r <= 0) break
                digest.update(buf, 0, r)
            }
        }

        val bytes = digest.digest()
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            sb.append(String.format("%02x", b))
        }
        File(file.parentFile, "${file.name}.sha1").writeText(sb.toString() + "\n")
    }

    val renameReleaseApk = tasks.register("renameReleaseApk") {
        dependsOn("assembleRelease")
        doLast {
            val dir = layout.buildDirectory.dir("outputs/flutter-apk").get().asFile

            val src = File(dir, "app-release.apk")
            if (src.exists()) {
                val dst = File(dir, "verhaarm-release-$vFull.apk")
                src.copyTo(dst, overwrite = true)
                writeSha1(dst)
            }
        }
    }

    val renameDebugApk = tasks.register("renameDebugApk") {
        dependsOn("assembleDebug")
        doLast {
            val dir = layout.buildDirectory.dir("outputs/flutter-apk").get().asFile

            val src = File(dir, "app-debug.apk")
            if (src.exists()) {
                val dst = File(dir, "verhaarm-debug-release-$vFull.apk")
                src.copyTo(dst, overwrite = true)
                writeSha1(dst)
            }
        }
    }

    tasks.named("assembleRelease") { finalizedBy(renameReleaseApk) }
    tasks.named("assembleDebug") { finalizedBy(renameDebugApk) }
}


