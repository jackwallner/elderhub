package com.jackwallner.aging.ui.screens

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.filled.MarkEmailRead
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.aging.AppGraph
import com.jackwallner.aging.R
import com.jackwallner.aging.data.AccessScope
import com.jackwallner.aging.data.GroupMember
import com.jackwallner.aging.data.GroupRole
import com.jackwallner.aging.data.InviteLink
import com.jackwallner.aging.data.InviteMessage
import com.jackwallner.aging.data.PendingInvite
import com.jackwallner.aging.data.SignInCancelled
import com.jackwallner.aging.model.Person
import com.jackwallner.aging.ui.Format
import com.jackwallner.aging.ui.LocalGraph
import com.jackwallner.aging.ui.LocalNavigator
import com.jackwallner.aging.ui.Route
import com.jackwallner.aging.ui.theme.AgingTheme
import com.jackwallner.aging.ui.theme.Card
import com.jackwallner.aging.ui.theme.DetailTopBar
import com.jackwallner.aging.ui.theme.NavRow
import com.jackwallner.aging.ui.theme.PrimaryButton
import com.jackwallner.aging.ui.theme.RowDivider
import com.jackwallner.aging.ui.theme.ScreenTitle
import com.jackwallner.aging.ui.theme.SectionHeader
import com.jackwallner.aging.ui.theme.Spacing
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID
import kotlinx.coroutines.launch

fun Context.findActivity(): Activity? {
    var current: Context? = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return null
}

/** The circle's people: what the family can see. With no circle, everything on the phone. */
fun AppGraph.circlePeople(): List<Person> {
    val id = groups.activeGroupId ?: return care.state.people
    return care.state.people.filter { it.groupId == id }
}

/** Records only on this phone (never shared, or left behind by a circle this phone is no longer in). */
fun AppGraph.privatePeople(): List<Person> {
    val id = groups.activeGroupId ?: return emptyList()
    return care.state.people.filter { it.groupId != id }
}

/**
 * Sign in, then everything a sign-in makes possible: the RevenueCat customer
 * takes the account id (so a purchase credits the circle), the name Google
 * already gave fills "Your name" if it is empty, and the circle loads.
 */
suspend fun AppGraph.signInWithGoogle(activity: Activity) {
    val session = auth.signIn(activity)
    store.identify(session.userId)
    if (care.state.caregiverName.isBlank() && auth.displayName.isNotBlank()) care.setCaregiverName(auth.displayName)
    groups.refresh()
    groups.loadMembers()
    sync.syncNow()
}

@Composable
private fun SmallPrint(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = AgingTheme.colors.secondaryText,
        modifier = modifier.padding(horizontal = Spacing.lg + 4.dp, vertical = Spacing.sm),
    )
}

@Composable
private fun ErrorDialog(message: String?, onDismiss: () -> Unit) {
    if (message == null) return
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Something went wrong") },
        text = { Text(message) },
        confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
    )
}

/** Google's neutral sign-in button: the G mark and "Sign in with Google", nothing restyled. */
@Composable
fun GoogleSignInButton(enabled: Boolean = true, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(14.dp),
        border = BorderStroke(1.dp, AgingTheme.colors.separator),
        modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag("signin.google"),
    ) {
        Image(painterResource(R.drawable.ic_google_g), contentDescription = null, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(Spacing.md))
        Text("Sign in with Google", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Medium), color = AgingTheme.colors.text)
    }
}

/** Port of `SignInView` for Android: Google only, with the purpose said plainly. */
@Composable
fun SignInPanel(headline: String, detail: String, onSignedIn: () -> Unit = {}) {
    val graph = LocalGraph.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.xl), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(headline, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold), color = AgingTheme.colors.text, textAlign = TextAlign.Center)
        Spacer(Modifier.height(Spacing.sm))
        Text(detail, style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.secondaryText, textAlign = TextAlign.Center)
        Spacer(Modifier.height(Spacing.xl))
        if (graph.auth.canSignIn) {
            GoogleSignInButton(enabled = !working) {
                val activity = context.findActivity() ?: return@GoogleSignInButton
                working = true
                error = null
                scope.launch {
                    try {
                        graph.signInWithGoogle(activity)
                        onSignedIn()
                    } catch (_: SignInCancelled) {
                        // Backing out is not a failure worth showing.
                    } catch (e: Exception) {
                        error = e.message ?: "Sign-in did not work. Please try again."
                    } finally {
                        working = false
                    }
                }
            }
            if (working) {
                Spacer(Modifier.height(Spacing.md))
                CircularProgressIndicator(Modifier.size(28.dp))
            }
            error?.let {
                Spacer(Modifier.height(Spacing.sm))
                Text(it, style = MaterialTheme.typography.bodySmall, color = AgingTheme.colors.danger, textAlign = TextAlign.Center, modifier = Modifier.testTag("signin.error"))
            }
            Spacer(Modifier.height(Spacing.md))
            Text("No password. Your saved care record still opens with no signal.", style = MaterialTheme.typography.bodySmall, color = AgingTheme.colors.secondaryText, textAlign = TextAlign.Center)
        } else {
            Text(
                "Sign-in is not available in this build, so the record stays on this phone.",
                style = MaterialTheme.typography.bodyMedium,
                color = AgingTheme.colors.secondaryText,
                textAlign = TextAlign.Center,
                modifier = Modifier.testTag("signin.unavailable"),
            )
        }
    }
}

