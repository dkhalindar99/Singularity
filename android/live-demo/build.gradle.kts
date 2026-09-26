// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
}

// A demo app for trying SpaceNotes Live on a real Android tablet against a
// development room server (LIVE_DEV_AUTH=1). It uses dev tokens, never
// Firebase, so it must never be pointed at a real server.
android {
    namespace = "app.spacenotes.live.demo"
    compileSdk = 37

    defaultConfig {
        applicationId = "app.spacenotes.live.demo"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        // The debug build is signed with the SDK's debug key, which is what
        // lets the owner sideload the APK straight onto a tablet.
        release {
            isMinifyEnabled = false
        }
    }

    buildFeatures {
        compose = true
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
    implementation(project(":live-core"))
    implementation(project(":live-ui"))
    implementation(project(":live-voice"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.kotlinx.coroutines.android)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
}
