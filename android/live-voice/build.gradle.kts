// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "app.spacenotes.live.voice"
    compileSdk = 37

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}

kotlin {
    jvmToolchain(21)
}

dependencies {
    api(project(":live-ui"))
    // LiveKit's official Android SDK (Apache 2.0), for voice. Only this module knows it.
    implementation(libs.livekit.android)

    implementation(libs.kotlinx.coroutines.android)
}