// MARK: - The Sharing tab

/** Port of `FamilyView`. Every control mirrors an RLS policy; none of them is the enforcement. */
@Composable
fun SharingScreen() {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val groups = graph.groups
    val scope = rememberCoroutineScope()
    var error by remember { mutableStateOf<String?>(null) }
    var confirmSharing by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf(false) }
    var leaving by remember { mutableStateOf(false) }

    LaunchedEffect(graph.auth.isSignedIn, groups.activeGroupId) {
        if (!graph.auth.isSignedIn) return@LaunchedEffect
        groups.refresh()
        groups.loadMembers()
        groups.loadPendingInvites()
    }

    fun createCircle() = scope.launch {
        try {
            val first = graph.care.state.people.firstOrNull()
            val name = when {
                first == null -> "Care circle"
                first.isSelf -> "My care circle"
                else -> "${first.displayLabel}'s care circle"
            }
            groups.createGroup(name)
            groups.loadMembers()
            graph.sync.syncNow()
        } catch (e: Exception) {
            error = e.message
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ScreenTitle("Sharing")
        when {
            !graph.auth.isSignedIn -> {
                Spacer(Modifier.height(Spacing.md))
                SignInPanel(
                    headline = "Share the record with family",
                    detail = "Everything you have entered is on this phone. Sign in to back it up and share it with family.",
                )
                Spacer(Modifier.height(Spacing.lg))
                Card { NavRow("I have an invitation", "A code or link from someone in the family", Icons.Filled.MarkEmailRead, modifier = Modifier.testTag("sharing.join"), onClick = { navigator.push(Route.Join(null)) }) }
                SmallPrint("Care records work with no account and no signal. Sharing needs an account.")
            }
            groups.activeGroupId == null -> {
                SectionHeader("Sharing")
                Card {
                    NavRow("Start a care circle", "Invite family to see and update the same record", Icons.Filled.GroupAdd, modifier = Modifier.testTag("sharing.start"), onClick = {
                        if (graph.care.state.people.any { !it.isSelf && it.surrogateAttestedAt == null }) confirmSharing = true else createCircle()
                    })
                    RowDivider()
                    NavRow("I have an invitation", "A code or link from someone in the family", Icons.Filled.MarkEmailRead, modifier = Modifier.testTag("sharing.join"), onClick = { navigator.push(Route.Join(null)) })
                }
                SmallPrint("You are not sharing with anyone yet. Signed in as ${graph.auth.displayName.ifEmpty { "your Google account" }}.")
            }
            else -> {
                MembersSection(onRename = if (groups.role == GroupRole.OWNER) ({ renaming = true }) else null)
                if (groups.role.isStaff) {
                    Spacer(Modifier.height(Spacing.md))
                    Card {
                        NavRow("Invite someone", null, Icons.Filled.PersonAdd, modifier = Modifier.testTag("sharing.invite"), onClick = { navigator.push(Route.Invite) })
                    }
                    SmallPrint(
                        if (groups.role == GroupRole.OWNER) "Enter an email address, or share a link or code. Invitations last 48 hours."
                        else "Invite by email, link, or code. Helpers cannot invite organizers.",
                    )
                    if (groups.pendingInvites.isNotEmpty()) PendingInvitesSection { error = it }
                }
                Spacer(Modifier.height(Spacing.md))
                Card {
                    if (groups.role == GroupRole.SUBJECT) {
                        NavRow("Who can see me", null, Icons.Filled.Visibility, onClick = { navigator.push(Route.Transparency) })
                        RowDivider()
                    }
                    val onlyOwner = groups.role == GroupRole.OWNER && groups.members.size <= 1
                    NavRow(
                        if (onlyOwner) "Delete this group" else "Leave this group",
                        null,
                        Icons.AutoMirrored.Filled.ExitToApp,
                        tint = AgingTheme.colors.danger,
                        modifier = Modifier.testTag("sharing.leave"),
                        onClick = { leaving = true },
                    )
                }
            }
        }
        Spacer(Modifier.height(Spacing.xl))
    }

    if (confirmSharing) {
        SharingConsentDialog(
            people = graph.care.state.people,
            onConfirm = {
                confirmSharing = false
                val now = Instant.now()
                graph.care.update { s -> s.copy(people = s.people.map { if (!it.isSelf && it.surrogateAttestedAt == null) it.copy(surrogateAttestedAt = now) else it }) }
                createCircle()
            },
            onDismiss = { confirmSharing = false },
        )
    }
    if (renaming) {
        var name by remember { mutableStateOf(groups.groupName) }
        AlertDialog(
            onDismissRequest = { renaming = false },
            title = { Text("Group name") },
            text = { OutlinedTextField(name, { name = it }, singleLine = true, modifier = Modifier.testTag("sharing.rename.field")) },
            confirmButton = {
                TextButton(onClick = {
                    renaming = false
                    scope.launch { runCatching { groups.rename(name) }.onFailure { error = it.message } }
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { renaming = false }) { Text("Cancel") } },
        )
    }
    if (leaving) LeaveDialog(onDone = { leaving = false }, onError = { error = it })
    ErrorDialog(error) { error = null }
}

@Composable
private fun MembersSection(onRename: (() -> Unit)?) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val groups = graph.groups
    val people = graph.circlePeople()
    Row(verticalAlignment = Alignment.CenterVertically) {
        SectionHeader(groups.groupName.ifEmpty { "Care circle" }, Modifier.weight(1f))
        if (onRename != null) {
            TextButton(onClick = onRename, modifier = Modifier.padding(end = Spacing.sm).testTag("sharing.rename")) { Text("Rename") }
        }
    }
    Card {
        if (groups.members.isEmpty()) {
            NavRow("Loading the member list", "Shown here once this phone reaches the server.", onClick = null)
        }
        groups.members.forEachIndexed { index, member ->
            if (index > 0) RowDivider()
            val editable = groups.role == GroupRole.OWNER && !member.isSelf
            NavRow(
                member.resolvedName,
                memberSubtitle(member, people),
                modifier = Modifier.testTag("sharing.member.$index"),
                onClick = if (editable) ({ navigator.push(Route.Member(member.id)) }) else null,
            )
        }
    }
    SmallPrint(
        if (people.size > 1) "Helpers can see and update everyone under Care unless you narrow it. A person invited to their own record sees only themselves."
        else "Helpers can see and update every person under Care. A person invited to their own record sees only themselves.",
    )
}

