package com.jackwallner.aging.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.LocalHospital
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PersonSearch
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.jackwallner.aging.model.CareState
import com.jackwallner.aging.model.DoseSlot
import com.jackwallner.aging.model.DoseStatus
import com.jackwallner.aging.model.Person
import com.jackwallner.aging.model.ScheduleEngine
import com.jackwallner.aging.ui.Format
import com.jackwallner.aging.ui.LocalGraph
import com.jackwallner.aging.ui.LocalNavigator
import com.jackwallner.aging.ui.Route
import com.jackwallner.aging.ui.theme.AgingTheme
import com.jackwallner.aging.ui.theme.Avatar
import com.jackwallner.aging.ui.theme.Card
import com.jackwallner.aging.ui.theme.EmptyNote
import com.jackwallner.aging.ui.theme.IconBadge
import com.jackwallner.aging.ui.theme.NavRow
import com.jackwallner.aging.ui.theme.RowDivider
import com.jackwallner.aging.ui.theme.ScreenTitle
import com.jackwallner.aging.ui.theme.SectionHeader
import com.jackwallner.aging.ui.theme.Spacing
import java.time.Instant

/** Port of `TodayView`: what is due for everyone, answered without opening each record. */
@Composable
fun TodayScreen() {
    val graph = LocalGraph.current
    val state = graph.care.state
    val now = Instant.now()
    val zone = Format.zone
    LazyColumn(Modifier.fillMaxSize().testTag("today.list")) {
        item { ScreenTitle("Today") }
        item {
            Text(
                now.atZone(zone).format(java.time.format.DateTimeFormatter.ofPattern("EEEE d MMMM")),
                style = MaterialTheme.typography.bodyLarge,
                color = AgingTheme.colors.secondaryText,
                modifier = Modifier.padding(horizontal = Spacing.lg),
            )
        }
        if (state.people.isEmpty()) {
            item {
                Spacer(Modifier.height(Spacing.lg))
                Card { EmptyNote("No one here yet", "Add someone on the Care tab.") }
            }
        }
        state.people.forEachIndexed { index, person ->
            item(key = person.id.toString()) {
                PersonToday(state, person, index, showHeader = state.people.size > 1, now = now) { slot, status ->
                    if (status == null) graph.care.clearDose(slot) else graph.care.recordDose(slot, status)
                }
            }
        }
        item { Spacer(Modifier.height(Spacing.xl)) }
    }
}

