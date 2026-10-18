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
    project.evaluationDependsOn(":app")
}

// v22: objectbox_flutter_libs (FMTC v9's storage backend) hardcodes
// compileSdkVersion 31, but its transitive androidx deps
// (fragment 1.7.1, window 1.2.0) require compiling against 34+.
// Bumping just that module's compileSdk is safe: compileSdk only widens
// the APIs available at compile time; minSdk/targetSdk are untouched.
subprojects {
    afterEvaluate {
        if (project.name == "objectbox_flutter_libs") {
            project.extensions.findByType<com.android.build.gradle.LibraryExtension>()
                ?.compileSdk = 34
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
