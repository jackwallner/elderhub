package com.jackwallner.aging.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.jackwallner.aging.AppGraph
import com.jackwallner.aging.DebugLaunchOptions
import com.jackwallner.aging.data.GroupRole
import com.jackwallner.aging.ui.screens.ConflictsScreen
import com.jackwallner.aging.ui.screens.InviteScreen
import com.jackwallner.aging.ui.screens.JoinCircleScreen
import com.jackwallner.aging.ui.screens.MemberScreen
import com.jackwallner.aging.ui.screens.SharingScreen
import com.jackwallner.aging.ui.screens.TransparencyScreen
import com.jackwallner.aging.ui.screens.CareScreen
import com.jackwallner.aging.ui.screens.ContactEditorScreen
import com.jackwallner.aging.ui.screens.ContactsScreen
import com.jackwallner.aging.ui.screens.EmergencyCardScreen
import com.jackwallner.aging.ui.screens.MedicationEditorScreen
import com.jackwallner.aging.ui.screens.MedicationsScreen
import com.jackwallner.aging.ui.screens.OnboardingScreen
import com.jackwallner.aging.ui.screens.PaywallScreen
import com.jackwallner.aging.ui.screens.PersonDetailsEditorScreen
import com.jackwallner.aging.ui.screens.PersonHubScreen
import com.jackwallner.aging.ui.screens.ProviderEditorScreen
import com.jackwallner.aging.ui.screens.ProvidersScreen
import com.jackwallner.aging.ui.screens.SettingsScreen
import com.jackwallner.aging.ui.screens.TodayScreen
import com.jackwallner.aging.ui.screens.VisitEditorScreen
import com.jackwallner.aging.ui.screens.VisitsScreen
import com.jackwallner.aging.ui.theme.AgingTheme
import java.util.UUID

val LocalGraph = staticCompositionLocalOf<AppGraph> { error("No AppGraph") }

/** Every pushed screen. Each tab keeps its own stack, like the iOS NavigationStacks. */
sealed interface Route {
    data class PersonHub(val personId: UUID) : Route
    data class Medications(val personId: UUID) : Route
    data class MedicationEditor(val personId: UUID, val medicationId: UUID?) : Route
    data class Visits(val personId: UUID) : Route
    data class VisitEditor(val personId: UUID, val visitId: UUID?) : Route
    data class Contacts(val personId: UUID) : Route
    data class ContactEditor(val personId: UUID, val contactId: UUID?) : Route
    data class Providers(val personId: UUID) : Route
    data class ProviderEditor(val personId: UUID, val providerId: UUID?) : Route
    data class EmergencyCard(val personId: UUID) : Route
    data class PersonDetails(val personId: UUID?) : Route
    data class Join(val code: String?) : Route
    object Invite : Route
    data class Member(val userId: UUID) : Route
    object Transparency : Route
    object Conflicts : Route
}

class Navigator {
    var tab by mutableIntStateOf(DebugLaunchOptions.launchTab ?: 0)
    private val stacks = List(TAB_COUNT) { mutableStateListOf<Route>() }
    var showPaywall by mutableStateOf(DebugLaunchOptions.openPaywall)

    val stack: List<Route> get() = stacks[tab]

    fun push(route: Route) { stacks[tab].add(route) }

    fun pop() { stacks[tab].removeLastOrNull() }

    fun popTo(predicate: (Route) -> Boolean) {
        val stack = stacks[tab]
        while (stack.isNotEmpty() && !predicate(stack.last())) stack.removeAt(stack.lastIndex)
    }

    fun select(index: Int) {
        if (index == tab) stacks[index].clear() else tab = index
    }

    /** A tapped invitation: the Sharing tab, with the code already in the join screen. */
    fun showJoin(code: String) {
        tab = TAB_SHARING
        stacks[TAB_SHARING].clear()
        stacks[TAB_SHARING].add(Route.Join(code))
    }

    /** Adding a person is the paywall's trigger; everyone else gets the editor. */
    fun requestAddPerson(canAdd: Boolean) {
        if (canAdd) push(Route.PersonDetails(null)) else showPaywall = true
    }
}

const val TAB_SHARING = 2
private const val TAB_COUNT = 4

val LocalNavigator = staticCompositionLocalOf<Navigator> { error("No Navigator") }

