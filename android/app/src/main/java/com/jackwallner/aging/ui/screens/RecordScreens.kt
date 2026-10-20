package com.jackwallner.aging.ui.screens

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Intent
import android.net.Uri
import android.text.format.DateFormat
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.LocalPharmacy
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import com.jackwallner.aging.model.EmergencyContact
import com.jackwallner.aging.model.Provider
import com.jackwallner.aging.model.Visit
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
import java.time.LocalDate
import java.time.LocalTime
import java.util.UUID

/** A screen listing one kind of row, with an Add button. */
@Composable
private fun ListScreen(title: String, addLabel: String, addTag: String, onAdd: () -> Unit, content: @Composable () -> Unit) {
    val navigator = LocalNavigator.current
    Column(Modifier.fillMaxSize()) {
        DetailTopBar(title, onBack = navigator::pop) {
            IconButton(onClick = onAdd, modifier = Modifier.testTag(addTag)) { Icon(Icons.Filled.Add, contentDescription = addLabel) }
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            content()
            Spacer(Modifier.height(Spacing.xl))
        }
    }
}

// MARK: - Visits

@Composable
fun VisitsScreen(personId: UUID) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val state = graph.care.state
    val now = Instant.now()
    val upcoming = state.upcomingVisits(personId, now)
    val past = state.pastVisits(personId, now)
    ListScreen("Appointments", "Add appointment", "visits.add", { navigator.push(Route.VisitEditor(personId, null)) }) {
        SectionHeader("Upcoming")
        Card {
            if (upcoming.isEmpty()) EmptyNote("Nothing booked", "Add the next appointment so it shows on Today the week before.")
            upcoming.forEachIndexed { i, visit ->
                if (i > 0) RowDivider()
                NavRow(visit.displayTitle(), Format.visitDate(visit.date, visit.hasTimeOfDay(Format.zone, now)), Icons.Filled.Event) {
                    navigator.push(Route.VisitEditor(personId, visit.id))
                }
            }
        }
        if (past.isNotEmpty()) {
            SectionHeader("Past visits")
            Card {
                past.forEachIndexed { i, visit ->
                    if (i > 0) RowDivider()
                    val detail = listOf(Format.date(visit.date), visit.reason).filter { it.isNotEmpty() }.joinToString(" · ")
                    NavRow(visit.displayTitle(), detail) { navigator.push(Route.VisitEditor(personId, visit.id)) }
                }
            }
        }
    }
}

@Composable
fun VisitEditorScreen(personId: UUID, visitId: UUID?) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val zone = Format.zone
    val existing = visitId?.let { id -> graph.care.state.visits.firstOrNull { it.id == id } }
    val initial = existing?.date?.atZone(zone)
    var day by remember { mutableStateOf(initial?.toLocalDate() ?: LocalDate.now(zone).plusDays(7)) }
    var time by remember {
        mutableStateOf(initial?.toLocalTime()?.takeIf { existing?.hasTimeOfDay(zone) == true } ?: if (existing == null) LocalTime.of(9, 0) else null)
    }
    var provider by remember { mutableStateOf(existing?.provider.orEmpty()) }
    var specialty by remember { mutableStateOf(existing?.specialty.orEmpty()) }
    var reason by remember { mutableStateOf(existing?.reason.orEmpty()) }
    var notes by remember { mutableStateOf(existing?.notes.orEmpty()) }
    var followUp by remember { mutableStateOf(existing?.followUp.orEmpty()) }
    var confirmDelete by remember { mutableStateOf(false) }

    val isPastDay = day < LocalDate.now(zone)
    fun save() {
        // A past visit's clock is zeroed: nobody chose that time of day (iOS `hasTimeOfDay`).
        val at = if (isPastDay || time == null) day.atStartOfDay(zone) else day.atTime(time).atZone(zone)
        val base = existing ?: Visit(personId = personId, date = at.toInstant())
        graph.care.upsertVisit(
            base.copy(
                date = at.toInstant(), provider = provider.trim(), specialty = specialty.trim(), reason = reason.trim(),
                notes = notes.trim(), followUp = followUp.trim(),
            ),
        )
        navigator.pop()
    }

    EditorScaffold(
        title = if (existing == null) "Add Appointment" else "Appointment",
        canSave = listOf(provider, specialty, reason).any { it.isNotBlank() },
        onBack = navigator::pop,
        onSave = ::save,
    ) {
        SectionHeader("When")
        Row(Modifier.padding(horizontal = Spacing.lg), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            AssistChip(
                onClick = { DatePickerDialog(context, { _, y, m, d -> day = LocalDate.of(y, m + 1, d) }, day.year, day.monthValue - 1, day.dayOfMonth).show() },
                label = { Text(Format.date(day)) },
            )
            if (!isPastDay) {
                AssistChip(
                    onClick = {
                        val t = time ?: LocalTime.of(9, 0)
                        TimePickerDialog(context, { _, h, m -> time = LocalTime.of(h, m) }, t.hour, t.minute, DateFormat.is24HourFormat(context)).show()
                    },
                    label = { Text(time?.let { Format.time(day.atTime(it).atZone(zone).toInstant()) } ?: "Add a time") },
                )
            }
        }
        SectionHeader("Who and why")
        FormField("Doctor or clinic", provider, { provider = it }, tag = "visit.provider", capitalization = KeyboardCapitalization.Words)
        FormField("Specialty", specialty, { specialty = it }, capitalization = KeyboardCapitalization.Words)
        FormField("Reason", reason, { reason = it }, tag = "visit.reason")
        SectionHeader("What was said")
        FormField("Notes", notes, { notes = it }, singleLine = false)
        FormField("Follow-up", followUp, { followUp = it })
        if (existing != null) {
            Spacer(Modifier.height(Spacing.lg))
            Card { NavRow("Delete appointment", null, onClick = { confirmDelete = true }) }
        }
    }
    if (confirmDelete && existing != null) {
        ConfirmDelete("Delete this appointment?", "This removes it and its notes.", onConfirm = {
            confirmDelete = false; graph.care.deleteVisit(existing.id); navigator.pop()
        }, onDismiss = { confirmDelete = false })
    }
}

