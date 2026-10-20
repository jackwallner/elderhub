package com.jackwallner.aging.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Assignment
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.FamilyRestroom
import androidx.compose.material.icons.filled.LocalHospital
import androidx.compose.material.icons.filled.Medication
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.People
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.aging.ui.LocalGraph
import com.jackwallner.aging.ui.theme.AgingTheme
import com.jackwallner.aging.ui.theme.IconBadge
import com.jackwallner.aging.ui.theme.PrimaryButton
import com.jackwallner.aging.ui.theme.Spacing

private enum class OnboardingStep { PATH, NAME, FEATURES }

/**
 * Port of `OnboardingFlow`: who you are here for, then the person's name,
 * then what the record holds. The Android build keeps the record on this
 * phone, so there is no account step and nothing follows one.
 */
@Composable
fun OnboardingScreen() {
    val graph = LocalGraph.current
    var step by rememberSaveable { mutableStateOf(OnboardingStep.PATH) }
    var isSolo by rememberSaveable { mutableStateOf(false) }
    var personName by rememberSaveable { mutableStateOf("") }
    var relationship by rememberSaveable { mutableStateOf("") }
    var attested by rememberSaveable { mutableStateOf(false) }

    BackHandler(enabled = step != OnboardingStep.PATH) {
        step = if (step == OnboardingStep.FEATURES) OnboardingStep.NAME else OnboardingStep.PATH
    }

    Column(
        Modifier.fillMaxSize().background(AgingTheme.colors.background).safeDrawingPadding().imePadding(),
    ) {
        when (step) {
            OnboardingStep.PATH -> PathStep { solo ->
                isSolo = solo
                relationship = if (solo) "Me" else ""
                step = OnboardingStep.NAME
            }
            OnboardingStep.NAME -> NameStep(
                isSolo = isSolo,
                name = personName,
                onName = { personName = it },
                relationship = relationship,
                onRelationship = { relationship = it },
                attested = attested,
                onAttested = { attested = it },
                onContinue = { step = OnboardingStep.FEATURES },
            )
            OnboardingStep.FEATURES -> FeaturesStep(personName.trim()) {
                graph.care.completeOnboarding(personName, relationship, isSelf = isSolo, attested = attested)
            }
        }
    }
}

@Composable
private fun PathStep(onPick: (Boolean) -> Unit) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = Spacing.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(72.dp))
        Icon(Icons.AutoMirrored.Filled.Assignment, contentDescription = null, tint = AgingTheme.colors.accent, modifier = Modifier.size(52.dp))
        Spacer(Modifier.height(Spacing.md))
        Text(
            "Who are you here for?",
            style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold),
            color = AgingTheme.colors.text,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(28.dp))
        PathOption("Start a care record", "For a parent, partner, or anyone you help.", Icons.Filled.FamilyRestroom, "onboarding.path.supporter") { onPick(false) }
        Spacer(Modifier.height(Spacing.md))
        PathOption("Keep track of myself", "Make a private care record for yourself.", Icons.Filled.Person, "onboarding.path.solo") { onPick(true) }
        Spacer(Modifier.weight(1f))
        Text(
            "You can change this later.",
            style = MaterialTheme.typography.bodySmall,
            color = AgingTheme.colors.secondaryText,
            modifier = Modifier.padding(vertical = Spacing.xl),
        )
    }
}

@Composable
private fun PathOption(title: String, detail: String, icon: ImageVector, tag: String, onClick: () -> Unit) {
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
        Icon(icon, contentDescription = null, tint = AgingTheme.colors.accent, modifier = Modifier.size(30.dp))
        Spacer(Modifier.width(14.dp))
        Column {
            Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold), color = AgingTheme.colors.text)
            Text(detail, style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.secondaryText)
        }
    }
}

