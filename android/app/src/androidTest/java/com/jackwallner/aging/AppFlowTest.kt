package com.jackwallner.aging

import android.content.Intent
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** End-to-end flows on a real device: first run, Today, the card and the paid boundary. */
@RunWith(AndroidJUnit4::class)
class AppFlowTest {
    @get:Rule val compose = createEmptyComposeRule()

    private fun launch(vararg flags: String, previewStore: Boolean = true): ActivityScenario<MainActivity> {
        val intent = Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java)
            .putExtra("resetAll", true)
            .putExtra("previewStore", previewStore)
        flags.forEach { intent.putExtra(it, true) }
        return ActivityScenario.launch(intent)
    }

    private fun waitForTag(tag: String) = compose.waitUntil(10_000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }

    private fun waitForText(text: String) = compose.waitUntil(10_000) { compose.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty() }

    @Test fun firstRunNamesThePersonBeforeAnythingElseAndLandsOnToday() {
        launch()
        waitForTag("onboarding.path.supporter")
        compose.onNodeWithTag("onboarding.path.supporter").performClick()
        compose.onNodeWithTag("onboarding.name").performTextInput("Eleanor")
        // A supporter must confirm permission before Continue does anything.
        compose.onNodeWithTag("onboarding.continue").assertIsNotEnabled()
        compose.onNodeWithText("Mom").performClick()
        compose.onNodeWithTag("onboarding.attestation").performScrollTo().performClick()
        compose.onNodeWithTag("onboarding.continue").assertIsEnabled().performClick()
        compose.onNodeWithText("Eleanor’s care record is ready").assertIsDisplayed()
        compose.onNodeWithTag("onboarding.finish").performClick()
        waitForText("Today")
        compose.onNodeWithTag("today.add-medication").assertIsDisplayed()
        compose.onNodeWithText("Add Eleanor's medications").assertIsDisplayed()
    }

    @Test fun addingAMedicationPutsItsDosesOnToday() {
        launch()
        waitForTag("onboarding.path.solo")
        compose.onNodeWithTag("onboarding.path.solo").performClick()
        compose.onNodeWithTag("onboarding.name").performTextInput("Pat")
        compose.onNodeWithTag("onboarding.continue").performClick()
        compose.onNodeWithTag("onboarding.finish").performClick()
        waitForTag("today.add-medication")
        compose.onNodeWithTag("today.add-medication").performClick()
        compose.onNodeWithTag("med.name").performTextInput("Lisinopril")
        compose.onNodeWithTag("med.strength").performTextInput("10 mg")
        compose.onNodeWithTag("editor.save").performClick()
        waitForText("Today's doses")
        compose.onNodeWithText("Lisinopril").assertIsDisplayed()
    }

    @Test fun markingADoseTakenRecordsItOnToday() {
        launch("seedDemo")
        waitForTag("today.dose.take")
        val before = compose.onAllNodesWithTag("today.dose.take").fetchSemanticsNodes().size
        compose.onAllNodesWithTag("today.dose.take").onFirst().performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("today.dose.take").fetchSemanticsNodes().size == before - 1 }
        assertTrue(compose.onAllNodesWithTag("today.dose.status").fetchSemanticsNodes().isNotEmpty())
    }

    @Test fun theFreeTierStopsAtOnePersonWithThePaywall() {
        launch("seedDemo")
        waitForTag("tab.care")
        compose.onNodeWithTag("tab.care").performClick()
        compose.onNodeWithText("Elderhub Plus").assertIsDisplayed()
        compose.onNodeWithTag("care.add-person").performClick()
        waitForTag("paywall")
        compose.onNodeWithTag("paywall.headline").assertIsDisplayed()
        compose.onNodeWithTag("paywall.plan.yearly").assertIsDisplayed()
        compose.onNodeWithText("Start My 7-Day Free Trial").assertIsDisplayed()
        compose.onNodeWithTag("paywall.close").performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("paywall").fetchSemanticsNodes().isEmpty() }
        compose.onNodeWithText("Eleanor Wallner").assertIsDisplayed()
    }

    @Test fun buyingPlusUnlocksTheSecondPerson() {
        launch("seedDemo")
        waitForTag("tab.care")
        compose.onNodeWithTag("tab.care").performClick()
        compose.onNodeWithTag("care.add-person").performClick()
        waitForTag("paywall.continue")
        // Preview store only: a debug purchase grants Plus without any store.
        compose.onNodeWithTag("paywall.continue").performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("paywall").fetchSemanticsNodes().isEmpty() }
        compose.onNodeWithTag("care.add-person").performClick()
        waitForTag("person.name")
        compose.onNodeWithTag("person.name").performTextInput("Robert")
        compose.onNodeWithTag("editor.save").assertIsNotEnabled()
        compose.onNodeWithTag("person.attestation").performClick()
        compose.onNodeWithTag("editor.save").performClick()
        waitForText("Robert's record")
    }

    @Test fun plusSubscribersAddPeopleWithoutThePaywall() {
        launch("seedDemo", "seedDad", "demoPro")
        waitForTag("tab.care")
        compose.onNodeWithTag("tab.care").performClick()
        compose.onNodeWithText("Robert Wallner").assertIsDisplayed()
        compose.onNodeWithTag("care.add-person").performClick()
        waitForTag("person.name")
        assertTrue(compose.onAllNodesWithTag("paywall").fetchSemanticsNodes().isEmpty())
    }

    @Test fun theEmergencyCardPrintsEveryCriticalSection() {
        launch("seedDemo")
        waitForTag("today.emergency-card")
        compose.onNodeWithTag("today.emergency-card").performScrollTo().performClick()
        waitForText("ALLERGIES")
        listOf("ALLERGIES", "Penicillin", "CONDITIONS", "MEDICATIONS", "EMERGENCY CONTACTS", "CALL FIRST", "Blood type: O+")
            .forEach { compose.onNodeWithText(it, substring = true).assertExists() }
        compose.onNodeWithText("not a medical record", substring = true).performScrollTo().assertIsDisplayed()
    }

    @Test fun theRecordIsSavedOnThePhoneAcrossLaunches() {
        val scenario = launch("seedDemo")
        waitForTag("tab.care")
        scenario.close()
        val file = File(ApplicationProvider.getApplicationContext<android.content.Context>().filesDir, "care.json")
        assertTrue(file.isFile && file.readText().contains("Eleanor Wallner"))
        ActivityScenario.launch(MainActivity::class.java)
        waitForTag("tab.care")
        compose.onNodeWithTag("tab.care").performClick()
        compose.onNodeWithText("Eleanor Wallner").assertIsDisplayed()
    }

    @Test fun settingsCarriesTheMedicalDisclaimer() {
        launch("seedDemo")
        waitForTag("tab.settings")
        compose.onNodeWithTag("tab.settings").performClick()
        compose.onNodeWithTag("settings.disclaimer").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("It is not a medical device", substring = true).assertExists()
    }
}
