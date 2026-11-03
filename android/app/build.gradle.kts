import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = providers.gradleProperty("briskaSigningPropertiesFile")
    .map { rootProject.file(it) }
    .getOrElse(rootProject.file("key.properties"))
val keystoreProperties = Properties()
if (keystorePropertiesFile.isFile) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val releaseSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasReleaseSigningProperties = keystorePropertiesFile.isFile &&
    releaseSigningKeys.all { !keystoreProperties.getProperty(it).isNullOrBlank() }
val releaseKeystoreFile = keystoreProperties.getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }
    ?.let { project.file(it) }
val hasValidReleaseSigning = hasReleaseSigningProperties &&
    releaseKeystoreFile?.isFile == true
val releaseBuildRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.substringAfterLast(':').contains("release", ignoreCase = true)
}

if (releaseBuildRequested && !hasValidReleaseSigning) {
    throw GradleException(
        "Briska Pay release signing is not configured. Check android/key.properties and the upload keystore.",
    )
}

android {
    namespace = "com.berkzerker.briska"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.berkzerker.briska"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasValidReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = releaseKeystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasValidReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
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
    // Google Mobile Ads currently brings WorkManager 2.7.0 transitively.
    // Use the current runtime so AndroidX Startup can initialize safely on
    // current Android releases before Flutter's MainActivity is created.
    implementation("androidx.work:work-runtime:2.11.2")
}
