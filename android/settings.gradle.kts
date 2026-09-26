// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

// SpaceNotes Live for Android. Its own Gradle build so it can be developed and
// tested alone; the notebook app includes these modules when it embeds a room
// (see README.md). Versions follow the notebook's own catalogue so both builds
// resolve the same Kotlin, Compose and serialization.
pluginManagement {
    repositories {
        google {
            content {
                includeGroupAndSubgroups("androidx")
                includeGroupAndSubgroups("com.android")
                includeGroupAndSubgroups("com.google")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google {
            content {
                includeGroupAndSubgroups("androidx")
                includeGroupAndSubgroups("com.android")
                includeGroupAndSubgroups("com.google")
            }
        }
        mavenCentral()
        // LiveKit's Android SDK depends on its own fork of Twilio's audioswitch,
        // published only on JitPack (LiveKit's install guide says to add it).
        // Limited to that one group so nothing else resolves from there.
        maven("https://jitpack.io") {
            content { includeGroup("com.github.davidliu") }
        }
    }
}

rootProject.name = "spacenotes-live-android"

// Plain JVM: protocol, reducer, permissions, room client and HTTP client.
include(":live-core")
// The room screen, in Compose. Knows nothing about LiveKit.
include(":live-ui")
// Camera and voice tiles through LiveKit.
include(":live-video")
