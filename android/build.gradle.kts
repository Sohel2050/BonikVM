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
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()

rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects { project.evaluationDependsOn(":app") }

tasks.register<Delete>("clean") { delete(rootProject.layout.buildDirectory) }