private fun memberSubtitle(member: GroupMember, people: List<Person>): String {
    if (member.accessScope != AccessScope.LISTED) return member.role.label
    val names = people.filter { it.id in member.visibleRecipientIds }.map { it.displayLabel }
    return if (names.isEmpty()) "${member.role.label} · no one yet" else "${member.role.label} · ${names.joinToString(", ")} only"
}

@Composable
private fun PendingInvitesSection(onError: (String) -> Unit) {
    val graph = LocalGraph.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val people = graph.care.state.people
    SectionHeader("Pending invitations")
    Card {
        graph.groups.pendingInvites.forEachIndexed { index, invite ->
            if (index > 0) RowDivider()
            val personName = invite.recipientId?.let { id -> people.firstOrNull { it.id == id }?.displayLabel }
            val expired = invite.isExpired()
            Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.lg, vertical = Spacing.md).testTag("sharing.pending.$index")) {
                Text(invite.email ?: "Code ${invite.code}", style = MaterialTheme.typography.bodyLarge, color = AgingTheme.colors.text)
                Text(
                    inviteDetail(invite, personName),
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (expired) AgingTheme.colors.danger else AgingTheme.colors.secondaryText,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    // A dead code is worse than none: whoever gets it is told it did not work.
                    if (!expired) {
                        invite.email?.let { email ->
                            InviteMessage.emailUri(email, invite.code, invite.role, personName)?.let { uri ->
                                TextButton(onClick = { openMail(context, uri) }) { Text("Email again") }
                            }
                        }
                        TextButton(onClick = { shareText(context, InviteMessage.text(invite.code, invite.role, personName)) }) { Text("Share") }
                    }
                    TextButton(onClick = {
                        scope.launch { runCatching { graph.groups.revokeInviteCode(invite.code) }.onFailure { onError(it.message.orEmpty()) } }
                    }) { Text(if (expired) "Remove" else "Revoke", color = AgingTheme.colors.danger) }
                }
            }
        }
    }
}

