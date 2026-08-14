allprojects {
    repositories {
        google()
        mavenCentral()

        // ✅ CRITICAL: flatDir repository for V2Ray AAR files
        // Note: flatDir warnings are expected and safe - required for local AAR dependencies
        @Suppress("DEPRECATION")
        flatDir {
            dirs(
                "${project.rootDir}/app/libs",
                "${project.rootDir}/../../axevpn_flutter/android/libs"
            )
        }

        // ==========================================================
        // LevelPlay mediation adapter repositories
        // Each network's native SDK is hosted on its own Maven repo;
        // mavenCentral()/google() alone don't cover these.
        // ==========================================================
        maven { url = uri("https://artifact.bytedance.com/repository/pangle") } // Pangle
        maven { url = uri("https://dl-maven-android.mintegral.com/repository/mbridge_android_sdk_oversea") } // Mintegral
        maven { url = uri("https://cboost.jfrog.io/artifactory/chartboost-ads/") } // Chartboost
        maven { url = uri("https://maven.ogury.co") } // Ogury
        maven { url = uri("https://repo.pubmatic.com/artifactory/public-repos") } // PubMatic
        maven { url = uri("https://s3.amazonaws.com/smaato-sdk-releases/") } // Smaato
        maven { url = uri("https://verve.jfrog.io/artifactory/verve-gradle-release") } // Verve
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
