package com.jackwallner.aging.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Help
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.jackwallner.aging.BuildConfig
import com.jackwallner.aging.ui.LocalGraph
import com.jackwallner.aging.ui.LocalNavigator
import com.jackwallner.aging.ui.theme.AgingTheme
import com.jackwallner.aging.ui.theme.Card
import com.jackwallner.aging.ui.theme.NavRow
import com.jackwallner.aging.ui.theme.RowDivider
import com.jackwallner.aging.ui.theme.ScreenTitle
import com.jackwallner.aging.ui.theme.SectionHeader
import com.jackwallner.aging.ui.theme.Spacing
import kotlinx.coroutines.launch

object Links {
    const val PRIVACY = "https://jackwallner.github.io/elderhub/privacy-policy.html"
    const val TERMS = "https://jackwallner.github.io/elderhub/terms.html"
    const val SUPPORT = "https://jackwallner.github.io/elderhub/support.html"
    const val PLAY_LISTING = "https://play.google.com/store/apps/details?id=com.jackwallner.aging"
    const val FEEDBACK_EMAIL = "jackwallner+medlist@gmail.com"
    const val MANAGE_SUBSCRIPTIONS = "https://play.google.com/store/account/subscriptions?package=com.jackwallner.aging"
}

const val MEDICAL_DISCLAIMER =
    "This app helps you organize medication and health information. It is not a medical device and does not provide medical advice. " +
        "It cannot tell whether anyone is unwell and it does not call for help. Always follow the guidance of a licensed clinician."

/** Port of `SettingsView` for a record kept on this phone. */
@Composable
fun SettingsScreen() {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var message by remember { mutableStateOf<String?>(null) }
    var askName by remember { mutableStateOf(false) }
    var askReviewCode by remember { mutableStateOf(false) }

    fun open(url: String) = context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ScreenTitle("Settings")

        SectionHeader("Elderhub Plus")
        Card {
            if (graph.store.isPro) {
                NavRow("Elderhub Plus is active", "Add everyone you look after.", Icons.Filled.WorkspacePremium, onClick = null)
                RowDivider()
                NavRow("Manage subscription", "Google Play › Payments & subscriptions", onClick = { open(Links.MANAGE_SUBSCRIPTIONS) })
            } else {
                NavRow(
                    "Upgrade to Elderhub Plus",
                    "Add more people to this care record. Every feature is already free for the first person.",
                    Icons.Filled.WorkspacePremium,
                    modifier = Modifier.testTag("settings.upgrade"),
                    onClick = { navigator.showPaywall = true },
                )
            }
            RowDivider()
            NavRow("Restore purchases", null, Icons.Filled.Restore, modifier = Modifier.testTag("settings.restore"), onClick = {
                scope.launch { message = graph.store.restorePurchases() }
            })
            if (BuildConfig.PLAY_REVIEW_CODE_SHA256.isNotEmpty() && !graph.store.isPro) {
                RowDivider()
                NavRow("Reviewer access", "For Google Play review", Icons.Filled.Key, modifier = Modifier.testTag("settings.review-access"), onClick = { askReviewCode = true })
            }
        }

        SectionHeader("You")
        Card {
            NavRow(
                "Your name",
                graph.care.state.caregiverName.ifEmpty { "Shown beside the doses you mark" },
                Icons.Filled.Person,
                modifier = Modifier.testTag("settings.name"),
                onClick = { askName = true },
            )
        }
        Text(
            "Everything is saved on this phone, and nowhere else. If you lose the phone, the record goes with it.",
            style = MaterialTheme.typography.bodySmall,
            color = AgingTheme.colors.secondaryText,
            modifier = Modifier.padding(horizontal = Spacing.lg + 4.dp, vertical = Spacing.sm),
        )

        SectionHeader("Feedback")
        Card {
            NavRow("Rate Elderhub", null, Icons.Filled.Star, onClick = { open(Links.PLAY_LISTING) })
            RowDivider()
            NavRow("Send Feedback", null, Icons.Filled.Email, onClick = {
                val mail = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:${Links.FEEDBACK_EMAIL}"))
                    .putExtra(Intent.EXTRA_SUBJECT, "Elderhub for Android feedback")
                    .putExtra(Intent.EXTRA_TEXT, "\n\nElderhub ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}), Android ${android.os.Build.VERSION.RELEASE}")
                runCatching { context.startActivity(mail) }.onFailure { message = "No email app is set up. Write to ${Links.FEEDBACK_EMAIL}." }
            })
        }
        Text(
            "The email arrives with your app version and nothing at all from the care record.",
            style = MaterialTheme.typography.bodySmall,
            color = AgingTheme.colors.secondaryText,
            modifier = Modifier.padding(horizontal = Spacing.lg + 4.dp, vertical = Spacing.sm),
        )

        SectionHeader("Privacy")
        Card {
            NavRow("A full copy lives on this phone, so it opens with no signal", null, Icons.Filled.Lock, onClick = null)
            RowDivider()
            NavRow("No location, ever. Nothing is used for advertising or tracking", null, Icons.Filled.Lock, onClick = null)
            RowDivider()
            NavRow("Privacy policy", null, Icons.Filled.Description, onClick = { open(Links.PRIVACY) })
            RowDivider()
            NavRow("Terms of use", null, Icons.Filled.Description, onClick = { open(Links.TERMS) })
            RowDivider()
            NavRow("Support", null, Icons.Filled.Help, onClick = { open(Links.SUPPORT) })
        }

        Text(
            MEDICAL_DISCLAIMER,
            style = MaterialTheme.typography.bodySmall,
            color = AgingTheme.colors.secondaryText,
            modifier = Modifier.padding(horizontal = Spacing.lg + 4.dp, vertical = Spacing.lg).testTag("settings.disclaimer"),
        )
        Text(
            "Elderhub ${BuildConfig.VERSION_NAME}",
            style = MaterialTheme.typography.bodySmall,
            color = AgingTheme.colors.secondaryText,
            modifier = Modifier.padding(horizontal = Spacing.lg + 4.dp),
        )
        Spacer(Modifier.height(Spacing.xl))
    }

    message?.let { text ->
        AlertDialog(
            onDismissRequest = { message = null },
            title = { Text("Restore purchases") },
            text = { Text(text) },
            confirmButton = { TextButton(onClick = { message = null }) { Text("OK") } },
        )
    }
    if (askName) {
        TextPrompt("Your name", "Shown beside the doses you mark, so the log says who did it.", graph.care.state.caregiverName, onDone = {
            graph.care.setCaregiverName(it); askName = false
        }, onDismiss = { askName = false })
    }
    if (askReviewCode) {
        TextPrompt("Reviewer access", "Enter the access code from the Play Console app access notes.", "", secret = true, onDone = {
            askReviewCode = false
            message = if (graph.store.activateReviewAccess(it)) "Elderhub Plus is unlocked for review on this phone." else "That code was not recognised."
        }, onDismiss = { askReviewCode = false })
    }
}

@Composable
private fun TextPrompt(title: String, detail: String, initial: String, secret: Boolean = false, onDone: (String) -> Unit, onDismiss: () -> Unit) {
    var value by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                Text(detail, style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(Spacing.md))
                OutlinedTextField(
                    value = value,
                    onValueChange = { value = it },
                    singleLine = true,
                    visualTransformation = if (secret) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
                    modifier = Modifier.testTag("prompt.field"),
                )
            }
        },
        confirmButton = { TextButton(onClick = { onDone(value) }, modifier = Modifier.testTag("prompt.done")) { Text("Done") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
