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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checklist
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
}

class Navigator {
    var tab by mutableIntStateOf(DebugLaunchOptions.launchTab ?: 0)
    private val stacks = List(3) { mutableStateListOf<Route>() }
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

    /** Adding a person is the paywall's trigger; everyone else gets the editor. */
    fun requestAddPerson(canAdd: Boolean) {
        if (canAdd) push(Route.PersonDetails(null)) else showPaywall = true
    }
}

val LocalNavigator = staticCompositionLocalOf<Navigator> { error("No Navigator") }

@Composable
fun RootScreen(graph: AppGraph) {
    val navigator = remember { Navigator() }
    val state = graph.care.state
    if (!state.hasCompletedOnboarding) {
        OnboardingScreen()
        return
    }
    CompositionLocalProvider(LocalNavigator provides navigator) {
        BackHandler(enabled = navigator.stack.isNotEmpty() && !navigator.showPaywall) { navigator.pop() }
        BackHandler(enabled = navigator.stack.isEmpty() && navigator.tab != 0 && !navigator.showPaywall) { navigator.tab = 0 }
        Box(Modifier.fillMaxSize()) {
            Scaffold(
                containerColor = AgingTheme.colors.background,
                bottomBar = { TabBar(navigator) },
            ) { padding ->
                Box(Modifier.padding(padding).fillMaxSize().background(AgingTheme.colors.background)) {
                    val top = navigator.stack.lastOrNull()
                    AnimatedContent(
                        targetState = navigator.tab to top,
                        transitionSpec = { fadeIn() togetherWith fadeOut() },
                        label = "route",
                    ) { (tab, route) ->
                        if (route != null) RouteScreen(route) else TabRoot(tab)
                    }
                }
            }
            if (navigator.showPaywall) {
                PaywallScreen(onDismiss = { navigator.showPaywall = false })
            }
        }
    }
}

@Composable
private fun TabRoot(tab: Int) {
    when (tab) {
        0 -> TodayScreen()
        1 -> CareScreen()
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
    }
}

@Composable
private fun TabBar(navigator: Navigator) {
    val colors = AgingTheme.colors
    NavigationBar(containerColor = colors.card) {
        val items = listOf(
            Triple("Today", Icons.Filled.Checklist, "tab.today"),
            Triple("Care", Icons.Filled.People, "tab.care"),
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
