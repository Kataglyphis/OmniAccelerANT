allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Single source of truth for the SDK components the CI image ships
// (/opt/android-sdk is read-only, so anything else makes Gradle try to install
// and fail). Modules read these instead of repeating literals, and the
// subprojects override below covers third-party plugins - AGENTS.md § 4.
extra["kataglyphisCompileSdk"] = 36
extra["kataglyphisBuildTools"] = "36.0.0"
extra["kataglyphisNdk"] = "29.0.14206865"
extra["kataglyphisCmake"] = "4.1.2"

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Must stay above evaluationDependsOn — AGENTS.md § 4.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            val android = ext as com.android.build.gradle.BaseExtension
            android.compileSdkVersion(rootProject.extra["kataglyphisCompileSdk"] as Int)
            android.buildToolsVersion = rootProject.extra["kataglyphisBuildTools"] as String
            android.ndkVersion = rootProject.extra["kataglyphisNdk"] as String
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
