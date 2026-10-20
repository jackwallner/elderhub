package com.jackwallner.aging

import com.jackwallner.aging.data.InMemoryStore
import com.jackwallner.aging.data.ReminderPreferences
import com.jackwallner.aging.model.CareState
import com.jackwallner.aging.model.DoseReminderPlanner
import com.jackwallner.aging.model.Medication
import com.jackwallner.aging.model.Person
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Parity with `AgingTests/DoseReminderTests.swift`, plus the Android rolling-alarm rules. */
class DoseReminderTest {
    private val zone = ZoneId.of("America/New_York")
    private val now: Instant = LocalDate.of(2026, 7, 15).atTime(12, 0).atZone(zone).toInstant() // a Wednesday
    private val mom = Person(name = "Eleanor")
    private val dad = Person(name = "Robert")

    private fun med(p: Person, name: String, minutes: List<Int>, weekdays: List<Int> = emptyList(), asNeeded: Boolean = false) =
        Medication(personId = p.id, name = name, strength = "500 mg", scheduleMinutes = minutes, weekdays = weekdays, isAsNeeded = asNeeded)

    private fun plan(vararg meds: Medication, people: List<Person> = listOf(mom, dad), enabled: Set<java.util.UUID> = people.map { it.id }.toSet()) =
        DoseReminderPlanner.plan(CareState(people = people, medications = meds.toList()), enabled, now)

    @Test fun emptyWeekdaysMeansOneSpecPerTimeEveryDay() {
        val specs = plan(med(mom, "Metformin", listOf(480, 1140)))
        assertEquals(2, specs.size)
        assertTrue(specs.all { it.weekday == null })
    }

    @Test fun specificWeekdaysProduceOneSpecPerDay() {
        val specs = plan(med(mom, "Alendronate", listOf(420), weekdays = listOf(2, 4, 6)))
        assertEquals(listOf(2, 4, 6), specs.map { it.weekday })
    }

    @Test fun asNeededInactiveAndEndedMedicationsProduceNoSpecs() {
        val stopped = med(mom, "Warfarin", listOf(480)).stopped(now.minus(1, ChronoUnit.DAYS))
        val ended = med(mom, "Prednisone", listOf(480)).copy(endDate = now.minus(1, ChronoUnit.DAYS))
        assertTrue(plan(med(mom, "Acetaminophen", listOf(480), asNeeded = true), stopped, ended).isEmpty())
    }

    @Test fun identifierEncodesPersonTimeAndWeekday() {
        val specs = plan(med(mom, "Alendronate", listOf(510), weekdays = listOf(2)))
        assertEquals("dose-${mom.id.toString().uppercase()}-510-2", specs.single().identifier)
    }

    @Test fun medicationsSharingATimeShareOneReminder() {
        val specs = plan(
            med(mom, "Metformin", listOf(480, 1200)), med(mom, "Atorvastatin", listOf(480)), med(mom, "Lisinopril", listOf(480)),
        )
        assertEquals(2, specs.size)
        val morning = specs.first { it.hour == 8 }
        assertEquals(3, morning.medicationNames.size)
        assertEquals("Time for 3 doses", morning.title)
        assertEquals("Eleanor: Atorvastatin 500 mg, Lisinopril 500 mg and 1 more", morning.body)
    }

    @Test fun twoMedicationsAtOneTimeAreBothNamed() {
        val specs = plan(med(mom, "Metformin", listOf(480)), med(mom, "Warfarin", listOf(480)))
        assertEquals("Eleanor: Metformin 500 mg and Warfarin 500 mg", specs.single().body)
    }

    @Test fun twoPeopleAtTheSameTimeStayTwoReminders() {
        val specs = plan(med(mom, "Metformin", listOf(480)), med(dad, "Atorvastatin", listOf(480)))
        assertEquals(setOf(mom.id, dad.id), specs.map { it.personId }.toSet())
    }

    @Test fun aDailyAndAWeeklyMedicationAtOneTimeStaySeparate() {
        val specs = plan(med(mom, "Metformin", listOf(480)), med(mom, "Alendronate", listOf(480), weekdays = listOf(2)))
        assertEquals(2, specs.size)
        assertTrue(specs.any { it.weekday == null && it.medicationNames == listOf("Metformin 500 mg") })
        assertTrue(specs.any { it.weekday == 2 && it.medicationNames == listOf("Alendronate 500 mg") })
    }

    @Test fun bodyNamesThePersonAndUsesNoEmDash() {
        val body = plan(med(mom, "Metformin", listOf(480))).single().body
        assertEquals("Eleanor: Metformin 500 mg", body)
        assertFalse(body.contains('—'))
    }

    @Test fun onlyPeopleWithRemindersOnAreScheduled() {
        val specs = plan(med(mom, "Metformin", listOf(480)), med(dad, "Atorvastatin", listOf(480)), enabled = setOf(dad.id))
        assertEquals(listOf(dad.id), specs.map { it.personId })
    }

    @Test fun preferenceIsOffUntilTurnedOnAndIsPerPerson() {
        val prefs = ReminderPreferences(InMemoryStore())
        assertFalse(prefs.isEnabled(mom.id))
        prefs.setEnabled(mom.id, true)
        assertTrue(prefs.isEnabled(mom.id))
        assertFalse(prefs.isEnabled(dad.id))
        prefs.setEnabled(mom.id, false)
        assertFalse(prefs.isEnabled(mom.id))
    }

    @Test fun nextFireRespectsTheWeekdayAndTheWallClock() {
        val weekly = plan(med(mom, "Alendronate", listOf(420), weekdays = listOf(2))).single()
        // From Wednesday noon the next Monday 7:00 is 2026-07-20.
        assertEquals(LocalDate.of(2026, 7, 20).atTime(7, 0).atZone(zone).toInstant(), weekly.nextFire(now, zone))
        val daily = plan(med(mom, "Metformin", listOf(1140))).single()
        assertEquals(LocalDate.of(2026, 7, 15).atTime(19, 0).atZone(zone).toInstant(), daily.nextFire(now, zone))
        // A reminder rings at 8:00 on the clock even across the spring-forward night.
        val morning = plan(med(mom, "Metformin", listOf(480))).single()
        val saturdayNight = LocalDate.of(2026, 3, 7).atTime(23, 0).atZone(zone).toInstant()
        assertEquals(8, morning.nextFire(saturdayNight, zone).atZone(zone).hour)
    }

    @Test fun theRollingAlarmTargetsTheSoonestGroupAndDeliversWhatIsDue() {
        val specs = plan(med(mom, "Metformin", listOf(480, 1140)), med(dad, "Atorvastatin", listOf(1140)))
        val (at, group) = DoseReminderPlanner.next(specs, now, zone)!!
        assertEquals(LocalDate.of(2026, 7, 15).atTime(19, 0).atZone(zone).toInstant(), at)
        assertEquals(2, group.size)
        // Delivered four minutes late, inside the window: both 7pm reminders are still due, the 8am is not.
        val due = DoseReminderPlanner.due(specs, at.minusSeconds(360), at.plusSeconds(300), zone)
        assertEquals(setOf(19), due.map { it.hour }.toSet())
        assertEquals(2, due.size)
    }
}
