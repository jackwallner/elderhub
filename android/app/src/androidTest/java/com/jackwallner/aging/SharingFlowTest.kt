package com.jackwallner.aging

import android.content.Intent
import android.net.Uri
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jackwallner.aging.model.SyncEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Family sharing on a real device, against the debug in-memory backend
 * (`FakeCareServer`): no network, no Google account, no secret. Each test runs
 * in a fresh process (orchestrator `clearPackageData`), so the fake server
 * starts empty every time.
 */
@RunWith(AndroidJUnit4::class)
class SharingFlowTest {
    @get:Rule val compose = createEmptyComposeRule()

    private val server get() = FakeCareServer.shared

    private fun intent(vararg flags: String, tab: Int? = null, reset: Boolean = true): Intent {
        val intent = Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java)
            .putExtra("resetAll", reset)
            .putExtra("previewStore", true)
            .putExtra("fakeCloud", true)
        flags.forEach { intent.putExtra(it, true) }
        tab?.let { intent.putExtra("tab", it) }
        return intent
    }

    private fun waitForTag(tag: String, timeout: Long = 30_000) =
        compose.waitUntil(timeout) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }

    private fun waitForText(text: String, timeout: Long = 30_000) =
        compose.waitUntil(timeout) { compose.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty() }

    @Test fun signedOutSharingOffersGoogleAndAnInvitationButNeverBlocksTheRecord() {
        ActivityScenario.launch<MainActivity>(intent("seedDemo", tab = 2))
        waitForTag("signin.google")
        compose.onNodeWithText("Sign in with Google").assertIsDisplayed()
        compose.onNodeWithTag("sharing.join").assertIsDisplayed()
        // The record is still all there with no account.
        compose.onNodeWithTag("tab.today").performClick()
        waitForTag("today.dose.take")
    }

    @Test fun signingInAndStartingACircleUploadsTheRecordAfterConsent() {
        ActivityScenario.launch<MainActivity>(intent("seedDemo", tab = 2))
        waitForTag("signin.google")
        compose.onNodeWithTag("signin.google").performClick()
        waitForTag("sharing.start")
        compose.onNodeWithTag("sharing.start").performClick()
        // A supporter's record is not uploaded without the permission statement.
        waitForTag("sharing.consent.toggle")
        compose.onNodeWithTag("sharing.consent.toggle").performClick()
        compose.onNodeWithTag("sharing.consent.confirm").performClick()
        waitForTag("sharing.invite")
        // Named after the record's person, in full, as `FamilyView.createGroup` does on iOS.
        waitForText("Eleanor Wallner's care circle")
        compose.waitUntil(30_000) { server.tables.getValue(SyncEntity.PERSON).isNotEmpty() && server.tables.getValue(SyncEntity.MEDICATION).isNotEmpty() }
        assertEquals("Eleanor Wallner", server.tables.getValue(SyncEntity.PERSON).values.single().getString("name"))
        // Google already gave the name, so nothing asked for it and it fills "Your name".
        compose.onNodeWithTag("tab.settings").performClick()
        waitForText("Signed in with Google")
        compose.onNodeWithText("Jack Wallner", substring = true).assertIsDisplayed()
    }

    @Test fun anInvitationIsCreatedReadyToShare() {
        ActivityScenario.launch<MainActivity>(intent("seedDemo", "fakeSignedIn", "fakeCircle", tab = 2))
        waitForTag("sharing.invite")
        compose.onNodeWithText("Michael Wallner").assertIsDisplayed()
        compose.onNodeWithTag("sharing.invite").performClick()
        compose.onNodeWithTag("invite.email").performTextInput("michael@example.com")
        compose.onNodeWithTag("invite.create").performScrollTo().performClick()
        waitForTag("invite.code")
        compose.onNodeWithText("Write the email to michael@example.com").assertIsDisplayed()
        compose.onNodeWithTag("invite.share").assertIsDisplayed()
        assertEquals(1, server.invites.count { !it.used && it.email == "michael@example.com" })
    }

    @Test fun aTappedJoinLinkOnANewPhoneJoinsTheFamilysRecordWithoutAskingForAnything() {
        val code = server.seedSarahsCircle()
        val link = intent("fakeSignedIn").setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("https://jackwallner.com/ios/elderhub/join.html?code=${code.lowercase()}"))
        ActivityScenario.launch<MainActivity>(link)
        waitForTag("join.submit")
        compose.onNodeWithTag("join.submit").performClick()
        waitForTag("tab.care")
        compose.onNodeWithTag("tab.care").performClick()
        waitForText("Eleanor Wallner")
        // The check-in the server stamped is visible after the pull, with no push service involved.
        compose.onNodeWithText("Eleanor Wallner").performClick()
        waitForTag("hub.last-check-in")
    }

    @Test fun theCustomSchemeFallbackOpensTheJoinScreenWithTheCode() {
        server.seedSarahsCircle()
        ActivityScenario.launch<MainActivity>(intent("seedDemo", "fakeSignedIn"))
        waitForTag("today.dose.take")
        val scheme = Intent(Intent.ACTION_VIEW, Uri.parse("elderhub://invite?code=HKT7PQ2M"))
            .setClass(ApplicationProvider.getApplicationContext(), MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ApplicationProvider.getApplicationContext<android.content.Context>().startActivity(scheme)
        waitForTag("join.code")
        compose.onNodeWithText("HKT7PQ2M").assertIsDisplayed()
    }

    @Test fun theOrganizerCanRemoveAMember() {
        ActivityScenario.launch<MainActivity>(intent("seedDemo", "fakeSignedIn", "fakeCircle", tab = 2))
        waitForTag("sharing.member.1")
        compose.onNodeWithTag("sharing.member.1").performClick()
        waitForTag("member.remove")
        compose.onNodeWithTag("member.remove").performScrollTo().performClick()
        compose.onNodeWithTag("confirm.action").performClick()
        compose.waitUntil(30_000) { compose.onAllNodesWithText("Michael Wallner").fetchSemanticsNodes().isEmpty() }
        assertTrue(server.members.single { it.userId.toString().endsWith("f006") }.removed)
    }

    @Test fun withNoSignalTheSavedCopyOpensAndSettingsSaysSo() {
        val first = ActivityScenario.launch<MainActivity>(intent("seedDemo", "fakeSignedIn", "fakeCircle", tab = 0))
        waitForTag("today.dose.take")
        first.close()
        server.isOnline = false
        ActivityScenario.launch<MainActivity>(intent("fakeOffline", tab = 3, reset = false))
        waitForTag("settings.sync")
        waitForText("Showing your saved copy")
        // A dose marked offline queues rather than failing.
        compose.onNodeWithTag("tab.today").performClick()
        waitForTag("today.dose.take")
        compose.onAllNodesWithTag("today.dose.take")[0].performClick()
        compose.waitUntil(5_000) { (ApplicationProvider.getApplicationContext<AgingApplication>()).graph.care.state.sync.outbox.isNotEmpty() }
    }
}
