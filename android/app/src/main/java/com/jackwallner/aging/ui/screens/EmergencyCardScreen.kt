package com.jackwallner.aging.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.jackwallner.aging.model.MedListExporter
import com.jackwallner.aging.model.Phone
import com.jackwallner.aging.ui.Format
import com.jackwallner.aging.ui.LocalGraph
import com.jackwallner.aging.ui.LocalNavigator
import com.jackwallner.aging.ui.Route
import com.jackwallner.aging.ui.theme.AgingTheme
import com.jackwallner.aging.ui.theme.DetailTopBar
import java.util.UUID

/**
 * Port of `EmergencyCardView`: the page handed to a paramedic. Every critical
 * section draws even when empty, in step with `MedListExporter`.
 */
@Composable
fun EmergencyCardScreen(personId: UUID) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val state = graph.care.state
    val person = state.person(personId) ?: return
    val meds = state.activeMedications(personId)
    val contacts = state.contactsOf(personId)
    val providers = state.providersOf(personId).filter { it.phone.isNotEmpty() }
    val isEmpty = person.allergies.isEmpty() && person.conditions.isEmpty() && contacts.isEmpty() &&
        person.bloodType.isEmpty() && meds.isEmpty() && providers.isEmpty()

    fun dial(phone: String) {
        Phone.dialable(phone)?.let { context.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$it"))) }
    }

    Column(Modifier.fillMaxSize()) {
        DetailTopBar("Emergency Card", onBack = navigator::pop) {
            IconButton(onClick = {
                val text = MedListExporter.plainText(state, personId)
                val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
                context.startActivity(Intent.createChooser(send, "Share ${person.displayLabel}'s card"))
            }, modifier = Modifier.testTag("card.share")) { Icon(Icons.Filled.Share, contentDescription = "Share") }
            IconButton(onClick = { navigator.push(Route.PersonDetails(personId)) }, modifier = Modifier.testTag("card.edit")) {
                Icon(Icons.Filled.Edit, contentDescription = "Edit")
            }
        }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(person.name.ifEmpty { person.displayLabel }, style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold), color = AgingTheme.colors.text)
                val born = person.birthDate?.let { "Born ${Format.date(it)}" + (person.age()?.let { a -> " (age $a)" } ?: "") } ?: "Date of birth not recorded"
                Text(born, style = MaterialTheme.typography.bodyLarge, color = AgingTheme.colors.secondaryText)
                Text("Blood type: ${person.bloodType.ifEmpty { "not recorded" }}", style = MaterialTheme.typography.bodyLarge, color = AgingTheme.colors.secondaryText)
            }
            if (isEmpty) {
                Column(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(AgingTheme.colors.card).padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text("Nothing on the card yet", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = AgingTheme.colors.text)
                    Text(
                        "Add allergies, conditions, blood type and who to call. This is the page you hand to a paramedic.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = AgingTheme.colors.secondaryText,
                    )
                }
            }
            Block("Allergies", person.allergies, AgingTheme.colors.danger)
            Block("Conditions", person.conditions, AgingTheme.colors.warning)
            Block("Medications", meds.map { med ->
                listOf(med.displayName, if (med.isAsNeeded) "as needed" else med.scheduleLabel(), med.purpose.let { if (it.isEmpty()) "" else "for $it" })
                    .filter { it.isNotEmpty() }.joinToString(" · ")
            }, AgingTheme.colors.accent, emptyText = "None recorded")
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                BlockTitle("Emergency contacts", AgingTheme.colors.text)
                if (contacts.isEmpty()) NotRecorded()
                contacts.forEach { contact ->
                    Row(Modifier.fillMaxWidth().clickable(enabled = Phone.dialable(contact.phone) != null) { dial(contact.phone) }.padding(vertical = 4.dp)) {
                        Column(Modifier.weight(1f)) {
                            if (contact.isPrimary) {
                                Text(
                                    "CALL FIRST",
                                    style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold),
                                    color = Color.White,
                                    modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(Color(0xFFCC4047)).padding(horizontal = 8.dp, vertical = 2.dp),
                                )
                                Spacer(Modifier.height(4.dp))
                            }
                            val who = if (contact.relationship.isEmpty()) contact.name else "${contact.name} (${contact.relationship})"
                            Text("$who, ${contact.phone.ifEmpty { "no phone number saved" }}", style = MaterialTheme.typography.bodyLarge, color = AgingTheme.colors.text)
                        }
                    }
                }
            }
            if (providers.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    BlockTitle("Providers", AgingTheme.colors.text)
                    providers.forEach { provider ->
                        val label = if (provider.specialty.isEmpty()) provider.name else "${provider.name} (${provider.specialty})"
                        Text(
                            "$label, ${provider.phone}",
                            style = MaterialTheme.typography.bodyLarge,
                            color = AgingTheme.colors.text,
                            modifier = Modifier.fillMaxWidth().clickable { dial(provider.phone) }.padding(vertical = 4.dp),
                        )
                    }
                }
            }
            Text(MedListExporter.DISCLAIMER, style = MaterialTheme.typography.bodySmall, color = AgingTheme.colors.secondaryText)
        }
    }
}

@Composable
private fun Block(title: String, lines: List<String>, tint: Color, emptyText: String? = null) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        BlockTitle(title, tint)
        if (lines.isEmpty()) {
            if (emptyText != null) Text(emptyText, style = MaterialTheme.typography.bodyLarge, color = AgingTheme.colors.secondaryText) else NotRecorded()
        }
        lines.forEach { line ->
            Row {
                Text("•", color = tint, style = MaterialTheme.typography.bodyLarge)
                Spacer(Modifier.width(8.dp))
                Text(line, style = MaterialTheme.typography.bodyLarge, color = AgingTheme.colors.text)
            }
        }
    }
}

@Composable
private fun BlockTitle(title: String, tint: Color) {
    Text(
        title.uppercase(),
        style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold, letterSpacing = MaterialTheme.typography.titleSmall.letterSpacing),
        color = tint,
        modifier = Modifier.semantics { heading() },
    )
}

@Composable
private fun NotRecorded() {
    Text("Not recorded", style = MaterialTheme.typography.bodyLarge, color = AgingTheme.colors.secondaryText)
}
