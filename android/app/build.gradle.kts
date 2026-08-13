import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

android {
    namespace = "com.albonik.vpn"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    // Enable 16KB page size support for Android 15+
    experimentalProperties["android.experimental.enable16KPageSize"] = true

    // Disable art profile to avoid AAR extraction path length issues on Windows
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // ✅ CRITICAL: Include shared certificate assets for Play Store compatibility
    sourceSets {
        named("main") {
            assets.srcDirs("../../../assets") // Link to Flutter assets
            res.srcDirs("../../../assets/certs") // Fallback for Play Store
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.albonik.vpn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24  // Minimum SDK for OpenVPN
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ✅ CRITICAL: Support arm64-v8a and x86_64 with 16 KB page size
        ndk {
            abiFilters.clear()
            abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
        }

        // ✅ CRITICAL: NDK build flags for 16 KB page size support
        externalNativeBuild {
            cmake {
                cppFlags += listOf("-Wl,-z,max-page-size=16384")
                arguments += listOf("-DANDROID_MAX_PAGE_SIZE=16384")
            }
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists() &&
            keystoreProperties.containsKey("keyAlias") &&
            keystoreProperties.containsKey("keyPassword") &&
            keystoreProperties.containsKey("storeFile") &&
            keystoreProperties.containsKey("storePassword")) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Only use release signing if configured
            if (keystorePropertiesFile.exists() && signingConfigs.findByName("release") != null) {
                signingConfig = signingConfigs.getByName("release")
            }

            // ✅ CRITICAL: Enable shrinking and obfuscation for release
            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }

        debug {
            // ✅ CRITICAL: Debug configuration
        }
    }

    // ✅ CRITICAL: OpenVPN Flutter plugin requirements for Play Store
    lint {
        disable += setOf("InvalidPackage")
        checkReleaseBuilds = false
        abortOnError = false
    }

    // ✅ CRITICAL: OpenVPN native library packaging with 16 KB support
    packaging {
        jniLibs {
            useLegacyPackaging = true

            // ✅ INCLUDE ALL OpenVPN 16 KB libraries from plugin
            // ❌ EXCLUDE old non-16KB libraries (removed from plugin repo)

            // Exclude old non-16KB libraries (prevent inclusion from any source)
            excludes += setOf(
                "**/libgojni.so",
                "**/libjbcrypto.so",
                "**/libnative-lib.so"
                // libopvpnutil.so is REQUIRED by NativeUtils JNI - do NOT exclude
            )

            // Pick first for 16 KB compatible libraries from plugin
            pickFirsts += setOf(
                "**/libopenvpn.so",
                "**/libovpnexec.so",
                "**/libovpnutil.so",     // 16KB version from plugin
                "**/libopvpnutil.so",    // 16KB version - required by NativeUtils
                "**/libosslspeedtest.so",
                "**/libosslutil.so",
                "**/libovpn3.so",
                "**/libc++_shared.so",
                "**/libjsc.so",
                "**/libc++.so",
                // WireGuard: prefer jniLibs (16KB) over Maven tunnel .so
                "**/libwg-go.so",
                "**/libwg.so",
                "**/libwg-quick.so"
            )
        }

        resources {
            excludes += setOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/license.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/notice.txt",
                "META-INF/ASL2.0",
                "**/kotlin/**",
                "**/*.kotlin_metadata"
            )
        }
    }

    // ✅ CRITICAL: App Bundle configuration
    bundle {
        language {
            enableSplit = false
        }
        density {
            enableSplit = false
        }
        abi {
            enableSplit = false  // Keep all ABIs together to avoid library conflicts
        }
    }

    buildFeatures {
        buildConfig = true
    }

    // ✅ CRITICAL: Ensure jniLibs directory is included
    sourceSets {
        named("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
}

dependencies {
    val multidexVersion = "2.0.1"
    implementation("androidx.multidex:multidex:$multidexVersion")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}




