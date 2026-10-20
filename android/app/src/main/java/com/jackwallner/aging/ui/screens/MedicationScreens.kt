package com.jackwallner.aging.ui.screens

import android.app.TimePickerDialog
import android.text.format.DateFormat
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Medication
import androidx.compose.material3.AssistChip
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.jackwallner.aging.model.Medication
import com.jackwallner.aging.model.MedicationForm
import com.jackwallner.aging.model.ScheduleEngine
import com.jackwallner.aging.ui.Format
import com.jackwallner.aging.ui.LocalGraph
import com.jackwallner.aging.ui.LocalNavigator
import com.jackwallner.aging.ui.Route
import com.jackwallner.aging.ui.theme.AgingTheme
import com.jackwallner.aging.ui.theme.Card
import com.jackwallner.aging.ui.theme.ConfirmDelete
import com.jackwallner.aging.ui.theme.DetailTopBar
import com.jackwallner.aging.ui.theme.EditorScaffold
import com.jackwallner.aging.ui.theme.EmptyNote
import com.jackwallner.aging.ui.theme.FormField
import com.jackwallner.aging.ui.theme.NavRow
import com.jackwallner.aging.ui.theme.RowDivider
import com.jackwallner.aging.ui.theme.SectionHeader
import com.jackwallner.aging.ui.theme.Spacing
import com.jackwallner.aging.ui.theme.ToggleRow
import java.time.Instant
import java.util.UUID

@Composable
fun MedicationsScreen(personId: UUID) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val state = graph.care.state
    val person = state.person(personId) ?: return
    val active = state.activeMedications(personId)
    val stopped = state.stoppedMedications(personId)
    Column(Modifier.fillMaxSize()) {
        DetailTopBar("Medications", onBack = navigator::pop) {
            IconButton(onClick = { navigator.push(Route.MedicationEditor(personId, null)) }, modifier = Modifier.testTag("medications.add")) {
                Icon(Icons.Filled.Add, contentDescription = "Add medication")
            }
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            SectionHeader("Taking now")
            Card {
                if (active.isEmpty()) {
                    EmptyNote("No medications yet", "Add what ${person.displayLabel} takes, with the times, and mark each dose from Today.")
                }
                active.forEachIndexed { i, med ->
                    if (i > 0) RowDivider()
                    NavRow(
                        title = med.displayName,
                        detail = medDetail(med),
                        icon = Icons.Filled.Medication,
                        onClick = { navigator.push(Route.MedicationEditor(personId, med.id)) },
                    )
                }
            }
            if (stopped.isNotEmpty()) {
                SectionHeader("Stopped")
                Card {
                    stopped.forEachIndexed { i, med ->
                        if (i > 0) RowDivider()
                        NavRow(
                            title = med.displayName,
                            detail = med.endDate?.let { "Stopped ${Format.date(it)}" } ?: "Stopped",
                            onClick = { navigator.push(Route.MedicationEditor(personId, med.id)) },
                        )
                    }
                }
            }
            Spacer(Modifier.height(Spacing.xl))
        }
    }
}