@Composable
private fun PersonToday(
    state: CareState,
    person: Person,
    index: Int,
    showHeader: Boolean,
    now: Instant,
    onRecord: (DoseSlot, DoseStatus?) -> Unit,
) {
    val navigator = LocalNavigator.current
    val zone = Format.zone
    val slots = ScheduleEngine.slots(state, person.id, now, zone)
    val overdue = slots.count { it.isPending && it.scheduledAt < now }
    val appointments = state.appointmentsDue(person.id, now)
    val runningLow = state.runningLow(person.id)
    val active = state.activeMedications(person.id)

    Column {
        if (showHeader) {
            Row(
                Modifier.fillMaxWidth().padding(start = Spacing.lg, end = Spacing.lg, top = Spacing.xl),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Avatar(person.displayLabel, index, size = 36)
                Spacer(Modifier.width(Spacing.md))
                Text(
                    person.displayLabel,
                    style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                    color = AgingTheme.colors.text,
                    modifier = Modifier.weight(1f),
                )
                if (overdue > 0) {
                    Text("$overdue overdue", style = MaterialTheme.typography.labelLarge, color = AgingTheme.colors.warning)
                }
            }
        }

        if (appointments.isNotEmpty()) {
            SectionHeader("Appointments")
            Card {
                appointments.forEachIndexed { i, visit ->
                    if (i > 0) RowDivider()
                    NavRow(
                        title = visit.displayTitle(),
                        detail = Format.visitDate(visit.date, visit.hasTimeOfDay(zone, now)),
                        icon = Icons.Filled.Event,
                        onClick = { navigator.push(Route.Visits(person.id)) },
                    )
                }
            }
        }

        if (runningLow.isNotEmpty()) {
            SectionHeader("Running low")
            Card {
                runningLow.forEachIndexed { i, med ->
                    if (i > 0) RowDivider()
                    NavRow(
                        title = med.displayName,
                        detail = Format.daysLeft(med.daysRemaining, med.isOutOfStock),
                        icon = Icons.Filled.Warning,
                        tint = AgingTheme.colors.warning,
                        onClick = { navigator.push(Route.MedicationEditor(person.id, med.id)) },
                    )
                }
            }
        }

        if (active.isNotEmpty()) {
            SectionHeader("Today's doses")
            Card {
                if (slots.isEmpty()) {
                    EmptyNote("Nothing scheduled today", "Everything ${person.displayLabel} takes is as-needed.")
                } else {
                    slots.forEachIndexed { i, slot ->
                        if (i > 0) RowDivider()
                        DoseRow(slot) { onRecord(slot, it) }
                    }
                }
            }
        } else {
            SectionHeader("Today's doses")
            Card {
                NavRow(
                    title = "Add ${person.displayLabel}'s medications",
                    detail = "Then mark each dose taken or skipped here.",
                    onClick = { navigator.push(Route.MedicationEditor(person.id, null)) },
                    modifier = Modifier.testTag("today.add-medication"),
                )
            }
        }

        Spacer(Modifier.height(Spacing.lg))
        Column(Modifier.padding(horizontal = Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            BigNavCard(
                title = "Emergency card",
                detail = "One page for the ER: ${person.displayLabel}'s meds, allergies and contacts. Works with no signal.",
                icon = Icons.Filled.LocalHospital,
                tint = AgingTheme.colors.danger,
                tag = "today.emergency-card",
            ) { navigator.push(Route.EmergencyCard(person.id)) }
            BigNavCard(
                title = "${person.displayLabel}'s full record",
                detail = "Medications, visits, providers and contacts.",
                icon = Icons.Filled.PersonSearch,
                tint = AgingTheme.colors.accent,
                tag = "today.full-record",
            ) { navigator.push(Route.PersonHub(person.id)) }
        }
    }
}

@Composable
private fun DoseRow(slot: DoseSlot, onRecord: (DoseStatus?) -> Unit) {
    val time = Format.time(slot.scheduledAt)
    var menuOpen by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(start = Spacing.lg, end = 4.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(slot.medicationName, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium), color = AgingTheme.colors.text)
            Text(
                if (slot.strength.isEmpty()) time else "$time · ${slot.strength}",
                style = MaterialTheme.typography.bodyMedium,
                color = AgingTheme.colors.secondaryText,
            )
        }
        val status = slot.status
        if (status == null) {
            Button(
                onClick = { onRecord(DoseStatus.TAKEN) },
                shape = RoundedCornerShape(10.dp),
                colors = ButtonDefaults.buttonColors(containerColor = AgingTheme.colors.accent),
                modifier = Modifier.heightIn(min = 44.dp).testTag("today.dose.take")
                    .semantics { contentDescription = "Mark ${slot.medicationName} at $time as taken" },
            ) { Text("Taken") }
        } else {
            Column(
                Modifier.clip(RoundedCornerShape(8.dp)).clickable { menuOpen = true }.heightIn(min = 44.dp)
                    .padding(horizontal = 10.dp, vertical = 4.dp).testTag("today.dose.status")
                    .semantics { contentDescription = "${slot.medicationName} at $time: ${status.label}. Change what was recorded" },
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    status.label,
                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                    color = if (status == DoseStatus.TAKEN) AgingTheme.colors.taken else AgingTheme.colors.secondaryText,
                )
                if (slot.recordedBy.isNotEmpty()) {
                    Text(slot.recordedBy, style = MaterialTheme.typography.bodySmall, color = AgingTheme.colors.secondaryText)
                }
            }
        }
        Box {
            IconButton(onClick = { menuOpen = true }, modifier = Modifier.testTag("today.dose.more")) {
                Icon(Icons.Filled.MoreVert, contentDescription = "More for ${slot.medicationName} at $time", tint = AgingTheme.colors.secondaryText)
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                if (status != DoseStatus.TAKEN) DropdownMenuItem(text = { Text("Taken") }, onClick = { menuOpen = false; onRecord(DoseStatus.TAKEN) })
                if (status != DoseStatus.SKIPPED) DropdownMenuItem(text = { Text("Skipped") }, onClick = { menuOpen = false; onRecord(DoseStatus.SKIPPED) })
                if (status != null) DropdownMenuItem(text = { Text("Not recorded yet") }, onClick = { menuOpen = false; onRecord(null) })
            }
        }
    }
}

@Composable
private fun BigNavCard(title: String, detail: String, icon: ImageVector, tint: Color, tag: String, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(AgingTheme.colors.card)
            .clickable(onClick = onClick)
            .testTag(tag)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconBadge(icon, tint, size = 44)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = AgingTheme.colors.text)
            Text(detail, style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.secondaryText)
        }
    }
}
