package com.jackwallner.aging

import com.jackwallner.aging.model.CareState
import com.jackwallner.aging.model.DeterministicId
import com.jackwallner.aging.model.DoseLog
import com.jackwallner.aging.model.DoseStatus
import com.jackwallner.aging.model.Medication
import com.jackwallner.aging.model.Person
import com.jackwallner.aging.model.ScheduleEngine
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Parity with `AgingTests/ScheduleEngineTests.swift`, same zone and dates. */
class ScheduleEngineTest {
    private val zone = ZoneId.of("America/New_York")
    private fun day(y: Int, m: Int, d: Int): Instant = LocalDate.of(y, m, d).atStartOfDay(zone).toInstant()
    private val person = Person(name = "Eleanor", relationship = "Mom")

    private fun state(vararg meds: Medication, doses: List<DoseLog> = emptyList()) =
        CareState(people = listOf(person), medications = meds.toList(), doses = doses)

    @Test fun scheduledMedicationProducesOneSlotPerTime() {
        val med = Medication(personId = person.id, name = "Metformin", strength = "500 mg", scheduleMinutes = listOf(8 * 60, 19 * 60), startDate = day(2026, 7, 1))
        val slots = ScheduleEngine.slots(state(med), person.id, day(2026, 7, 15), zone)
        assertEquals(2, slots.size)
        assertTrue(slots.all { it.isPending })
        assertTrue(slots[0].scheduledAt < slots[1].scheduledAt)
    }

    @Test fun asNeededMedicationIsNeverScheduled() {
        val med = Medication(personId = person.id, name = "Acetaminophen", isAsNeeded = true, scheduleMinutes = listOf(8 * 60))
        assertTrue(ScheduleEngine.slots(state(med), person.id, day(2026, 7, 15), zone).isEmpty())
    }

    @Test fun medicationIsNotScheduledBeforeItStarts() {
        val med = Medication(personId = person.id, name = "Lisinopril", scheduleMinutes = listOf(8 * 60), startDate = day(2026, 7, 20))
        assertTrue(ScheduleEngine.slots(state(med), person.id, day(2026, 7, 15), zone).isEmpty())
        assertEquals(1, ScheduleEngine.slots(state(med), person.id, day(2026, 7, 21), zone).size)
    }

    @Test fun weekdayRestrictionIsHonored() {
        // 2 == Monday in Calendar's 1-indexed, Sunday-first numbering.
        val med = Medication(personId = person.id, name = "Alendronate", scheduleMinutes = listOf(7 * 60), startDate = day(2026, 7, 1), weekdays = listOf(2))
        assertEquals(1, ScheduleEngine.slots(state(med), person.id, day(2026, 7, 13), zone).size)
        assertTrue(ScheduleEngine.slots(state(med), person.id, day(2026, 7, 14), zone).isEmpty())
    }

    @Test fun loggedDoseIsMatchedToItsSlot() {
        val med = Medication(personId = person.id, name = "Metformin", scheduleMinutes = listOf(8 * 60), startDate = day(2026, 7, 1))
        val target = day(2026, 7, 15)
        val time = med.doseTimes(target, zone)[0]
        val log = DoseLog.create(med.id, time, DoseStatus.TAKEN, "You")
        val slots = ScheduleEngine.slots(state(med, doses = listOf(log)), person.id, target, zone)
        assertEquals(1, slots.size)
        assertEquals(DoseStatus.TAKEN, slots[0].status)
        assertEquals("You", slots[0].recordedBy)
        assertTrue(!slots[0].isPending)
    }

    @Test fun adherenceCountsTakenOverScheduled() {
        val med = Medication(personId = person.id, name = "Metformin", scheduleMinutes = listOf(8 * 60), startDate = day(2026, 7, 1))
        val end = day(2026, 7, 15)
        val doses = (0 until 2).map { offset ->
            val target = end.atZone(zone).minusDays(offset.toLong()).toInstant()
            DoseLog.create(med.id, med.doseTimes(target, zone)[0], DoseStatus.TAKEN, "")
        }
        assertEquals(0.5, ScheduleEngine.adherence(state(med, doses = doses), person.id, 4, end, zone)!!, 0.0)
    }