// MARK: - Contacts

@Composable
fun ContactsScreen(personId: UUID) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val contacts = graph.care.state.contactsOf(personId)
    ListScreen("Contacts", "Add contact", "contacts.add", { navigator.push(Route.ContactEditor(personId, null)) }) {
        SectionHeader("Emergency contacts")
        Card {
            if (contacts.isEmpty()) EmptyNote("No one yet", "Add who to call first. They go on the emergency card.")
            contacts.forEachIndexed { i, contact ->
                if (i > 0) RowDivider()
                val detail = listOf(if (contact.isPrimary) "CALL FIRST" else "", contact.relationship, contact.phone).filter { it.isNotEmpty() }.joinToString(" · ")
                Row {
                    Column(Modifier.weight(1f)) {
                        NavRow(contact.name, detail, Icons.Filled.Phone, tint = AgingTheme.colors.warning) {
                            navigator.push(Route.ContactEditor(personId, contact.id))
                        }
                    }
                    if (com.jackwallner.aging.model.Phone.dialable(contact.phone) != null) {
                        IconButton(onClick = { context.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:${com.jackwallner.aging.model.Phone.dialable(contact.phone)}"))) }) {
                            Icon(Icons.Filled.Phone, contentDescription = "Call ${contact.name}", tint = AgingTheme.colors.accent)
                        }
                    }
                }
            }
        }
    }
}


@Composable
fun ContactEditorScreen(personId: UUID, contactId: UUID?) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val existing = contactId?.let { id -> graph.care.state.contacts.firstOrNull { it.id == id } }
    val isFirst = graph.care.state.contactsOf(personId).isEmpty()
    var name by remember { mutableStateOf(existing?.name.orEmpty()) }
    var relationship by remember { mutableStateOf(existing?.relationship.orEmpty()) }
    var phone by remember { mutableStateOf(existing?.phone.orEmpty()) }
    var primary by remember { mutableStateOf(existing?.isPrimary ?: isFirst) }
    var confirmDelete by remember { mutableStateOf(false) }
    EditorScaffold(
        title = if (existing == null) "Add Contact" else "Contact",
        canSave = name.isNotBlank(),
        onBack = navigator::pop,
        onSave = {
            val base = existing ?: EmergencyContact(personId = personId)
            graph.care.upsertContact(base.copy(name = name.trim(), relationship = relationship.trim(), phone = phone.trim(), isPrimary = primary))
            navigator.pop()
        },
    ) {
        SectionHeader("Contact")
        FormField("Name", name, { name = it }, tag = "contact.name", capitalization = KeyboardCapitalization.Words)
        FormField("Relationship", relationship, { relationship = it }, capitalization = KeyboardCapitalization.Words)
        FormField("Phone", phone, { phone = it }, tag = "contact.phone", keyboardType = KeyboardType.Phone)
        Spacer(Modifier.height(Spacing.sm))
        Card { ToggleRow("Call first", "Marked CALL FIRST on the emergency card.", primary) { primary = it } }
        if (existing != null) {
            Spacer(Modifier.height(Spacing.lg))
            Card { NavRow("Delete contact", null, onClick = { confirmDelete = true }) }
        }
    }
    if (confirmDelete && existing != null) {
        ConfirmDelete("Delete ${existing.name}?", "They come off the emergency card.", onConfirm = {
            confirmDelete = false; graph.care.deleteContact(existing.id); navigator.pop()
        }, onDismiss = { confirmDelete = false })
    }
}

