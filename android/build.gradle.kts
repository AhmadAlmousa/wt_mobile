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

subprojects {
    // Some plugins (flutter_secure_storage 11) hardcode `compileSdk = 37`. The
    // SDK manager installs that as `android-37.0` — Android's new
    // minor-version scheme — which Gradle's `android-37` lookup cannot
    // resolve, so the build fails before compiling anything. Pin every plugin
    // module to the SDK that is actually installed; none of them need API 37.
    //
    // This must be registered before `evaluationDependsOn` below, which
    // evaluates projects and would make `afterEvaluate` too late to hook.
    afterEvaluate {
        extensions.findByName("android")?.let { android ->
            (android as com.android.build.gradle.BaseExtension)
                .compileSdkVersion(36)
        }
    }

    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
