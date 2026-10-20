package com.jackwallner.aging.ui.screens

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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.LocalHospital
import androidx.compose.material.icons.filled.MedicalInformation
import androidx.compose.material.icons.filled.Medication
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.jackwallner.aging.data.PaidBoundary
import com.jackwallner.aging.model.CareFeature
import com.jackwallner.aging.model.CareOverview
import com.jackwallner.aging.model.ScheduleEngine
import com.jackwallner.aging.ui.Format
import com.jackwallner.aging.ui.LocalGraph
import com.jackwallner.aging.ui.LocalNavigator
import com.jackwallner.aging.ui.Route
import com.jackwallner.aging.ui.theme.AgingTheme
import com.jackwallner.aging.ui.theme.Avatar
import com.jackwallner.aging.ui.theme.Card
import com.jackwallner.aging.ui.theme.DetailTopBar
import com.jackwallner.aging.ui.theme.FeatureTile
import com.jackwallner.aging.ui.theme.NavRow
import com.jackwallner.aging.ui.theme.RowDivider
import com.jackwallner.aging.ui.theme.ScreenTitle
import com.jackwallner.aging.ui.theme.SectionHeader
import com.jackwallner.aging.ui.theme.Spacing
import com.jackwallner.aging.ui.theme.StatTile
import java.time.Instant
import java.util.UUID

/** Port of `PeopleView`: everyone in the record, and the second person's paywall. */
@Composable
fun CareScreen() {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val state = graph.care.state
    val canAdd = PaidBoundary.canAddPerson(graph.store.isPro, state.people.size)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ScreenTitle("Care")
        SectionHeader("People")
        Card {
            state.people.forEachIndexed { index, person ->
                if (index > 0) RowDivider()
                Row(
                    Modifier.fillMaxWidth().clickable { navigator.push(Route.PersonHub(person.id)) }
                        .testTag("care.person.$index").padding(horizontal = Spacing.lg, vertical = Spacing.md),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Avatar(person.displayLabel, index)
                    Spacer(Modifier.width(Spacing.md))
                    Column(Modifier.weight(1f)) {
                        Text(person.displayLabel, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold), color = AgingTheme.colors.text)
                        val sub = listOf(person.relationship, CareOverview.detail(CareFeature.MEDICATIONS, state, person.id))
                            .filter { it.isNotEmpty() }.joinToString(" · ")
                        Text(sub, style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.secondaryText)
                    }
                }
            }
            if (state.people.isNotEmpty()) RowDivider()
            NavRow(
                title = "Add Person",
                detail = if (canAdd) null else "Elderhub Plus",
                icon = Icons.Filled.Add,
                modifier = Modifier.testTag("care.add-person"),
                onClick = { navigator.requestAddPerson(canAdd) },
            )
        }
        Text(
            if (graph.store.isPro) "Elderhub Plus is active. Add everyone you look after."
            else "The first person's care record is free, with every feature.",
            style = MaterialTheme.typography.bodySmall,
            color = AgingTheme.colors.secondaryText,
            modifier = Modifier.padding(horizontal = Spacing.lg + 4.dp, vertical = Spacing.sm),
        )
        Spacer(Modifier.height(Spacing.xl))
    }
}

/** Port of `PersonDetailView`: a hub whose tiles say what each feature is for. */
@Composable
fun PersonHubScreen(personId: UUID) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val state = graph.care.state
    val person = state.person(personId) ?: return
    val index = state.people.indexOf(person)
    val now = Instant.now()
    val zone = Format.zone
    val slots = ScheduleEngine.slots(state, personId, now, zone)
    val adherence = ScheduleEngine.adherence(state, personId, 7, now, zone)

    Column(Modifier.fillMaxSize()) {
        DetailTopBar(person.displayLabel, onBack = navigator::pop) {
            IconButton(onClick = { navigator.push(Route.PersonDetails(personId)) }, modifier = Modifier.testTag("hub.edit")) {
                Icon(Icons.Filled.Edit, contentDescription = "Edit ${person.displayLabel}")
            }
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            Card {
                Row(Modifier.padding(Spacing.lg), verticalAlignment = Alignment.CenterVertically) {
                    Avatar(person.displayLabel, index, size = 56)
                    Spacer(Modifier.width(Spacing.md))
                    Column {
                        Text(person.displayLabel, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold), color = AgingTheme.colors.text)
                        val sub = listOfNotNull(person.relationship.ifEmpty { null }, person.age(now.atZone(zone).toLocalDate())?.let { "Age $it" })
                        if (sub.isNotEmpty()) Text(sub.joinToString(" · "), style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.secondaryText)
                    }
                }
                Row(Modifier.padding(start = Spacing.lg, end = Spacing.lg, bottom = Spacing.lg), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    StatTile("${slots.count { !it.isPending }}/${slots.size}", "Doses today", Modifier.weight(1f))
                    StatTile(adherence?.let { "${Math.round(it * 100)}%" } ?: "–", "Taken, 7 days", Modifier.weight(1f))
                    StatTile("${state.activeMedications(personId).size}", "Medications", Modifier.weight(1f))
                }
            }
            Spacer(Modifier.height(Spacing.md))
            EmergencyBanner { navigator.push(Route.EmergencyCard(personId)) }
            SectionHeader("${person.displayLabel}'s record")
            val tiles = listOf(
                Triple(CareFeature.MEDICATIONS, Icons.Filled.Medication, AgingTheme.colors.accent) to Route.Medications(personId),
                Triple(CareFeature.VISITS, Icons.Filled.CalendarMonth, Color(0xFF2E9E7A)) to Route.Visits(personId),
                Triple(CareFeature.HEALTH_DETAILS, Icons.Filled.MedicalInformation, AgingTheme.colors.danger) to Route.PersonDetails(personId),
                Triple(CareFeature.CONTACTS, Icons.Filled.Phone, Color(0xFFE0703D)) to Route.Contacts(personId),
                Triple(CareFeature.PROVIDERS, Icons.Filled.Badge, Color(0xFF8A5CD6)) to Route.Providers(personId),
            )
            tiles.chunked(2).forEach { pair ->
                Row(
                    Modifier.padding(horizontal = Spacing.lg).padding(bottom = Spacing.md),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.md),
                ) {
                    pair.forEach { (tile, route) ->
                        val (feature, icon, tint) = tile
                        FeatureTile(
                            title = feature.title,
                            blurb = feature.blurb,
                            icon = icon,
                            tint = tint,
                            status = CareOverview.detail(feature, state, personId, now, zone),
                            modifier = Modifier.weight(1f).testTag("hub.${feature.name.lowercase()}"),
                        ) { navigator.push(route) }
                    }
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
            Spacer(Modifier.height(Spacing.xl))
        }
    }
}

@Composable
private fun EmergencyBanner(onClick: () -> Unit) {
    Row(
        Modifier
            .padding(horizontal = Spacing.lg)
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color(0xFFCC4047))
            .clickable(onClick = onClick)
            .testTag("hub.emergency-card")
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.LocalHospital, contentDescription = null, tint = Color.White)
        Spacer(Modifier.width(Spacing.md))
        Column(Modifier.weight(1f)) {
            Text("Emergency card", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = Color.White)
            Text("Meds, allergies and who to call. Works with no signal.", style = MaterialTheme.typography.bodyMedium, color = Color.White.copy(alpha = 0.9f))
        }
    }
}
