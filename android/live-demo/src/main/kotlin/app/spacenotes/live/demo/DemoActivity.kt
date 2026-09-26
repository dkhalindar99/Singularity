// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.demo

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.edit
import app.spacenotes.live.core.LiveApi
import app.spacenotes.live.core.PageBackground
import app.spacenotes.live.ui.LiveLobby
import app.spacenotes.live.ui.LiveNotebookSource
import app.spacenotes.live.ui.LiveRoomScreen
import app.spacenotes.live.ui.LiveSourcePage
import app.spacenotes.live.ui.rememberRoomClient
import app.spacenotes.live.voice.LiveKitVoiceProvider
import java.util.UUID

/**
 * SpaceNotes Live Demo: server address and name, then the lobby, then the
 * room. It signs in with dev tokens (`dev:<uid>:<name>`), which only a server
 * started with LIVE_DEV_AUTH=1 accepts; there is no Firebase here.
 */
class DemoActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize()) {
                    Box(Modifier.safeDrawingPadding()) { DemoApp() }
                }
            }
        }
    }
}

/** What the demo remembers between launches. */
private class DemoSettings(context: Context) {
    private val prefs = context.getSharedPreferences("spacenotes-live-demo", Context.MODE_PRIVATE)

    var serverUrl: String
        get() = prefs.getString("serverUrl", null) ?: "http://192.168.1.10:8080"
        set(value) = prefs.edit { putString("serverUrl", value) }

    var name: String
        get() = prefs.getString("name", null) ?: ""
        set(value) = prefs.edit { putString("name", value) }

    /** One uid per install, so the server knows this tablet across launches. */
    val uid: String
        get() = prefs.getString("uid", null) ?: ("android-" + UUID.randomUUID().toString().take(12)).also {
            prefs.edit { putString("uid", it) }
        }

    val deviceId: String get() = "demo-$uid"
}

/** A dev token's name may not contain ':' and is at most 60 characters. */
private fun tokenName(name: String): String = name.replace(":", " ").trim().take(60).ifEmpty { "Guest" }

private sealed interface Screen {
    data object Setup : Screen
    data object Lobby : Screen
    data class Room(val roomId: String) : Screen
}

@Composable
private fun DemoApp() {
    val context = LocalContext.current
    val settings = remember { DemoSettings(context.applicationContext) }
    var screen by remember { mutableStateOf<Screen>(Screen.Setup) }
    var serverUrl by rememberSaveable { mutableStateOf(settings.serverUrl) }
    var name by rememberSaveable { mutableStateOf(settings.name) }
    var notice by remember { mutableStateOf<String?>(null) }

    val token: suspend () -> String = { "dev:${settings.uid}:${tokenName(name)}" }
    val api = remember(serverUrl, name) { LiveApi(serverUrl, token) }

    when (val current = screen) {
        Screen.Setup -> SetupScreen(
            serverUrl = serverUrl,
            name = name,
            notice = notice,
            onServerUrl = { serverUrl = it },
            onName = { name = it },
            onContinue = {
                serverUrl = serverUrl.trim().trimEnd('/')
                settings.serverUrl = serverUrl
                settings.name = name.trim()
                notice = null
                screen = Screen.Lobby
            },
        )
        Screen.Lobby -> {
            BackHandler { screen = Screen.Setup }
            LiveLobby(
                api = api,
                source = remember { BlankLinedNotebook(3) },
                onJoin = { screen = Screen.Room(it.roomId) },
                onHosted = { screen = Screen.Room(it.roomId) },
            )
        }
        is Screen.Room -> {
            val client = rememberRoomClient(serverUrl, current.roomId, tokenName(name), settings.deviceId, token)
            val voice = remember(current.roomId) { LiveKitVoiceProvider(context) }
            BackHandler { client.disconnect() }
            // Voice joins when the server issues a ticket; without LiveKit
            // keys it answers 503 and the room carries on with ink only.
            LiveRoomScreen(
                client = client,
                api = api,
                voiceProvider = voice,
                onSessionEnded = { result ->
                    notice = "Session over (${result.reason})."
                    screen = Screen.Lobby
                },
            )
        }
    }
}

@Composable
private fun SetupScreen(
    serverUrl: String,
    name: String,
    notice: String?,
    onServerUrl: (String) -> Unit,
    onName: (String) -> Unit,
    onContinue: () -> Unit,
) {
    Column(
        Modifier.padding(24.dp).widthIn(max = 480.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("SpaceNotes Live Demo", fontSize = 24.sp)
        Text("For trying SpaceNotes Live against a development server on your Wi-Fi.")
        OutlinedTextField(
            value = serverUrl,
            onValueChange = onServerUrl,
            label = { Text("Server address") },
            placeholder = { Text("http://192.168.1.10:8080") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = name,
            onValueChange = onName,
            label = { Text("Your name") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        notice?.let { Text(it) }
        Button(
            onClick = onContinue,
            enabled = name.isNotBlank() && (serverUrl.startsWith("http://") || serverUrl.startsWith("https://")),
        ) { Text("Continue") }
    }
}

/** The notebook a demo host shares: blank A4 pages with lines. */
private class BlankLinedNotebook(private val count: Int) : LiveNotebookSource {
    override val title: String = "SpaceNotes Live demo"

    override suspend fun pages(): List<LiveSourcePage> = List(count) {
        LiveSourcePage(
            id = UUID.randomUUID().toString().uppercase(),
            width = 595.0,
            height = 842.0,
            background = PageBackground.template("lined"),
        )
    }
}
