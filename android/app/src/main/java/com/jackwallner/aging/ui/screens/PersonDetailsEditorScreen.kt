package com.jackwallner.aging.ui.screens

import android.app.DatePickerDialog
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AssistChip
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.material3.Icon
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.jackwallner.aging.model.Person
import com.jackwallner.aging.ui.Format
import com.jackwallner.aging.ui.LocalGraph
import com.jackwallner.aging.ui.LocalNavigator
import com.jackwallner.aging.ui.Route
import com.jackwallner.aging.ui.theme.AgingTheme
import com.jackwallner.aging.ui.theme.Card
import com.jackwallner.aging.ui.theme.ConfirmDelete
import com.jackwallner.aging.ui.theme.EditorScaffold
import com.jackwallner.aging.ui.theme.FormField
import com.jackwallner.aging.ui.theme.NavRow
import com.jackwallner.aging.ui.theme.SectionHeader
import com.jackwallner.aging.ui.theme.Spacing
import com.jackwallner.aging.ui.theme.ToggleRow
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

/**
 * Add Person (personId null) and the Details editor: name, date of birth,
 * blood type, allergies, conditions and family notes.
 */
@Composable
fun PersonDetailsEditorScreen(personId: UUID?) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val existing = personId?.let(graph.care.state::person)
    var name by remember { mutableStateOf(existing?.name.orEmpty()) }
    var relationship by remember { mutableStateOf(existing?.relationship.orEmpty()) }
    var birthDate by remember { mutableStateOf(existing?.birthDate) }
    var bloodType by remember { mutableStateOf(existing?.bloodType.orEmpty()) }
    var allergies by remember { mutableStateOf(existing?.allergies.orEmpty()) }
    var conditions by remember { mutableStateOf(existing?.conditions.orEmpty()) }
    var notes by remember { mutableStateOf(existing?.notes.orEmpty()) }
    var attested by remember { mutableStateOf(existing?.surrogateAttestedAt != null || existing?.isSelf == true) }
    var confirmDelete by remember { mutableStateOf(false) }
    val isNew = existing == null

    EditorScaffold(
        title = if (isNew) "Add Person" else "Details",
        canSave = name.isNotBlank() && (!isNew || attested),
        onBack = navigator::pop,
        onSave = {
            val base = existing ?: Person(surrogateAttestedAt = Instant.now())
            val saved = base.copy(
                name = name.trim(), relationship = relationship.trim(), birthDate = birthDate, bloodType = bloodType.trim(),
                allergies = allergies, conditions = conditions, notes = notes.trim(),
            )
            graph.care.upsertPerson(saved)
            navigator.pop()
            if (isNew) navigator.push(Route.PersonHub(saved.id))
        },
    ) {
        SectionHeader("Name")
        FormField("Name", name, { name = it }, tag = "person.name", capitalization = KeyboardCapitalization.Words)
        FormField(
            "Relationship (optional)", relationship, { relationship = it }, capitalization = KeyboardCapitalization.Words,
            supporting = "The name is what every screen calls this record. The relationship is the subtitle under it.",
        )
        if (isNew) {
            Card {
                ToggleRow(
                    "I have permission",
                    "They know I'm keeping this, or I'm the one who makes their health decisions.",
                    attested,
                    tag = "person.attestation",
                ) { attested = it }
            }
        }

        SectionHeader("For the emergency card")
        Row(Modifier.padding(horizontal = Spacing.lg), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            AssistChip(
                onClick = {
                    val d = birthDate ?: LocalDate.of(1950, 1, 1)
                    DatePickerDialog(context, { _, y, m, day -> birthDate = LocalDate.of(y, m + 1, day) }, d.year, d.monthValue - 1, d.dayOfMonth).show()
                },
                label = { Text(birthDate?.let { "Born ${Format.date(it)}" } ?: "Add date of birth") },
            )
        }
        FormField("Blood type", bloodType, { bloodType = it }, capitalization = KeyboardCapitalization.Characters)
        ListEditor("Allergies", "Add an allergy", allergies, tag = "person.allergies") { allergies = it }
        ListEditor("Conditions", "Add a condition", conditions, tag = "person.conditions") { conditions = it }

        SectionHeader("Notes")
        FormField(
            "Anything else worth knowing", notes, { notes = it }, singleLine = false,
            supporting = "For your family. This does not print on the emergency card or the shared one-pager.",
        )

        if (!isNew && graph.care.state.people.size > 1) {
            Spacer(Modifier.height(Spacing.lg))
            Card { NavRow("Delete ${existing.displayLabel}'s record", null, onClick = { confirmDelete = true }) }
        }
    }
    if (confirmDelete && existing != null) {
        ConfirmDelete(
            "Delete ${existing.displayLabel}'s record?",
            "This removes their medications, doses, appointments, contacts and providers from this phone.",
            onConfirm = {
                confirmDelete = false
                navigator.popTo { false }
                graph.care.deletePerson(existing.id)
            },
            onDismiss = { confirmDelete = false },
        )
    }
}

/** A list of short entries edited as chips, with an add field. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ListEditor(label: String, placeholder: String, items: List<String>, tag: String, onChange: (List<String>) -> Unit) {
    var draft by remember { mutableStateOf("") }
    Text(label, style = MaterialTheme.typography.titleSmall, color = AgingTheme.colors.secondaryText, modifier = Modifier.padding(start = Spacing.lg, top = Spacing.md))
    if (items.isNotEmpty()) {
        FlowRow(Modifier.padding(horizontal = Spacing.lg), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            items.forEach { item ->
                InputChip(
                    selected = false,
                    onClick = {},
                    label = { Text(item) },
                    trailingIcon = { Icon(Icons.Filled.Close, contentDescription = "Remove $item", modifier = Modifier.clickable { onChange(items - item) }) },
                )
            }
        }
    }
    Row {
        FormField(placeholder, draft, { draft = it }, modifier = Modifier.weight(1f), tag = "$tag.field", capitalization = KeyboardCapitalization.Sentences)
    }
    TextButton(
        onClick = {
            val entry = draft.trim()
            if (entry.isNotEmpty() && items.none { it.equals(entry, ignoreCase = true) }) onChange(items + entry)
            draft = ""
        },
        enabled = draft.isNotBlank(),
        modifier = Modifier.padding(horizontal = Spacing.sm).testTag("$tag.add"),
    ) { Text("Add") }
}
