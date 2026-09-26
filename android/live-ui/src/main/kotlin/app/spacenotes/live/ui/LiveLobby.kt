// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

package app.spacenotes.live.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.spacenotes.live.core.CreatedRoom
import app.spacenotes.live.core.LiveApi
import app.spacenotes.live.core.RoomLookup
import kotlinx.coroutines.launch

/** The characters a room code can contain (no 0, O, 1 or I). */
public const val ROOM_CODE_ALPHABET: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

/** Tidies what someone typed into a room code: upper case, known characters, six at most. */
public fun cleanRoomCode(typed: String): String =
    typed.uppercase().filter { it in ROOM_CODE_ALPHABET }.take(6)

/**
 * Before a session: join a friend's room by its code, or host this notebook.
 *
 * [source] is the notebook the host app is showing; without one, only joining
 * is offered. [onJoin] gets the room found for a code; [onHosted] the room
 * just created. The app then shows [LiveRoomScreen] for it.
 */
@Composable
public fun LiveLobby(
    api: LiveApi,
    source: LiveNotebookSource?,
    onJoin: (RoomLookup) -> Unit,
    onHosted: (CreatedRoom) -> Unit,
    modifier: Modifier = Modifier,
    theme: LiveTheme = LiveTheme.Light,
    initialCode: String = "",
) {
    CompositionLocalProvider(LocalLiveTheme provides theme) {
        val scope = rememberCoroutineScope()
        var code by remember { mutableStateOf(cleanRoomCode(initialCode)) }
        var found by remember { mutableStateOf<RoomLookup?>(null) }
        var busy by remember { mutableStateOf(false) }
        var error by remember { mutableStateOf<String?>(null) }
        var allowGuests by remember { mutableStateOf(true) }

        Surface(modifier.fillMaxSize(), color = theme.background) {
            Column(
                Modifier.padding(24.dp).widthIn(max = 480.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("SpaceNotes Live", color = theme.onSurface, fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
                Text("Study together on one notebook: everyone sees the ink as it is drawn.", color = theme.onSurfaceMuted)

                Spacer(Modifier.height(8.dp))
                Text("Join a room", color = theme.onSurface, fontWeight = FontWeight.Medium)
                OutlinedTextField(
                    value = code,
                    onValueChange = {
                        code = cleanRoomCode(it)
                        found = null
                        error = null
                    },
                    label = { Text("Room code") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                    modifier = Modifier.fillMaxWidth(),
                )
                val room = found
                if (room == null) {
                    Button(
                        onClick = {
                            busy = true
                            error = null
                            scope.launch {
                                try {
                                    val result = api.lookup(code)
                                    if (result == null) error = "No room has that code." else found = result
                                } catch (e: Exception) {
                                    error = "Could not reach SpaceNotes Live. Check the connection and try again."
                                } finally {
                                    busy = false
                                }
                            }
                        },
                        enabled = code.length == 6 && !busy,
                        colors = ButtonDefaults.buttonColors(containerColor = theme.accent, contentColor = theme.onAccent),
                    ) { Text("Find room") }
                } else {
                    Text(
                        "${room.title}" + if (room.hostName.isNotEmpty()) " — hosted by ${room.hostName}" else "",
                        color = theme.onSurface,
                    )
                    Button(
                        onClick = { onJoin(room) },
                        colors = ButtonDefaults.buttonColors(containerColor = theme.accent, contentColor = theme.onAccent),
                    ) { Text("Join") }
                }

                if (source != null) {
                    HorizontalDivider(Modifier.padding(vertical = 8.dp), color = theme.surfaceVariant)
                    Text("Host this notebook", color = theme.onSurface, fontWeight = FontWeight.Medium)
                    Text(source.title, color = theme.onSurfaceMuted)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Let people join without an account", color = theme.onSurface, modifier = Modifier.weight(1f))
                        Switch(checked = allowGuests, onCheckedChange = { allowGuests = it })
                    }
                    OutlinedButton(
                        onClick = {
                            busy = true
                            error = null
                            scope.launch {
                                try {
                                    onHosted(api.hostRoom(source, allowGuests))
                                } catch (e: Exception) {
                                    error = "Could not start the room. Check the connection and try again."
                                } finally {
                                    busy = false
                                }
                            }
                        },
                        enabled = !busy,
                    ) { Text("Start a room") }
                }

                error?.let { Text(it, color = theme.danger) }
            }
        }
    }
}