// MARK: - Providers

@Composable
fun ProvidersScreen(personId: UUID) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val providers = graph.care.state.providersOf(personId)
    ListScreen("Providers", "Add provider", "providers.add", { navigator.push(Route.ProviderEditor(personId, null)) }) {
        SectionHeader("Doctors and pharmacies")
        Card {
            if (providers.isEmpty()) EmptyNote("None saved", "Save doctors and pharmacies once, with their numbers, so nobody has to look them up again.")
            providers.forEachIndexed { i, provider ->
                if (i > 0) RowDivider()
                val detail = listOf(if (provider.isPharmacy) "Pharmacy" else provider.specialty, provider.phone).filter { it.isNotEmpty() }.joinToString(" · ")
                NavRow(provider.name, detail, if (provider.isPharmacy) Icons.Filled.LocalPharmacy else Icons.Filled.Badge) {
                    navigator.push(Route.ProviderEditor(personId, provider.id))
                }
            }
        }
    }
}

@Composable
fun ProviderEditorScreen(personId: UUID, providerId: UUID?) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val existing = providerId?.let { id -> graph.care.state.providers.firstOrNull { it.id == id } }
    var name by remember { mutableStateOf(existing?.name.orEmpty()) }
    var specialty by remember { mutableStateOf(existing?.specialty.orEmpty()) }
    var phone by remember { mutableStateOf(existing?.phone.orEmpty()) }
    var address by remember { mutableStateOf(existing?.address.orEmpty()) }
    var notes by remember { mutableStateOf(existing?.notes.orEmpty()) }
    var pharmacy by remember { mutableStateOf(existing?.isPharmacy ?: false) }
    var confirmDelete by remember { mutableStateOf(false) }
    EditorScaffold(
        title = if (existing == null) "Add Provider" else "Provider",
        canSave = name.isNotBlank(),
        onBack = navigator::pop,
        onSave = {
            val base = existing ?: Provider(personId = personId)
            graph.care.upsertProvider(
                base.copy(name = name.trim(), specialty = specialty.trim(), phone = phone.trim(), address = address.trim(), notes = notes.trim(), isPharmacy = pharmacy),
            )
            navigator.pop()
        },
    ) {
        SectionHeader("Provider")
        FormField("Name", name, { name = it }, tag = "provider.name", capitalization = KeyboardCapitalization.Words)
        Card { ToggleRow("Pharmacy", null, pharmacy) { pharmacy = it } }
        if (!pharmacy) FormField("Specialty", specialty, { specialty = it }, capitalization = KeyboardCapitalization.Words)
        FormField("Phone", phone, { phone = it }, keyboardType = KeyboardType.Phone)
        FormField("Address", address, { address = it })
        FormField("Notes", notes, { notes = it }, singleLine = false)
        if (existing != null) {
            Spacer(Modifier.height(Spacing.lg))
            Card { NavRow("Delete provider", "Medications linked to it keep their own details.", onClick = { confirmDelete = true }) }
        }
    }
    if (confirmDelete && existing != null) {
        ConfirmDelete("Delete ${existing.name}?", "Medications and visits linked to it are kept.", onConfirm = {
            confirmDelete = false; graph.care.deleteProvider(existing.id); navigator.pop()
        }, onDismiss = { confirmDelete = false })
    }
}