    @Test fun adherenceIsNilWithNothingScheduled() {
        assertNull(ScheduleEngine.adherence(state(), person.id, 7, day(2026, 7, 15), zone))
    }

    @Test fun minutesRoundTripThroughTimeLabel() {
        val noon = LocalDate.of(2026, 7, 15).atTime(12, 30).atZone(zone).toInstant()
        assertEquals(12 * 60 + 30, ScheduleEngine.minutes(noon, zone))
        assertEquals("12:30 PM", ScheduleEngine.timeLabel(12 * 60 + 30, Locale.US).replace(' ', ' '))
    }

    // Daylight saving (iOS ea7c92e). A schedule is a time on the clock, so it is placed by the
    // clock's hour and minute, not by elapsed minutes after midnight: those days are 23 and 25
    // hours long, and the 8:00 AM tablet used to be listed at 9:00 AM (spring) or 7:00 AM (fall)
    // while the reminder fired at 8:00 AM.
    private val losAngeles = ZoneId.of("America/Los_Angeles")

    private fun clock(times: List<Instant>, z: ZoneId) = times.map {
        val t = it.atZone(z)
        "%02d:%02d".format(t.hour, t.minute)
    }

    private fun daily(vararg minutes: Int, from: Instant) =
        Medication(personId = person.id, name = "Metformin", scheduleMinutes = minutes.toList(), startDate = from)

    @Test fun daylightSavingSpringForwardKeepsTheEightAmDoseAtEight() {
        // Epoch 1772971200 is 2026-03-08 08:00 EDT, checked against the iOS wall-clock call.
        val med = daily(8 * 60, 20 * 60, from = day(2026, 3, 1))
        val times = med.doseTimes(day(2026, 3, 8), zone)
        assertEquals(1_772_971_200L, times[0].epochSecond)
        assertEquals(listOf("08:00", "20:00"), clock(times, zone))
        assertEquals(8 * 60, ScheduleEngine.minutes(med.doseTimes(day(2026, 3, 9), zone)[0], zone))
    }

    @Test fun daylightSavingFallBackKeepsTheEightAmDoseAtEight() {
        val med = daily(8 * 60, 20 * 60, from = day(2026, 10, 1))
        assertEquals(listOf("08:00", "20:00"), clock(med.doseTimes(day(2026, 11, 1), zone), zone))
    }

    @Test fun westCoastChangeDaysKeepTheClockToo() {
        val spring = daily(8 * 60, from = LocalDate.of(2026, 3, 1).atStartOfDay(losAngeles).toInstant())
        val fall = daily(8 * 60, from = LocalDate.of(2026, 10, 1).atStartOfDay(losAngeles).toInstant())
        val springDay = LocalDate.of(2026, 3, 8).atStartOfDay(losAngeles).toInstant()
        val fallDay = LocalDate.of(2026, 11, 1).atStartOfDay(losAngeles).toInstant()
        assertEquals(listOf("08:00"), clock(spring.doseTimes(springDay, losAngeles), losAngeles))
        assertEquals(listOf("08:00"), clock(fall.doseTimes(fallDay, losAngeles), losAngeles))
    }

    @Test fun todaysListShowsTheSameClockTimesOnTheDayTheClocksChange() {
        val med = daily(8 * 60, from = day(2026, 10, 1))
        val slots = ScheduleEngine.slots(state(med), person.id, day(2026, 11, 1), zone)
        assertEquals(listOf("08:00"), clock(slots.map { it.scheduledAt }, zone))
    }

    @Test fun aDoseLoggedOnTheChangeDayStillMatchesItsSlot() {
        val med = daily(8 * 60, from = day(2026, 10, 1))
        val target = day(2026, 11, 1)
        val slot = ScheduleEngine.slots(state(med), person.id, target, zone)[0]
        val log = DoseLog.create(med.id, slot.scheduledAt, DoseStatus.TAKEN, "Test")
        val again = ScheduleEngine.slots(state(med, doses = listOf(log)), person.id, target, zone)[0]
        assertEquals(DoseStatus.TAKEN, again.status)
    }

