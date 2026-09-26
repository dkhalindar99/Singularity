// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

// No Android dependency on purpose: everything that decides what the shared
// notebook looks like runs in a plain JVM test against the protocol fixtures.
dependencies {
    api(libs.kotlinx.serialization.json)
    api(libs.kotlinx.coroutines.core)
    api(libs.okhttp)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}

kotlin {
    jvmToolchain(21)
    explicitApi()
}

val protocolFixtures: Directory = rootProject.layout.projectDirectory.dir("../fixtures/protocol")

tasks.withType<Test>().configureEach {
    // The fixtures are the contract shared with the server, web and iPad; the
    // tests read the repository's copy so they can never drift from it.
    systemProperty("spacenotes.live.fixtures", protocolFixtures.asFile.absolutePath)
    inputs.dir(protocolFixtures)
        .withPropertyName("protocolFixtures")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    // LiveServerTest runs only when this names a local dev server.
    inputs.property("liveServer", providers.environmentVariable("LIVE_SERVER_URL").orElse(""))
    testLogging {
        events("failed", "skipped")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