private val dateTime: DateTimeFormatter = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)

private fun inviteDetail(invite: PendingInvite, personName: String?): String {
    val recipient = personName?.let { " for $it" }.orEmpty()
    if (invite.isExpired()) return "Expired, ${invite.role.label.lowercase()}$recipient"
    return "${invite.role.label}$recipient, expires ${dateTime.format(invite.expiresAt.atZone(Format.zone))}"
}

fun shareText(context: Context, text: String) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    context.startActivity(Intent.createChooser(send, "Share the invitation"))
}

/** Elderhub has no mail server: this writes the email and hands it to the mail app, where the person presses send. */
fun openMail(context: Context, uri: String) {
    runCatching { context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse(uri))) }
}

@Composable
private fun SharingConsentDialog(people: List<Person>, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    var permitted by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Before you share") },
        text = {
            Column {
                Text("Starting a care circle uploads the saved records for ${people.joinToString(", ") { it.displayLabel }} so invited family can use the same information.")
                Spacer(Modifier.height(Spacing.sm))
                Text("Every helper you invite can see and update every person in this care circle. A person invited to their own record sees only themselves.")
                Row(Modifier.fillMaxWidth().clickable { permitted = !permitted }.padding(top = Spacing.md), verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = permitted, onCheckedChange = { permitted = it }, modifier = Modifier.testTag("sharing.consent.toggle"))
                    Text("I have permission to keep and share this care information.")
                }
            }
        },
        confirmButton = { TextButton(onClick = onConfirm, enabled = permitted, modifier = Modifier.testTag("sharing.consent.confirm")) { Text("Start care circle") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** Port of `LeaveOrDeleteView`: the last organizer hands over first; a circle of one is deleted. */
@Composable
private fun LeaveDialog(onDone: () -> Unit, onError: (String) -> Unit) {
    val graph = LocalGraph.current
    val groups = graph.groups
    val scope = rememberCoroutineScope()
    val isOnlyMember = groups.members.size <= 1
    val isLastOwner = groups.role == GroupRole.OWNER && groups.members.count { it.role == GroupRole.OWNER } <= 1
    val (title, message, action) = when {
        isLastOwner && !isOnlyMember -> Triple("Leave this group", "You are the only organizer. Make someone else the organizer first, then you can leave.", null)
        isOnlyMember && groups.role == GroupRole.OWNER -> Triple(
            "Delete this group?",
            "Nobody else is in it, so the shared copy of the record goes with it. What is on this phone stays on this phone.",
            "Delete",
        )
        else -> Triple("Leave this group?", "The others keep the record. You stop seeing it on this phone.", "Leave")
    }
    AlertDialog(
        onDismissRequest = onDone,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = {
            if (action != null) {
                TextButton(modifier = Modifier.testTag("sharing.leave.confirm"), onClick = {
                    onDone()
                    scope.launch {
                        try {
                            if (action == "Delete") {
                                // Keep this phone's copy: what was here before the circle stays here.
                                val keep = graph.care.state
                                groups.deleteGroup()
                                graph.care.applyRemote { keep.copy(people = keep.people.map { it.copy(groupId = null) }, sync = it.sync) }
                            } else {
                                groups.leaveGroup()
                            }
                        } catch (e: Exception) {
                            onError(e.message.orEmpty())
                        }
                    }
                }) { Text(action, color = AgingTheme.colors.danger) }
            } else {
                TextButton(onClick = onDone) { Text("OK") }
            }
        },
        dismissButton = if (action != null) ({ TextButton(onClick = onDone) { Text("Cancel") } }) else null,
    )
}

// MARK: - Joining

/** Port of `JoinGroupView`: sign in if needed, then the eight-character code. */
@Composable
fun JoinCircleScreen(initialCode: String?, onBack: (() -> Unit)?, onJoined: (GroupRole) -> Unit) {
    val graph = LocalGraph.current
    val scope = rememberCoroutineScope()
    var code by rememberSaveable { mutableStateOf(initialCode.orEmpty()) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(initialCode) { if (!initialCode.isNullOrEmpty()) code = initialCode }
    val cleaned = code.uppercase().filter { it.isLetterOrDigit() }

    Column(Modifier.fillMaxSize().imePadding()) {
        if (onBack != null) DetailTopBar("Join a Care Circle", onBack = onBack)
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = Spacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (!graph.auth.isSignedIn) {
                SignInPanel(
                    headline = "Join the care circle",
                    detail = "After signing in, the invitation link or code connects you to the right care circle.",
                )
                if (cleaned.length == InviteLink.CODE_LENGTH) {
                    Spacer(Modifier.height(Spacing.lg))
                    Text("Your code $cleaned is kept for after you sign in.", style = MaterialTheme.typography.bodySmall, color = AgingTheme.colors.secondaryText)
                }
                return@Column
            }
            Icon(Icons.Filled.MarkEmailRead, contentDescription = null, tint = AgingTheme.colors.accent, modifier = Modifier.size(52.dp))
            Spacer(Modifier.height(Spacing.md))
            Text("Enter your code", style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold), color = AgingTheme.colors.text)
            Spacer(Modifier.height(Spacing.sm))
            Text(
                "Eight letters and numbers, from whoever invited you.",
                style = MaterialTheme.typography.bodyMedium,
                color = AgingTheme.colors.secondaryText,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 28.dp),
            )
            Spacer(Modifier.height(Spacing.xl))
            OutlinedTextField(
                value = code,
                onValueChange = { code = it },
                singleLine = true,
                placeholder = { Text("ABCD2345", style = codeStyle) },
                textStyle = codeStyle.copy(color = AgingTheme.colors.text),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false, keyboardType = KeyboardType.Ascii),
                modifier = Modifier.padding(horizontal = 28.dp).fillMaxWidth().testTag("join.code"),
            )
            error?.let {
                Spacer(Modifier.height(Spacing.md))
                Text(it, style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.danger, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 28.dp).testTag("join.error"))
            }
            Spacer(Modifier.height(Spacing.xl))
            PrimaryButton(
                if (working) "Joining…" else "Join",
                enabled = cleaned.length == InviteLink.CODE_LENGTH && !working,
                modifier = Modifier.padding(horizontal = 28.dp).testTag("join.submit"),
            ) {
                working = true
                error = null
                scope.launch {
                    try {
                        graph.groups.acceptInvite(cleaned)
                        if (graph.groups.role != GroupRole.SUBJECT) graph.sync.syncNow()
                        onJoined(graph.groups.role)
                    } catch (e: Exception) {
                        error = e.message
                    } finally {
                        working = false
                    }
                }
            }
        }
    }
}