@Composable
fun RootScreen(graph: AppGraph) {
    val navigator = remember { Navigator() }
    val state = graph.care.state
    val pendingCode = graph.pendingInviteCode
    // A tapped invitation on a phone with no record yet goes straight to joining (iOS `needsOnboarding`).
    if (!state.hasCompletedOnboarding && pendingCode != null && state.people.isEmpty()) {
        Box(Modifier.fillMaxSize().background(AgingTheme.colors.background).safeDrawingPadding()) {
            JoinCircleScreen(pendingCode, onBack = { graph.pendingInviteCode = null }) { graph.finishJoinOnboarding() }
        }
        return
    }
    if (!state.hasCompletedOnboarding) {
        OnboardingScreen()
        return
    }
    LaunchedEffect(pendingCode) {
        if (pendingCode != null) {
            navigator.showJoin(pendingCode)
            graph.pendingInviteCode = null
        }
    }
    if (graph.groups.requiresTransparency) {
        CompositionLocalProvider(LocalNavigator provides navigator) {
            Box(Modifier.fillMaxSize().background(AgingTheme.colors.background).safeDrawingPadding()) {
                TransparencyScreen(isOnboarding = true)
            }
        }
        return
    }
    val isSubject = graph.groups.role == GroupRole.SUBJECT && graph.groups.activeGroupId != null
    CompositionLocalProvider(LocalNavigator provides navigator) {
        BackHandler(enabled = navigator.stack.isNotEmpty() && !navigator.showPaywall) { navigator.pop() }
        BackHandler(enabled = navigator.stack.isEmpty() && navigator.tab != 0 && !navigator.showPaywall) { navigator.tab = 0 }
        Box(Modifier.fillMaxSize()) {
            Scaffold(
                containerColor = AgingTheme.colors.background,
                bottomBar = { TabBar(navigator, isSubject) },
            ) { padding ->
                Box(Modifier.padding(padding).fillMaxSize().background(AgingTheme.colors.background)) {
                    val top = navigator.stack.lastOrNull()
                    AnimatedContent(
                        targetState = navigator.tab to top,
                        transitionSpec = { fadeIn() togetherWith fadeOut() },
                        label = "route",
                    ) { (tab, route) ->
                        if (route != null) RouteScreen(route) else TabRoot(tab, isSubject)
                    }
                }
            }
            if (navigator.showPaywall) {
                PaywallScreen(onDismiss = { navigator.showPaywall = false })
            }
        }
    }
}

/**
 * The person being looked after gets their own app rather than a caregiver's
 * with parts greyed out: their day, and who can see them. RLS enforces the
 * rest whatever this shows.
 */
@Composable
private fun TabRoot(tab: Int, isSubject: Boolean) {
    if (isSubject) {
        if (tab == 0) TodayScreen() else TransparencyScreen(isOnboarding = false)
        return
    }
    when (tab) {
        0 -> TodayScreen()
        1 -> CareScreen()
        TAB_SHARING -> SharingScreen()
        else -> SettingsScreen()
    }
}

@Composable
private fun RouteScreen(route: Route) {
    when (route) {
        is Route.PersonHub -> PersonHubScreen(route.personId)
        is Route.Medications -> MedicationsScreen(route.personId)
        is Route.MedicationEditor -> MedicationEditorScreen(route.personId, route.medicationId)
        is Route.Visits -> VisitsScreen(route.personId)
        is Route.VisitEditor -> VisitEditorScreen(route.personId, route.visitId)
        is Route.Contacts -> ContactsScreen(route.personId)
        is Route.ContactEditor -> ContactEditorScreen(route.personId, route.contactId)
        is Route.Providers -> ProvidersScreen(route.personId)
        is Route.ProviderEditor -> ProviderEditorScreen(route.personId, route.providerId)
        is Route.EmergencyCard -> EmergencyCardScreen(route.personId)
        is Route.PersonDetails -> PersonDetailsEditorScreen(route.personId)
        is Route.Join -> {
            val navigator = LocalNavigator.current
            JoinCircleScreen(route.code, onBack = navigator::pop) { navigator.pop() }
        }
        Route.Invite -> InviteScreen()
        is Route.Member -> MemberScreen(route.userId)
        Route.Transparency -> TransparencyScreen(isOnboarding = false)
        Route.Conflicts -> ConflictsScreen()
    }
}

@Composable
private fun TabBar(navigator: Navigator, isSubject: Boolean) {
    val colors = AgingTheme.colors
    NavigationBar(containerColor = colors.card) {
        val items = if (isSubject) listOf(
            Triple("Today", Icons.Filled.Checklist, "tab.today"),
            Triple("You", Icons.Filled.Visibility, "tab.you"),
        ) else listOf(
            Triple("Today", Icons.Filled.Checklist, "tab.today"),
            Triple("Care", Icons.Filled.People, "tab.care"),
            Triple("Sharing", Icons.Filled.Groups, "tab.sharing"),
            Triple("Settings", Icons.Filled.Settings, "tab.settings"),
        )
        items.forEachIndexed { index, (label, icon, tag) ->
            NavigationBarItem(
                selected = navigator.tab == index,
                onClick = { navigator.select(index) },
                icon = { Icon(icon, contentDescription = null) },
                label = { Text(label) },
                modifier = Modifier.testTag(tag),
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = colors.accent,
                    selectedTextColor = colors.accent,
                    indicatorColor = colors.accent.copy(alpha = 0.12f),
                    unselectedIconColor = colors.secondaryText,
                    unselectedTextColor = colors.secondaryText,
                ),
            )
        }
    }
}