private fun medDetail(med: Medication): String {
    val schedule = when {
        med.isAsNeeded -> "As needed"
        med.scheduleMinutes.isEmpty() -> "No times set"
        else -> med.scheduleLabel()
    }
    val refill = if (med.tracksRefills) " · ${Format.daysLeft(med.daysRemaining, med.isOutOfStock)}" else ""
    return schedule + refill
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MedicationEditorScreen(personId: UUID, medicationId: UUID?) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]
    val state = graph.care.state
    val existing = medicationId?.let { id -> state.medications.firstOrNull { it.id == id } }
    var name by remember { mutableStateOf(existing?.name.orEmpty()) }
    var strength by remember { mutableStateOf(existing?.strength.orEmpty()) }
    var form by remember { mutableStateOf(existing?.form ?: MedicationForm.TABLET) }
    var purpose by remember { mutableStateOf(existing?.purpose.orEmpty()) }
    var instructions by remember { mutableStateOf(existing?.instructions.orEmpty()) }
    var asNeeded by remember { mutableStateOf(existing?.isAsNeeded ?: false) }
    var times by remember { mutableStateOf(existing?.scheduleMinutes?.sorted() ?: listOf(8 * 60)) }
    var weekdays by remember { mutableStateOf(existing?.weekdays.orEmpty()) }
    var tracks by remember { mutableStateOf(existing?.tracksRefills ?: false) }
    var quantity by remember { mutableStateOf(existing?.quantityRemaining?.let(::trimNumber) ?: "") }
    var perDose by remember { mutableStateOf(existing?.unitsPerDose?.let(::trimNumber) ?: "1") }
    var prescriber by remember { mutableStateOf(existing?.prescriber.orEmpty()) }
    var pharmacy by remember { mutableStateOf(existing?.pharmacy.orEmpty()) }
    var formMenu by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    fun save() {
        val base = existing ?: Medication(personId = personId, startDate = Instant.now())
        graph.care.upsertMedication(
            base.copy(
                name = name.trim(), strength = strength.trim(), form = form, purpose = purpose.trim(),
                instructions = instructions.trim(), isAsNeeded = asNeeded, scheduleMinutes = times.distinct().sorted(),
                weekdays = if (weekdays.size == 7) emptyList() else weekdays.sorted(), tracksRefills = tracks,
                quantityRemaining = quantity.toDoubleOrNull() ?: 0.0, unitsPerDose = perDose.toDoubleOrNull()?.takeIf { it > 0 } ?: 1.0,
                prescriber = prescriber.trim(), pharmacy = pharmacy.trim(),
            ),
        )
        navigator.pop()
    }

    fun pickTime(initial: Int, onPicked: (Int) -> Unit) {
        TimePickerDialog(context, { _, h, m -> onPicked(h * 60 + m) }, initial / 60, initial % 60, DateFormat.is24HourFormat(context)).show()
    }

    EditorScaffold(
        title = if (existing == null) "Add Medication" else "Edit Medication",
        canSave = name.isNotBlank(),
        onBack = navigator::pop,
        onSave = ::save,
    ) {
        SectionHeader("Medication")
        FormField("Name", name, { name = it }, tag = "med.name", capitalization = KeyboardCapitalization.Words)
        FormField("Strength (e.g. 10 mg)", strength, { strength = it }, tag = "med.strength")
        Row(Modifier.padding(horizontal = Spacing.lg, vertical = 4.dp)) {
            AssistChip(onClick = { formMenu = true }, label = { Text("Form: ${form.label}") })
            DropdownMenu(expanded = formMenu, onDismissRequest = { formMenu = false }) {
                MedicationForm.entries.forEach { option ->
                    DropdownMenuItem(text = { Text(option.label) }, onClick = { form = option; formMenu = false })
                }
            }
        }
        FormField("What it's for", purpose, { purpose = it })
        FormField("Instructions (e.g. take with food)", instructions, { instructions = it })

        SectionHeader("Schedule")
        Card {
            ToggleRow("As needed", "Not on a schedule, so it never appears on Today.", asNeeded, tag = "med.as-needed") { asNeeded = it }
        }
        if (!asNeeded) {
            Spacer(Modifier.height(Spacing.sm))
            FlowRow(Modifier.padding(horizontal = Spacing.lg), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                times.sorted().forEach { minutes ->
                    InputChip(
                        selected = false,
                        onClick = { pickTime(minutes) { picked -> times = (times - minutes + picked).distinct().sorted() } },
                        label = { Text(ScheduleEngine.timeLabel(minutes)) },
                        trailingIcon = {
                            Icon(
                                Icons.Filled.Close, contentDescription = "Remove ${ScheduleEngine.timeLabel(minutes)}",
                                modifier = Modifier.clickable { times = times - minutes },
                            )
                        },
                    )
                }
                TextButton(onClick = { pickTime(times.maxOrNull()?.let { minOf(it + 4 * 60, 23 * 60) } ?: 8 * 60) { times = (times + it).distinct().sorted() } }, modifier = Modifier.testTag("med.add-time")) {
                    Text("Add a time")
                }
            }
            Text(
                "Days",
                style = MaterialTheme.typography.titleSmall,
                color = AgingTheme.colors.secondaryText,
                modifier = Modifier.padding(start = Spacing.lg, top = Spacing.md),
            )
            FlowRow(Modifier.padding(horizontal = Spacing.lg), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                ScheduleEngine.orderedWeekdays(locale).forEach { day ->
                    val everyDay = weekdays.isEmpty()
                    val on = everyDay || day in weekdays
                    FilterChip(
                        selected = on,
                        onClick = {
                            val current = if (everyDay) (1..7).toList() else weekdays
                            val next = if (day in current) current - day else current + day
                            if (next.isNotEmpty()) weekdays = if (next.size == 7) emptyList() else next
                        },
                        label = { Text(ScheduleEngine.dayOfWeek(day).getDisplayName(java.time.format.TextStyle.SHORT, locale)) },
                        colors = FilterChipDefaults.filterChipColors(selectedContainerColor = AgingTheme.colors.accent.copy(alpha = 0.18f)),
                    )
                }
            }
            Text(
                ScheduleEngine.weekdayLabel(weekdays, locale).ifEmpty { "Every day" },
                style = MaterialTheme.typography.bodySmall,
                color = AgingTheme.colors.secondaryText,
                modifier = Modifier.padding(horizontal = Spacing.lg),
            )
        }

        SectionHeader("Refills")
        Card {
            ToggleRow("Track what's left", "Counts down as doses are marked taken.", tracks, tag = "med.tracks") { tracks = it }
        }
        if (tracks) {
            FormField("On hand", quantity, { quantity = it }, keyboardType = KeyboardType.Decimal, tag = "med.quantity")
            FormField("Per dose", perDose, { perDose = it }, keyboardType = KeyboardType.Decimal)
        }

        SectionHeader("Who prescribes and fills it")
        FormField("Prescriber", prescriber, { prescriber = it }, capitalization = KeyboardCapitalization.Words)
        FormField("Pharmacy", pharmacy, { pharmacy = it }, capitalization = KeyboardCapitalization.Words)

        if (existing != null) {
            Spacer(Modifier.height(Spacing.lg))
            Card {
                if (existing.isActive) {
                    NavRow("Stop taking", "Comes off Today and the card, keeps its history.", onClick = {
                        graph.care.upsertMedication(existing.stopped()); navigator.pop()
                    }, modifier = Modifier.testTag("med.stop"))
                } else {
                    NavRow("Start again", "Back on Today and the card.", onClick = {
                        graph.care.upsertMedication(existing.restarted()); navigator.pop()
                    })
                }
                RowDivider()
                NavRow("Delete medication", "Removes it and every dose logged against it.", onClick = { confirmDelete = true })
            }
        }
    }
    if (confirmDelete && existing != null) {
        ConfirmDelete(
            "Delete ${existing.name}?",
            "Stopping keeps the history. Deleting removes the medication and every dose logged against it.",
            onConfirm = { confirmDelete = false; graph.care.deleteMedication(existing.id); navigator.popTo { it is Route.Medications || it is Route.PersonHub } },
            onDismiss = { confirmDelete = false },
        )
    }
}

private fun trimNumber(value: Double): String = if (value % 1.0 == 0.0) value.toLong().toString() else value.toString()