    @Test fun twoDosesInTheHourTheClocksSkipStayTwoSlots() {
        // 2:00 and 2:30 AM do not exist on 2026-03-08; each still gets its own slot.
        val med = daily(2 * 60, 2 * 60 + 30, from = day(2026, 3, 1))
        val times = med.doseTimes(day(2026, 3, 8), zone)
        assertEquals(2, times.size)
        assertEquals(2, times.toSet().size)
        assertTrue(times[0] < times[1])
    }

    @Test fun aScheduleLabelReadsTheSameOnTheDaysTheClocksChange() {
        // The label comes from LocalTime, which has no zone, so it cannot drift by an hour.
        assertEquals("8:00 AM", ScheduleEngine.timeLabel(8 * 60, Locale.US).replace(' ', ' '))
    }

    @Test fun stoppedMedicationLeavesTheDoseList() {
        val med = Medication(personId = person.id, name = "Warfarin", scheduleMinutes = listOf(8 * 60), startDate = day(2026, 7, 1)).stopped(day(2026, 7, 10))
        assertTrue(ScheduleEngine.slots(state(med), person.id, day(2026, 7, 15), zone).isEmpty())
        val restarted = med.restarted()
        assertNull(restarted.endDate)
        assertEquals(1, ScheduleEngine.slots(state(restarted), person.id, day(2026, 7, 15), zone).size)
    }

    @Test fun weekdayLabelReadsLikeIos() {
        assertEquals("", ScheduleEngine.weekdayLabel(emptyList(), Locale.US))
        assertEquals("", ScheduleEngine.weekdayLabel((1..7).toList(), Locale.US))
        assertEquals("Mondays", ScheduleEngine.weekdayLabel(listOf(2), Locale.US))
        assertEquals("Mon, Wed, Fri", ScheduleEngine.weekdayLabel(listOf(6, 2, 4), Locale.US))
        // A Monday-first locale never reads its own week back to front.
        assertEquals("Mon, Sun", ScheduleEngine.weekdayLabel(listOf(1, 2), Locale.UK))
        assertEquals("Sun, Mon", ScheduleEngine.weekdayLabel(listOf(1, 2), Locale.US))
    }

    @Test fun weekdayNumbersMatchFoundationCalendar() {
        assertEquals(1, ScheduleEngine.weekdayNumber(LocalDate.of(2026, 7, 12))) // Sunday
        assertEquals(2, ScheduleEngine.weekdayNumber(LocalDate.of(2026, 7, 13))) // Monday
        assertEquals(7, ScheduleEngine.weekdayNumber(LocalDate.of(2026, 7, 18))) // Saturday
        (1..7).forEach { assertEquals(it, ScheduleEngine.weekdayNumber(ScheduleEngine.dayOfWeek(it))) }
    }

    @Test fun scheduleLabelCarriesDaysAndTimes() {
        val med = Medication(personId = person.id, name = "Alendronate", scheduleMinutes = listOf(20 * 60, 8 * 60), weekdays = listOf(2, 4, 6))
        val label = med.scheduleLabel()
        assertTrue(label.startsWith(ScheduleEngine.weekdayLabel(listOf(2, 4, 6)) + " · "))
        assertEquals("", med.copy(isAsNeeded = true).scheduleLabel())
    }
}

/** `DeterministicID.v5` vectors produced by compiling the iOS Swift file itself. */
class DeterministicIdTest {
    @Test fun matchesTheRfcAndTheSwiftImplementation() {
        val dns = UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
        assertEquals("886313e1-3b8a-5372-9b90-0c9aee199e5d", DeterministicId.v5(dns, "python.org").toString())
    }

    @Test fun doseLogIdMatchesIosForTheSameSlot() {
        val medication = UUID.fromString("3f2504e0-4f89-11d3-9a0c-0305e82c3301")
        val at = Instant.ofEpochSecond(1_784_116_800)
        assertEquals("4b994dcd-adcd-5238-941e-af5dc462c73a", DoseLog.deterministicId(medication, at).toString())
    }

    @Test fun idIsBucketedToTheMinute() {
        val medication = UUID.randomUUID()
        val slot = Instant.ofEpochSecond(1_784_116_800)
        assertEquals(DoseLog.deterministicId(medication, slot), DoseLog.deterministicId(medication, slot.plusSeconds(31)))
        assertTrue(DoseLog.deterministicId(medication, slot) != DoseLog.deterministicId(medication, slot.plusSeconds(60)))
    }
}