private val codeStyle = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 26.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)

// MARK: - Inviting

/** Port of `InviteSheet`: a caregiver sees everyone; the person being looked after is linked to their own record. */
@Composable
fun InviteScreen() {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val people = graph.circlePeople()
    var subject by rememberSaveable { mutableStateOf(false) }
    var recipientId by remember { mutableStateOf<UUID?>(null) }
    var email by rememberSaveable { mutableStateOf("") }
    var code by rememberSaveable { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val normalizedEmail = email.trim().lowercase()
    val emailValid = normalizedEmail.isEmpty() || InviteLink.isValidEmail(normalizedEmail)
    val role = if (subject) GroupRole.SUBJECT else GroupRole.CAREGIVER
    val personName = recipientId?.let { id -> people.firstOrNull { it.id == id }?.displayLabel }

    Column(Modifier.fillMaxSize().imePadding()) {
        DetailTopBar("Invite", onBack = navigator::pop)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            val ready = code
            if (ready != null) {
                SectionHeader("Invitation ready")
                Card {
                    Text(
                        ready,
                        style = codeStyle.copy(fontSize = 34.sp, color = AgingTheme.colors.text),
                        modifier = Modifier.fillMaxWidth().padding(vertical = Spacing.lg).testTag("invite.code"),
                    )
                    RowDivider()
                    InviteMessage.emailUri(normalizedEmail, ready, role, personName)?.let { uri ->
                        NavRow("Write the email to $normalizedEmail", null, Icons.Filled.Email, onClick = { openMail(context, uri) })
                        RowDivider()
                    }
                    NavRow(
                        if (normalizedEmail.isEmpty()) "Share the invitation" else "Share another way",
                        null,
                        Icons.Filled.Share,
                        modifier = Modifier.testTag("invite.share"),
                        onClick = { shareText(context, InviteMessage.text(ready, role, personName)) },
                    )
                }
                SmallPrint(
                    if (normalizedEmail.isEmpty()) "Good for 48 hours, and works once. You can read it out over the phone."
                    else "Nothing has been sent yet. Good for 48 hours, and works once.",
                )
                return@Column
            }

            SectionHeader("Who are you inviting?")
            Card {
                KindRow("Another caregiver", "A brother, sister or partner. They see and edit everyone in the family.", !subject, "invite.kind.caregiver") { subject = false }
                RowDivider()
                KindRow("The person being looked after", "They see only their own list and mark their own doses.", subject, "invite.kind.subject") { subject = true }
            }
            if (subject) {
                SectionHeader("Link them to")
                Card {
                    val linkable = people.filter { it.linkedUserId == null }
                    if (linkable.isEmpty()) NavRow("Everyone you track already has an account linked.", null, onClick = null)
                    linkable.forEachIndexed { index, person ->
                        if (index > 0) RowDivider()
                        KindRow(person.displayLabel, null, recipientId == person.id, "invite.recipient.$index") { recipientId = person.id }
                    }
                }
                SmallPrint("They join the record you already built, so the medication history carries over.")
            }
            SectionHeader("Send to")
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("Email address") },
                singleLine = true,
                isError = !emailValid,
                supportingText = if (!emailValid) ({ Text("Enter a valid email address.") }) else null,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth().padding(horizontal = Spacing.lg).testTag("invite.email"),
            )
            SmallPrint("Optional. Elderhub does not send the email for you: it writes it and hands it to your mail app, so you press send. You can also share the link or read the code out.")
            error?.let { SmallPrint(it, Modifier.testTag("invite.error")) }
            PrimaryButton(
                if (working) "Creating…" else "Create invitation",
                enabled = !working && emailValid && (!subject || recipientId != null),
                modifier = Modifier.padding(Spacing.lg).testTag("invite.create"),
            ) {
                working = true
                error = null
                scope.launch {
                    try {
                        code = graph.groups.generateInviteCode(role, recipientId, normalizedEmail.ifEmpty { null })
                    } catch (e: Exception) {
                        error = e.message
                    } finally {
                        working = false
                    }
                }
            }
        }
    }
}

