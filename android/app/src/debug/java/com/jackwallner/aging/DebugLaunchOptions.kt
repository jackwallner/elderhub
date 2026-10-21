package com.jackwallner.aging

import android.content.Intent
import com.jackwallner.aging.data.GroupRole
import kotlinx.coroutines.runBlocking
import com.jackwallner.aging.data.PackageKind
import com.jackwallner.aging.data.PeriodUnit
import com.jackwallner.aging.data.Plan
import com.jackwallner.aging.data.PlanPeriod
import com.jackwallner.aging.model.SampleData

/**
 * Debug-only launch extras, the Android side of the iOS launch arguments.
 * None of this is compiled into a release or QA build.
 *
 *     adb shell am start -n com.jackwallner.aging/.MainActivity \
 *         --ez resetAll true --ez seedDemo true --ez seedDad true --ez demoPro true --ei tab 1
 *
 * Sharing runs against [FakeCareServer] with `fakeCloud` (no network, no
 * Google account): `fakeSignedIn` signs the made-up account in, `fakeCircle`
 * starts a circle from the seeded record with a sibling in it, `fakeInvite`
 * seeds somebody else's circle and opens its invitation, `fakeOffline` makes
 * every request fail as airplane mode would.
 */
object DebugLaunchOptions {
    var launchTab: Int? = null
        private set
    var openPaywall: Boolean = false
        private set

    fun apply(graph: AppGraph, intent: Intent?) {
        val extras = intent?.extras ?: return
        if (extras.getBoolean("resetAll")) {
            graph.care.reset()
            graph.defaults.keys().forEach(graph.defaults::remove)
        }
        if (extras.getBoolean("fakeCloud")) graph.cloud = FakeCareServer.shared.cloud()
        if (extras.getBoolean("demoPro")) graph.store.forceProForDebug()
        if (extras.getBoolean("previewStore")) {
            graph.store.loadPreviewPlans(previewPlans(extras.getInt("previewTrialDays", 7)), history = extras.getBoolean("previewTrialUsed"))
        }
        if (extras.getBoolean("seedDemo")) {
            val mom = SampleData.mom()
            graph.care.update { if (extras.getBoolean("seedDad")) SampleData.withDad(mom) else mom }
        }
        val server = FakeCareServer.shared
        if (extras.getBoolean("fakeCloud") && extras.getBoolean("fakeSignedIn")) {
            runBlocking {
                graph.auth.bootstrap()
                if (!graph.auth.isSignedIn) {
                    server.signInWithIdToken("google", "fake-id-token", "fake-nonce")
                    server.updateDisplayName(server.signInAs.id, server.signInAs.name)
                    server.rememberDisplayName(server.signInAs.name)
                    graph.care.setCaregiverName(server.signInAs.name)
                }
                graph.auth.bootstrap()
                graph.groups.loadFromCache()
                if (extras.getBoolean("fakeCircle") && graph.groups.activeGroupId == null) {
                    val first = graph.care.state.people.firstOrNull()
                    val id = graph.groups.createGroup(first?.let { "${it.displayLabel}'s care circle" } ?: "Care circle")
                    server.addSibling(id)
                    graph.groups.loadMembers()
                    graph.sync.syncNow()
                    if (extras.getBoolean("fakePendingInvite")) graph.groups.generateInviteCode(GroupRole.CAREGIVER, null, "michael@example.com")
                }
            }
        }
        if (extras.getBoolean("fakeCloud") && extras.getBoolean("fakeInvite")) {
            graph.pendingInviteCode = server.seedSarahsCircle()
        }
        if (extras.getBoolean("fakeOffline")) server.isOnline = false
        if (extras.containsKey("tab")) launchTab = extras.getInt("tab")
        openPaywall = extras.getBoolean("openPaywall")
    }

    /** The proposed Android US ladder (iOS 9.99/39.99/89.99 less about 20%), so the real paywall renders without a store. */
    private fun previewPlans(trialDays: Int): List<Plan> {
        val trial = if (trialDays > 0) PlanPeriod(trialDays, PeriodUnit.DAY) else null
        return listOf(
            Plan("\$rc_monthly", "com.jackwallner.aging.pro.monthly:monthly", PackageKind.MONTHLY, 7_990_000, "$7.99", "USD", PlanPeriod(1, PeriodUnit.MONTH), trial, "Monthly"),
            Plan("\$rc_annual", "com.jackwallner.aging.pro.yearly:yearly", PackageKind.YEARLY, 31_990_000, "$31.99", "USD", PlanPeriod(1, PeriodUnit.YEAR), trial, "Yearly"),
            Plan("\$rc_lifetime", "com.jackwallner.aging.pro.lifetime", PackageKind.LIFETIME, 71_990_000, "$71.99", "USD", null, null, "Lifetime"),
        )
    }
}
