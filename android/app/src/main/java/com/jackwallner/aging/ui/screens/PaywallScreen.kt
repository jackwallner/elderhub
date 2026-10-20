package com.jackwallner.aging.ui.screens

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.RadioButtonChecked
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.aging.data.PackageKind
import com.jackwallner.aging.data.PaywallCopy
import com.jackwallner.aging.data.Plan
import com.jackwallner.aging.data.PurchaseException
import com.jackwallner.aging.data.PurchaseOutcome
import com.jackwallner.aging.ui.LocalGraph
import com.jackwallner.aging.ui.theme.AgingTheme
import com.jackwallner.aging.ui.theme.PrimaryButton
import com.jackwallner.aging.ui.theme.Spacing
import kotlinx.coroutines.launch

/** Port of `PaywallView`: opened by adding a second person, or from Settings. */
@Composable
fun PaywallScreen(onDismiss: () -> Unit) {
    val graph = LocalGraph.current
    val store = graph.store
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val plans = store.plans
    var selectedId by remember { mutableStateOf<String?>(null) }
    var isPurchasing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    val selected = plans.firstOrNull { it.packageId == selectedId } ?: PaywallCopy.defaultSelection(plans)
    val trialDays = store.eligibleTrialDays(selected)
    val monthly = plans.firstOrNull { it.kind == PackageKind.MONTHLY }

    BackHandler(onBack = onDismiss)
    LaunchedEffect(Unit) {
        store.trackPaywallImpression("elderhub_paywall")
        if (store.plans.isEmpty()) store.refresh()
    }
    LaunchedEffect(store.isPro) { if (store.isPro) onDismiss() }

    fun open(url: String) = context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))

    Column(Modifier.fillMaxSize().background(AgingTheme.colors.background).safeDrawingPadding().testTag("paywall")) {
        Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.sm), horizontalArrangement = Arrangement.End) {
            TextButton(onClick = onDismiss, modifier = Modifier.testTag("paywall.close")) { Text("Not now") }
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Spacing.xl),
            verticalArrangement = Arrangement.spacedBy(Spacing.xl),
        ) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(
                    if (trialDays == null) Icons.Filled.GroupAdd else Icons.Filled.CardGiftcard,
                    contentDescription = null,
                    tint = AgingTheme.colors.accent,
                    modifier = Modifier.size(46.dp),
                )
                Text(
                    PaywallCopy.headline(trialDays),
                    style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold),
                    color = AgingTheme.colors.text,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.testTag("paywall.headline"),
                )
                Text(PaywallCopy.subhead(trialDays), style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.secondaryText, textAlign = TextAlign.Center)
            }
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                val icons = listOf(Icons.Filled.People, Icons.Filled.WbSunny, Icons.Filled.CheckCircle)
                PaywallCopy.BENEFITS.forEachIndexed { i, text -> Benefit(icons[i], text) }
            }
            when {
                store.isLoadingPlans -> Box(Modifier.fillMaxWidth().padding(vertical = 30.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.testTag("paywall.loading"))
                }
                store.hasNoPlans -> Unavailable(store.loadFailure) { scope.launch { store.refresh() } }
                else -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    plans.forEach { plan ->
                        PlanRow(plan, plan.packageId == selected?.packageId, PaywallCopy.planDetail(plan, store.eligibleTrialDays(plan)),
                            PaywallCopy.savingsPercent(plan, monthly), enabled = !isPurchasing) { selectedId = plan.packageId }
                    }
                    if (trialDays != null) TrialTimeline(trialDays, selected?.priceFormatted)
                }
            }
        }
        // The purchase area is pinned, so the decision stays under the thumb.
        Column(
            Modifier.fillMaxWidth().background(AgingTheme.colors.card).padding(horizontal = Spacing.xl, vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (plans.isNotEmpty()) {
                PrimaryButton(
                    PaywallCopy.cta(selected, trialDays, isPurchasing),
                    enabled = !isPurchasing && selected != null,
                    modifier = Modifier.testTag("paywall.continue"),
                ) {
                    val activity = context as? Activity ?: return@PrimaryButton
                    isPurchasing = true
                    error = null
                    scope.launch {
                        try {
                            when (store.purchase(activity, selected)) {
                                PurchaseOutcome.PURCHASED -> onDismiss()
                                PurchaseOutcome.PENDING -> notice = "Google Play is still processing the payment. Elderhub Plus unlocks as soon as it completes."
                                PurchaseOutcome.CANCELLED -> Unit
                            }
                        } catch (e: PurchaseException) {
                            error = e.message
                        } finally {
                            isPurchasing = false
                        }
                    }
                }
                if (trialDays != null) {
                    Text("No payment now · Cancel any time", style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium), color = AgingTheme.colors.secondaryText)
                }
            }
            val footnote = error ?: notice ?: PaywallCopy.disclosure(selected, trialDays)
            if (footnote != null) {
                Text(
                    footnote,
                    style = MaterialTheme.typography.labelSmall,
                    color = if (error != null) AgingTheme.colors.danger else AgingTheme.colors.secondaryText,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.testTag("paywall.disclosure"),
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { scope.launch { notice = store.restorePurchases() } }, modifier = Modifier.testTag("paywall.restore")) { Text("Restore") }
                Dot()
                TextButton(onClick = { open(Links.TERMS) }) { Text("Terms") }
                Dot()
                TextButton(onClick = { open(Links.PRIVACY) }) { Text("Privacy") }
            }
        }
    }
}

