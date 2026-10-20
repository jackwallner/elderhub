package com.jackwallner.aging

import android.app.NotificationManager
import android.content.Intent
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.rule.GrantPermissionRule
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Turning reminders on from the hub posts a real grouped notification when a dose is due. */
@RunWith(AndroidJUnit4::class)
class ReminderFlowTest {
    @get:Rule val compose = createEmptyComposeRule()
    @get:Rule val notifications: GrantPermissionRule = GrantPermissionRule.grant(android.Manifest.permission.POST_NOTIFICATIONS)

    @Test fun turningRemindersOnDeliversTheGroupedDoseNotification() {
        val app = ApplicationProvider.getApplicationContext<AgingApplication>()
        ActivityScenario.launch<MainActivity>(
            Intent(app, MainActivity::class.java).putExtra("resetAll", true).putExtra("seedDemo", true),
        )
        compose.waitUntil(10_000) { compose.onAllNodesWithTag("today.full-record").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("today.full-record").performScrollTo().performClick()
        compose.onNodeWithTag("hub.reminders").performScrollTo().performClick()
        val mom = app.graph.care.state.people.single()
        compose.waitUntil(5_000) { app.graph.reminders.preferences.isEnabled(mom.id) }

        val zone = ZoneId.systemDefault()
        app.graph.reminders.fire(LocalDate.now(zone).atTime(8, 0, 30).atZone(zone).toInstant())

        val posted = app.getSystemService(NotificationManager::class.java).activeNotifications
            .map { it.notification.extras.getCharSequence("android.text").toString() }
        assertTrue(posted.toString(), posted.contains("Eleanor Wallner: Lisinopril 10 mg and Metformin 500 mg"))
    }
}
