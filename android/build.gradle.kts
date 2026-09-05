allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Third-party plugins pin their own compileSdk/build-tools — permission_handler
// asks for 35. The CI image ships exactly build-tools 36.0.0 and platforms
// android-36, and its /opt/android-sdk is read-only, so every such plugin would
// make Gradle try to install a component and fail with "The SDK directory is
// not writable". Pull them all up to what the image has.
//
// This must stay ABOVE the evaluationDependsOn block below: that one forces
// evaluation, and registering afterEvaluate afterwards throws
// "Cannot run Project.afterEvaluate(Action) when the project is already
// evaluated".
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            val android = ext as com.android.build.gradle.BaseExtension
            android.compileSdkVersion(36)
            android.buildToolsVersion = "36.0.0"
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