@Composable
private fun Dot() = Text("·", color = AgingTheme.colors.secondaryText)

@Composable
private fun Benefit(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = AgingTheme.colors.accent, modifier = Modifier.width(26.dp))
        Spacer(Modifier.width(Spacing.md))
        Text(text, style = MaterialTheme.typography.bodyLarge, color = AgingTheme.colors.text)
    }
}

@Composable
private fun PlanRow(plan: Plan, selected: Boolean, detail: String, savings: Int?, enabled: Boolean, onSelect: () -> Unit) {
    val colors = AgingTheme.colors
    val shape = RoundedCornerShape(12.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (selected) colors.accent.copy(alpha = 0.10f) else colors.fill)
            .then(if (selected) Modifier.border(BorderStroke(2.dp, colors.accent), shape) else Modifier)
            .selectable(selected = selected, enabled = enabled, role = Role.RadioButton, onClick = onSelect)
            .testTag("paywall.plan.${plan.kind.name.lowercase()}")
            .heightIn(min = 64.dp)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            if (selected) Icons.Filled.RadioButtonChecked else Icons.Filled.RadioButtonUnchecked,
            contentDescription = null,
            tint = if (selected) colors.accent else colors.secondaryText,
        )
        Spacer(Modifier.width(Spacing.md))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(PaywallCopy.planTitle(plan), style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = colors.text)
                if (savings != null) {
                    Spacer(Modifier.width(Spacing.sm))
                    Text(
                        "Save $savings%",
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                        color = colors.taken,
                        modifier = Modifier.clip(RoundedCornerShape(50)).background(colors.taken.copy(alpha = 0.16f)).padding(horizontal = 6.dp, vertical = 2.dp),
                    )
                }
            }
            Text(detail, style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
        }
        Spacer(Modifier.width(Spacing.sm))
        Text(plan.priceFormatted, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = colors.text)
    }
}

@Composable
private fun TrialTimeline(trialDays: Int, priceLabel: String?) {
    val reminderDay = maxOf(trialDays - 1, 1)
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(AgingTheme.colors.card).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("How the free trial works", style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold), color = AgingTheme.colors.text)
        Step(Icons.Filled.LockOpen, "Today: everything unlocks", "Add the people you look after and use every feature.")
        Step(Icons.Filled.NotificationsActive, "Day $reminderDay: a heads-up", "Google Play reminds you before the trial ends.")
        Step(Icons.Filled.CardGiftcard, "Day $trialDays: the trial ends", priceLabel?.let { "Billed $it unless you cancel first." } ?: "You are only billed if you keep it.")
    }
}

@Composable
private fun Step(icon: ImageVector, title: String, detail: String) {
    Row {
        Icon(icon, contentDescription = null, tint = AgingTheme.colors.accent, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(Spacing.md))
        Column {
            Text(title, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = AgingTheme.colors.text)
            Text(detail, style = MaterialTheme.typography.bodySmall, color = AgingTheme.colors.secondaryText)
        }
    }
}

@Composable
private fun Unavailable(reason: String?, onRetry: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 12.dp).testTag("paywall.unavailable"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.Filled.Warning, contentDescription = null, tint = AgingTheme.colors.secondaryText, modifier = Modifier.size(34.dp))
        Text("Couldn't load the plans", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = AgingTheme.colors.text)
        Text(
            "We couldn't reach Google Play just now. Everything you have already entered is safe on this phone, and the first person's care record stays free either way.",
            style = MaterialTheme.typography.bodyMedium,
            color = AgingTheme.colors.secondaryText,
            textAlign = TextAlign.Center,
        )
        TextButton(onClick = onRetry, modifier = Modifier.testTag("paywall.retry")) { Text("Try again") }
        Text("Already bought Elderhub Plus? Tap Restore below.", style = MaterialTheme.typography.bodySmall, color = AgingTheme.colors.secondaryText)
        if (reason != null) Text(reason, style = MaterialTheme.typography.labelSmall, color = AgingTheme.colors.secondaryText, textAlign = TextAlign.Center)
    }
}
