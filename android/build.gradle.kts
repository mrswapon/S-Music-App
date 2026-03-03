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

// Fix legacy plugins: inject namespace and align JVM targets
subprojects {
    plugins.whenPluginAdded {
        if (this is com.android.build.gradle.api.AndroidBasePlugin) {
            val android = project.extensions.getByType(com.android.build.gradle.BaseExtension::class.java)

            // Inject namespace from AndroidManifest if missing
            if (android.namespace.isNullOrEmpty()) {
                val manifestFile = file("${project.projectDir}/src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val manifest = manifestFile.readText()
                    val packageMatch = Regex("""package\s*=\s*"([^"]+)"""").find(manifest)
                    if (packageMatch != null) {
                        android.namespace = packageMatch.groupValues[1]
                    }
                }
            }

            // Align Java compile options to JVM 17
            android.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }

    // Align Kotlin JVM target to 17
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
