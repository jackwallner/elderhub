package com.jackwallner.aging.ui.screens

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityCompat
import com.jackwallner.aging.model.Person
import com.jackwallner.aging.ui.LocalGraph
import com.jackwallner.aging.ui.theme.AgingTheme
import com.jackwallner.aging.ui.theme.Card
import com.jackwallner.aging.ui.theme.SectionHeader
import com.jackwallner.aging.ui.theme.Spacing
import com.jackwallner.aging.ui.theme.ToggleRow

/**
 * The person hub's reminder switch (`NotificationPermission.swift`): asks for
 * the notification permission when needed, and when Android has blocked it,
 * says so with a way to Settings instead of silently flipping back.
 */
@Composable
fun ReminderCard(person: Person) {
    val graph = LocalGraph.current
    val context = LocalContext.current
    val reminders = graph.reminders
    var enabled by remember(person.id) { mutableStateOf(reminders.preferences.isEnabled(person.id) && reminders.canPost()) }
    var blocked by remember { mutableStateOf(false) }

    fun set(on: Boolean) {
        reminders.preferences.setEnabled(person.id, on)
        enabled = on
        reminders.refresh()
    }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) {
            set(true)
        } else {
            set(false)
            val activity = context as? Activity
            // No rationale after a denial means Android will not ask again: only Settings can fix it.
            if (activity != null && !ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.POST_NOTIFICATIONS)) {
                blocked = true
            }
        }
    }

    SectionHeader("Reminders")
    Card {
        ToggleRow("Dose reminders", null, enabled, tag = "hub.reminders") { on ->
            when {
                !on -> set(false)
                reminders.canPost() -> set(true)
                Build.VERSION.SDK_INT >= 33 -> permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                else -> blocked = true
            }
        }
    }
    Text(
        "Notifies this phone at each scheduled dose time for ${person.displayLabel}. Reminders are set on each device separately.",
        style = MaterialTheme.typography.bodySmall,
        color = AgingTheme.colors.secondaryText,
        modifier = Modifier.padding(horizontal = Spacing.lg + 4.dp, vertical = Spacing.sm),
    )

    if (blocked) {
        AlertDialog(
            onDismissRequest = { blocked = false },
            title = { Text("Reminders are off for Elderhub") },
            text = {
                Text("Android is blocking notifications for this app, so reminders can't be delivered. Turn on notifications for Elderhub in Settings, then switch reminders back on here.")
            },
            confirmButton = {
                TextButton(onClick = {
                    blocked = false
                    context.startActivity(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName),
                    )
                }) { Text("Open Settings") }
            },
            dismissButton = { TextButton(onClick = { blocked = false }) { Text("Not now") } },
        )
    }
}