@Composable
private fun KindRow(title: String, detail: String?, selected: Boolean, tag: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).testTag(tag).padding(horizontal = Spacing.lg, vertical = Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium), color = AgingTheme.colors.text)
            if (detail != null) Text(detail, style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.secondaryText)
        }
        RadioButton(selected = selected, onClick = onClick)
    }
}

// MARK: - One member

/** Port of `MemberSheet`: role, who they can see, organizer hand-over and removal. Owner only. */
@Composable
fun MemberScreen(memberId: UUID) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val scope = rememberCoroutineScope()
    val member = graph.groups.members.firstOrNull { it.id == memberId } ?: run { navigator.pop(); return }
    val people = graph.circlePeople()
    var pendingRole by remember { mutableStateOf<GroupRole?>(null) }
    var confirmRemove by remember { mutableStateOf(false) }
    var confirmTransfer by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var scopeChoice by remember(member) { mutableStateOf(member.accessScope) }
    var granted by remember(member) { mutableStateOf(member.visibleRecipientIds) }

    fun run(block: suspend () -> Unit, popAfter: Boolean = true) = scope.launch {
        try {
            block()
            if (popAfter) navigator.pop()
        } catch (e: Exception) {
            error = e.message
            scopeChoice = member.accessScope
            granted = member.visibleRecipientIds
        }
    }

    fun saveAccess() = run({ graph.groups.setAccess(member.id, scopeChoice, granted) }, popAfter = false)

    Column(Modifier.fillMaxSize()) {
        DetailTopBar(member.resolvedName, onBack = navigator::pop)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            SectionHeader("Role")
            Card {
                listOf(
                    GroupRole.CAREGIVER to "Sees and edits everyone in the family.",
                    GroupRole.SUBJECT to "Sees only their own list, and marks their own doses.",
                ).forEachIndexed { index, (option, detail) ->
                    if (index > 0) RowDivider()
                    KindRow(option.label, detail, member.role == option, "member.role.${option.raw}") { if (option != member.role) pendingRole = option }
                }
            }
            if (member.canBeRestricted && people.size > 1) {
                SectionHeader("Can see")
                Card {
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(Spacing.md)) {
                        listOf(AccessScope.ALL to "Everyone", AccessScope.LISTED to "Only some").forEachIndexed { index, (option, label) ->
                            SegmentedButton(
                                selected = scopeChoice == option,
                                onClick = {
                                    if (scopeChoice == option) return@SegmentedButton
                                    scopeChoice = option
                                    // Starting from everyone ticked is honest: this narrows a permission they already have.
                                    if (option == AccessScope.LISTED && granted.isEmpty()) granted = people.map { it.id }.toSet()
                                    saveAccess()
                                },
                                shape = SegmentedButtonDefaults.itemShape(index, 2),
                                modifier = Modifier.testTag("member.scope.${option.raw}"),
                            ) { Text(label) }
                        }
                    }
                    if (scopeChoice == AccessScope.LISTED) {
                        people.forEach { person ->
                            RowDivider()
                            Row(
                                Modifier.fillMaxWidth().clickable {
                                    granted = if (person.id in granted) granted - person.id else granted + person.id
                                    saveAccess()
                                }.padding(horizontal = Spacing.lg, vertical = Spacing.md),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(person.displayLabel, Modifier.weight(1f), color = AgingTheme.colors.text)
                                if (person.id in granted) Icon(Icons.Filled.Check, contentDescription = "Can see", tint = AgingTheme.colors.accent)
                            }
                        }
                    }
                }
                SmallPrint(
                    if (scopeChoice == AccessScope.ALL) "${member.resolvedName} can see and update everyone in this circle."
                    else "${member.resolvedName} can only open the people ticked here. The database refuses them everything else, and their app clears what it already downloaded the next time it reaches the server.",
                )
            }
            Spacer(Modifier.height(Spacing.md))
            Card { NavRow("Make organizer", "There is one organizer. Handing it over makes you a caregiver.", modifier = Modifier.testTag("member.transfer"), onClick = { confirmTransfer = true }) }
            Spacer(Modifier.height(Spacing.md))
            Card { NavRow("Remove from the group", null, tint = AgingTheme.colors.danger, modifier = Modifier.testTag("member.remove"), onClick = { confirmRemove = true }) }
            error?.let { SmallPrint(it) }
            Spacer(Modifier.height(Spacing.xl))
        }
    }

    pendingRole?.let { option ->
        Confirm(
            "Change ${member.resolvedName} to ${option.label}?",
            if (option == GroupRole.SUBJECT) "They will see only their own list on their own phone, and everyone else's records come off it."
            else "They will see and be able to edit everyone in the family.",
            "Change",
            onConfirm = { pendingRole = null; run({ graph.groups.changeRole(member.id, option) }) },
            onDismiss = { pendingRole = null },
        )
    }
    if (confirmRemove) {
        Confirm("Remove ${member.resolvedName}?", "They lose access straight away. Anything they entered stays in the family record.", "Remove",
            onConfirm = { confirmRemove = false; run({ graph.groups.removeMember(member.id) }) }, onDismiss = { confirmRemove = false })
    }
    if (confirmTransfer) {
        Confirm("Make ${member.resolvedName} the organizer?", "You become a caregiver and can no longer change roles or billing.", "Hand over",
            onConfirm = { confirmTransfer = false; run({ graph.groups.transferOwnership(member.id) }) }, onDismiss = { confirmTransfer = false })
    }
}