@Composable
private fun NameStep(
    isSolo: Boolean,
    name: String,
    onName: (String) -> Unit,
    relationship: String,
    onRelationship: (String) -> Unit,
    attested: Boolean,
    onAttested: (Boolean) -> Unit,
    onContinue: () -> Unit,
) {
    val suggestions = if (isSolo) listOf("Me") else listOf("Mom", "Dad", "Spouse", "Partner", "Me")
    val requiresAttestation = !isSolo
    val canContinue = name.isNotBlank() && (!requiresAttestation || attested)
    val focus = LocalFocusManager.current
    Column(Modifier.fillMaxSize().padding(horizontal = 28.dp)) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(48.dp))
            Icon(Icons.AutoMirrored.Filled.Assignment, contentDescription = null, tint = AgingTheme.colors.accent, modifier = Modifier.size(52.dp))
            Spacer(Modifier.height(Spacing.md))
            Text(
                if (isSolo) "What should we call you?" else "Who are you keeping track of?",
                style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold),
                color = AgingTheme.colors.text,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(Spacing.sm))
            Text(
                if (isSolo) "Your own list. You can add someone else later."
                else "The person you look after, not your own account. You can add more later.",
                style = MaterialTheme.typography.bodyLarge,
                color = AgingTheme.colors.secondaryText,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(28.dp))
            OutlinedTextField(
                value = name,
                onValueChange = onName,
                label = { Text(if (isSolo) "Your name" else "Their name") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Next),
                modifier = Modifier.fillMaxWidth().testTag("onboarding.name"),
            )
            Spacer(Modifier.height(Spacing.md))
            OutlinedTextField(
                value = relationship,
                onValueChange = onRelationship,
                label = { Text("Relationship (optional)") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { focus.clearFocus() }),
                modifier = Modifier.fillMaxWidth().testTag("onboarding.relationship"),
            )
            Spacer(Modifier.height(Spacing.sm))
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                suggestions.forEach { option ->
                    val chosen = relationship.trim().equals(option, ignoreCase = true)
                    FilterChip(
                        selected = chosen,
                        onClick = { onRelationship(if (chosen) "" else option); focus.clearFocus() },
                        label = { Text(option) },
                        colors = FilterChipDefaults.filterChipColors(selectedContainerColor = AgingTheme.colors.accent.copy(alpha = 0.18f)),
                    )
                }
            }
            if (requiresAttestation) {
                Row(Modifier.fillMaxWidth().padding(top = Spacing.md), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "I have permission to keep and share this person’s care information.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = AgingTheme.colors.text,
                        modifier = Modifier.weight(1f),
                    )
                    Spacer(Modifier.width(Spacing.md))
                    Switch(checked = attested, onCheckedChange = onAttested, modifier = Modifier.testTag("onboarding.attestation"))
                }
            }
        }
        PrimaryButton("Continue", enabled = canContinue, modifier = Modifier.testTag("onboarding.continue"), onClick = onContinue)
        Text(
            "A copy stays on this phone, so it opens with no signal.",
            style = MaterialTheme.typography.bodySmall,
            color = AgingTheme.colors.secondaryText,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(top = Spacing.sm, bottom = Spacing.xl),
        )
    }
}

@Composable
private fun FeaturesStep(personName: String, onContinue: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(horizontal = Spacing.xl)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Spacer(Modifier.height(36.dp))
            Text(
                "$personName’s care record is ready",
                style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold),
                color = AgingTheme.colors.text,
            )
            Text(
                "Start with what matters today. You do not need to set everything up at once.",
                style = MaterialTheme.typography.bodyLarge,
                color = AgingTheme.colors.secondaryText,
            )
            Spacer(Modifier.height(4.dp))
            Feature(Icons.Filled.Medication, "Medications and doses", "Add schedules, then mark doses taken or skipped from Today.")
            Feature(Icons.Filled.LocalHospital, "Emergency card", "Keep allergies, conditions, contacts, providers, and medications available offline.")
            Feature(Icons.Filled.Checklist, "Visits, providers, and contacts", "Keep the practical details in one record instead of scattered messages.")
            Feature(Icons.Filled.People, "Looking after more than one person?", "Add Mom, Dad, or a partner under Care.")
        }
        PrimaryButton(
            "Open $personName’s record",
            modifier = Modifier.padding(vertical = Spacing.xl).testTag("onboarding.finish"),
            onClick = onContinue,
        )
    }
}

@Composable
private fun Feature(icon: ImageVector, title: String, detail: String) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(AgingTheme.colors.card).padding(14.dp),
        verticalAlignment = Alignment.Top,
    ) {
        IconBadge(icon, AgingTheme.colors.accent, size = 36)
        Spacer(Modifier.width(Spacing.md))
        Column {
            Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold), color = AgingTheme.colors.text)
            Text(detail, style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.secondaryText)
        }
    }
}
