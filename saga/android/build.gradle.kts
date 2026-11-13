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
// AGP 9 (Flutter 3.50) checks AAR metadata in plugin modules too, and
// flutter_plugin_android_lifecycle requires compileSdk 36 of anything that
// depends on it. Most plugins here (file_picker, share_plus, the vendored
// just_audio and audio_service, …) still say 34 or 35. compileSdk only sets the
// API stubs a module compiles against; runtime behaviour follows the app's
// targetSdk, which this doesn't touch. Raise only, never lower. Keep in step
// with flutter.compileSdkVersion.
val pluginCompileSdkFloor = 36
subprojects {
    plugins.withId("com.android.library") {
        extensions.getByType(com.android.build.api.variant.LibraryAndroidComponentsExtension::class.java)
            .finalizeDsl { android ->
                if ((android.compileSdk ?: 0) < pluginCompileSdkFloor) {
                    android.compileSdk = pluginCompileSdkFloor
                }
            }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