@Composable
private fun Confirm(title: String, message: String, action: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = { TextButton(onClick = onConfirm, modifier = Modifier.testTag("confirm.action")) { Text(action) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

// MARK: - Transparency, for the person being looked after

/** Port of `TransparencyView`: who can see them and what, before anything syncs to their phone. */
@Composable
fun TransparencyScreen(isOnboarding: Boolean, onAccepted: () -> Unit = {}) {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val scope = rememberCoroutineScope()
    var leaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxSize()) {
        if (!isOnboarding) DetailTopBar("Who can see you", onBack = navigator::pop)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            if (isOnboarding) ScreenTitle("Who can see you")
            SmallPrint("You have joined ${graph.groups.groupName.ifEmpty { "a care circle" }}.")
            Card {
                graph.groups.members.filter { !it.isSelf }.forEachIndexed { index, member ->
                    if (index > 0) RowDivider()
                    NavRow(member.resolvedName, member.role.label, onClick = null)
                }
                if (graph.groups.members.none { !it.isSelf }) NavRow("Nobody else yet", "The list appears once this phone reaches the server.", onClick = null)
            }
            Bullets("What they can see", Icons.Filled.Visibility, listOf(
                "Your medications, and when a dose was marked taken or skipped",
                "Your allergies, conditions and emergency contacts",
                "Doctor visits, and the doctors and pharmacies saved for you",
                "Notes, readings, to-dos and bills the family keeps about you, on the iPhone app",
                "When you last pressed your check-in button",
            ))
            Bullets("What they cannot see", Icons.Filled.VisibilityOff, listOf(
                "Where you are. This app has no location and never asks for it",
                "Anything from the rest of your phone",
                "Your Google account, beyond the name on it",
            ))
            Bullets("What you can do", Icons.Filled.PanTool, listOf(
                "Mark your own doses",
                "See this page any time",
                "Leave the group whenever you want",
            ))
            SmallPrint(MEDICAL_DISCLAIMER)
            Column(Modifier.padding(Spacing.lg)) {
                if (isOnboarding) {
                    PrimaryButton("I understand", modifier = Modifier.testTag("transparency.accept")) {
                        graph.groups.markTransparencyAccepted()
                        onAccepted()
                        scope.launch { graph.sync.syncNow() }
                    }
                } else {
                    OutlinedButton(onClick = { leaving = true }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                        Text("Leave this group", color = AgingTheme.colors.danger)
                    }
                }
            }
        }
    }
    if (leaving) {
        Confirm("Leave this group?", "The others keep the record. You stop seeing it on this phone.", "Leave", onConfirm = {
            leaving = false
            scope.launch { runCatching { graph.groups.leaveGroup() }.onFailure { error = it.message } }
        }, onDismiss = { leaving = false })
    }
    ErrorDialog(error) { error = null }
}

@Composable
private fun Bullets(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, lines: List<String>) {
    SectionHeader(title)
    Card {
        lines.forEachIndexed { index, line ->
            if (index > 0) RowDivider()
            Row(Modifier.padding(horizontal = Spacing.lg, vertical = Spacing.md), verticalAlignment = Alignment.Top) {
                Icon(icon, contentDescription = null, tint = AgingTheme.colors.accent, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(Spacing.md))
                Text(line, style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.text)
            }
        }
    }
}

// MARK: - Conflicts

/** Port of `ConflictsView`: both versions side by side, and a person chooses. */
@Composable
fun ConflictsScreen() {
    val graph = LocalGraph.current
    val navigator = LocalNavigator.current
    val scope = rememberCoroutineScope()
    val conflicts = graph.sync.conflicts()
    Column(Modifier.fillMaxSize()) {
        DetailTopBar("Needs a look", onBack = navigator::pop)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            if (conflicts.isEmpty()) SmallPrint("Nothing is waiting on a decision.")
            conflicts.forEachIndexed { index, conflict ->
                SectionHeader(listOf(conflict.entity.label, conflict.personName).filter { it.isNotEmpty() }.joinToString(" · "))
                Card {
                    Column(Modifier.padding(Spacing.lg).testTag("conflict.$index")) {
                        Text(conflict.title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = AgingTheme.colors.text)
                        if (conflict.localSummary.isNotEmpty()) {
                            Spacer(Modifier.height(Spacing.sm))
                            Text("On this phone", style = MaterialTheme.typography.labelMedium, color = AgingTheme.colors.secondaryText)
                            Text(conflict.localSummary, style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.text)
                        }
                        if (conflict.remoteSummary.isNotEmpty()) {
                            Spacer(Modifier.height(Spacing.sm))
                            Text("From the family", style = MaterialTheme.typography.labelMedium, color = AgingTheme.colors.secondaryText)
                            Text(conflict.remoteSummary, style = MaterialTheme.typography.bodyMedium, color = AgingTheme.colors.text)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), modifier = Modifier.padding(top = Spacing.sm)) {
                            TextButton(onClick = { scope.launch { graph.sync.resolveKeepingLocal(conflict.id) } }, modifier = Modifier.testTag("conflict.keep")) { Text("Keep mine") }
                            TextButton(onClick = { scope.launch { graph.sync.resolveTakingRemote(conflict.id) } }, modifier = Modifier.testTag("conflict.theirs")) { Text("Use theirs") }
                        }
                    }
                }
            }
            Spacer(Modifier.height(Spacing.xl))
        }
    }
}
