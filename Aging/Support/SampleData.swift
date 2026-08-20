import Foundation
import SwiftData

/// Seed data for previews and headless simulator runs. Never used in a release build path.
@MainActor
enum SampleData {

    static func previewContainer() -> ModelContainer {
        let container = CareModelStore.makeInMemoryContainer()
        seed(into: container.mainContext)
        return container
    }

    /// A person detached from any container, for previews that only need the object.
    static func previewPerson() -> Person {
        let person = Person(name: "Eleanor Wallner", relationship: "Mom", colorIndex: 0)
        person.birthDate = Calendar.current.date(from: DateComponents(year: 1947, month: 4, day: 12))
        person.bloodType = "O+"
        person.allergies = ["Penicillin", "Sulfa drugs"]
        person.conditions = ["Hypertension", "Type 2 diabetes"]
        return person
    }

    private static func calendarDaysFromNow(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
    }

    #if DEBUG
    /// A two-person care circle, written straight into the local mirror.
    ///
    /// Anything gated on "somebody else is in the family" (the tasks screen's
    /// Everyone/Mine filter, and the "You" that replaces the reader's own name
    /// on a row) is invisible without one, and a real circle needs a signed-in
    /// account and a server round trip that a headless simulator has neither
    /// of. So the cache the app reads at launch is seeded directly.
    ///
    /// Local only, and DEBUG only. No auth session is faked and nothing is
    /// queued for push, so this cannot reach the server or a real family's
    /// data. `GroupService.loadFromCache()` picks it up on the next launch.
    ///
    /// A *new* circle every launch, replacing any it finds, which is the point:
    /// the pool simulators keep their store between runs, so a circle carried
    /// over would leave last run's tasks still assigned to this run's reader and
    /// no test could ever assert that nothing is. New ids make those leftovers
    /// somebody else's, which is what they are.
    /// The names deliberately avoid the "Jack" and "Sarah" that `seed` puts on
    /// its sample tasks. Those are assigned by name with no id, so a circle
    /// whose reader is also called Jack would match them through the name
    /// fallback in `TaskPlanner.isAssigned` and inherit a previous test's
    /// errands. The fallback is doing its job there; the seed just must not
    /// collide with it.
    static func seedDemoCircle(
        into context: ModelContext,
        selfName: String = "Robin",
        siblingName: String = "Dana"
    ) {
        for group in (try? context.fetch(FetchDescriptor<CareGroup>())) ?? [] {
            context.delete(group)
        }
        for member in (try? context.fetch(FetchDescriptor<CachedGroupMember>())) ?? [] {
            context.delete(member)
        }

        let group = CareGroup(name: "Wallner family", role: .owner)
        context.insert(group)

        let me = CachedGroupMember(
            id: UUID(),
            groupID: group.id,
            displayName: selfName,
            role: .owner,
            joinedAt: calendarDaysFromNow(-30),
            isSelf: true
        )
        let sibling = CachedGroupMember(
            id: UUID(),
            groupID: group.id,
            displayName: siblingName,
            role: .caregiver,
            joinedAt: calendarDaysFromNow(-20),
            isSelf: false
        )
        context.insert(me)
        context.insert(sibling)
        try? context.save()
    }
    #endif

    /// Seeds only an empty store, so relaunching the screenshot build does not
    /// stack a second Eleanor on top of the first.
    static func seedIfEmpty(into context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Person>())) ?? 0
        guard existing == 0 else { return }
        seed(into: context)
        try? context.save()
    }

    static func seed(into context: ModelContext) {
        let mom = Person(name: "Eleanor Wallner", relationship: "Mom", colorIndex: 0)
        mom.birthDate = Calendar.current.date(from: DateComponents(year: 1947, month: 4, day: 12))
        mom.bloodType = "O+"
        mom.allergies = ["Penicillin", "Sulfa drugs"]
        mom.conditions = ["Hypertension", "Type 2 diabetes"]
        context.insert(mom)

        let primaryCare = Provider(
            name: "Dr. Patel",
            specialty: "Primary care",
            phone: "(555) 200-1010",
            person: mom
        )
        context.insert(primaryCare)

        // The audiologist plus the hearing-themed medication, visit and
        // incident below exist so a search for "hearing" (plan82 slice F)
        // has something real to find across every kind at once.
        let audiologist = Provider(
            name: "Dr. Chen",
            specialty: "Audiology",
            phone: "(555) 200-3030",
            notes: "Fits and adjusts hearing aids.",
            person: mom
        )
        context.insert(audiologist)

        let pharmacy = Provider(
            name: "CVS Pharmacy - Main St",
            phone: "(555) 200-5050",
            isPharmacy: true,
            person: mom
        )
        context.insert(pharmacy)

        let lisinopril = Medication(
            name: "Lisinopril",
            strength: "10 mg",
            form: .tablet,
            purpose: "blood pressure",
            person: mom
        )
        lisinopril.scheduleMinutes = [8 * 60]
        lisinopril.prescriber = "Dr. Patel"
        lisinopril.instructions = "Take with food"
        lisinopril.providerID = primaryCare.id
        lisinopril.pharmacyID = pharmacy.id
        context.insert(lisinopril)

        let metformin = Medication(
            name: "Metformin",
            strength: "500 mg",
            form: .tablet,
            purpose: "blood sugar",
            person: mom
        )
        metformin.scheduleMinutes = [8 * 60, 19 * 60]
        metformin.prescriber = "Dr. Patel"
        metformin.providerID = primaryCare.id
        metformin.pharmacyID = pharmacy.id
        context.insert(metformin)

        let acetaminophen = Medication(
            name: "Acetaminophen",
            strength: "500 mg",
            form: .tablet,
            purpose: "joint pain",
            person: mom
        )
        acetaminophen.isAsNeeded = true
        context.insert(acetaminophen)

        let hearingAidBatteries = Medication(
            name: "Hearing Aid Batteries",
            strength: "size 312",
            form: .other,
            purpose: "hearing aid",
            person: mom
        )
        hearingAidBatteries.isAsNeeded = true
        hearingAidBatteries.instructions = "Replace weekly. Keep spares in the visit bag."
        hearingAidBatteries.pharmacyID = pharmacy.id
        context.insert(hearingAidBatteries)

        let contact = EmergencyContact(
            name: "Jack Wallner",
            relationship: "Son",
            phone: "(555) 010-4477",
            isPrimary: true,
            person: mom
        )
        context.insert(contact)

        let visit = Visit(
            date: Calendar.current.date(byAdding: .day, value: -12, to: Date()) ?? Date(),
            provider: "Dr. Patel",
            specialty: "Primary care",
            reason: "Three month check",
            person: mom
        )
        visit.notes = "BP still running high in the mornings. Keep logging readings before breakfast and bring the numbers to the next visit."
        visit.followUp = "Recheck in 3 months"
        visit.providerID = primaryCare.id
        context.insert(visit)

        let hearingVisit = Visit(
            date: Calendar.current.date(byAdding: .day, value: -40, to: Date()) ?? Date(),
            provider: "Dr. Chen",
            specialty: "Audiology",
            reason: "Annual hearing screening",
            person: mom
        )
        hearingVisit.notes = "Mild high-frequency hearing loss, worse in the left ear. Discussed hearing aid options."
        hearingVisit.followUp = "Fit hearing aids in two weeks"
        hearingVisit.providerID = audiologist.id
        context.insert(hearingVisit)

        // One appointment still to come, so the Upcoming section, the Today
        // row and the "Next: ..." tile line all have something to show in a
        // preview and in a screenshot.
        let upcoming = Visit(
            date: Calendar.current.date(
                bySettingHour: 10, minute: 15, second: 0,
                of: Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date()
            ) ?? Date(),
            provider: "Dr. Patel",
            specialty: "Primary care",
            reason: "Blood pressure review",
            person: mom
        )
        upcoming.notes = "Ask whether the morning dose can move later."
        upcoming.providerID = primaryCare.id
        context.insert(upcoming)

        let hearingEvent = CareEvent(
            kind: .symptom,
            occurredAt: Calendar.current.date(byAdding: .day, value: -45, to: Date()) ?? Date(),
            note: "Reports muffled hearing in the left ear, worse on the phone.",
            recordedBy: "Jack",
            person: mom
        )
        context.insert(hearingEvent)

        // One task per bucket, so a screenshot of the list shows every state:
        // overdue, due today, dated later, undated, and recently ticked off.
        let overdueTask = CareTask(
            title: "Call the pharmacy about the Lisinopril refill",
            dueAt: calendarDaysFromNow(-3),
            priority: .high,
            recurrence: .never,
            assigneeName: "Jack",
            createdByName: "Sarah",
            person: mom
        )
        context.insert(overdueTask)

        let todayTask = CareTask(
            title: "Replace hearing aid batteries",
            notes: "Size 312. Spares live in the visit bag.",
            dueAt: Date(),
            recurrence: .weekly,
            assigneeName: "Sarah",
            createdByName: "Jack",
            person: mom
        )
        context.insert(todayTask)

        let laterTask = CareTask(
            title: "Pay the long-term care premium",
            dueAt: calendarDaysFromNow(21),
            recurrence: .yearly,
            assigneeName: "Jack",
            createdByName: "Jack",
            person: mom
        )
        context.insert(laterTask)

        let somedayTask = CareTask(
            title: "Ask Dr. Chen about a hearing aid upgrade",
            priority: .low,
            createdByName: "Sarah",
            person: mom
        )
        context.insert(somedayTask)

        let doneTask = CareTask(
            title: "Book the three month check with Dr. Patel",
            dueAt: calendarDaysFromNow(-9),
            assigneeName: "Sarah",
            createdByName: "Jack",
            person: mom
        )
        doneTask.completedAt = calendarDaysFromNow(-8)
        doneTask.completedByName = "Sarah"
        context.insert(doneTask)

        // Notes are the screen with no shape of its own, so the seed has to
        // carry the shape: one pinned logistics note and one long note that
        // wraps, which is what proves the row truncates rather than collides.
        // No gate code in the seed either. The empty state stopped suggesting
        // one, and seeded data that still models a credential teaches the same
        // habit the editor's footer is there to prevent.
        let pinnedNote = CareNote(
            title: "Getting into the house",
            body: "Use the side door, the front one sticks. Spare key with Marta next door, and she is usually in before noon.",
            isPinned: true,
            createdByName: "Sarah",
            person: mom
        )
        context.insert(pinnedNote)

        let appointmentNote = CareNote(
            title: "Ask at the next neurology visit",
            body: "Whether the evening Metformin can move earlier, and if the dizziness on standing is worth mentioning. Sarah has the list from the last visit in her bag.",
            createdByName: "Jack",
            person: mom
        )
        context.insert(appointmentNote)

        // One bill per bucket, for the same reason the tasks are: a screenshot
        // of the list has to be able to show overdue, due soon, later, autopay
        // and recently paid all at once.
        let careHomeBill = Bill(
            payee: "Sunrise Assisted Living",
            amount: 2450,
            notes: "Covers the room and the daily check. Meals are billed separately.",
            category: .care,
            recurrence: .monthly,
            dueAt: calendarDaysFromNow(-4),
            createdByName: "Jack",
            person: mom
        )
        context.insert(careHomeBill)

        let utilityBill = Bill(
            payee: "Duke Energy",
            amount: 142.30,
            category: .utilities,
            recurrence: .monthly,
            dueAt: calendarDaysFromNow(3),
            createdByName: "Sarah",
            person: mom
        )
        context.insert(utilityBill)

        let taxBill = Bill(
            payee: "County property tax",
            amount: 1180,
            category: .housing,
            recurrence: .halfYearly,
            dueAt: calendarDaysFromNow(48),
            createdByName: "Jack",
            person: mom
        )
        context.insert(taxBill)

        let autoPayBill = Bill(
            payee: "Medicare supplement",
            amount: 189,
            category: .insurance,
            recurrence: .monthly,
            dueAt: calendarDaysFromNow(9),
            isAutoPay: true,
            createdByName: "Jack",
            person: mom
        )
        context.insert(autoPayBill)

        let paidBill = Bill(
            payee: "Comcast",
            amount: 89.99,
            category: .utilities,
            recurrence: .monthly,
            dueAt: calendarDaysFromNow(-18),
            createdByName: "Sarah",
            person: mom
        )
        paidBill.paidAt = calendarDaysFromNow(-17)
        paidBill.paidByName = "Sarah"
        context.insert(paidBill)

        let reading = VitalReading(
            kind: .bloodPressure,
            primaryValue: 148,
            secondaryValue: 88,
            recordedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
            person: mom
        )
        context.insert(reading)

        // Roughly two years of history below: biweekly vitals, weekly dose
        // logs, quarterly visits and monthly incidents. A naive search that
        // rescans everything on each keystroke stutters against this row
        // count; an empty preview store would never have caught that
        // (plan82 slice F).
        let calendar = Calendar.current
        let today = Date()

        for weeksAgo in stride(from: 2, through: 104, by: 2) {
            guard let date = calendar.date(byAdding: .day, value: -weeksAgo * 7, to: today) else { continue }
            let vital = VitalReading(
                kind: .bloodPressure,
                primaryValue: Double.random(in: 122...152),
                secondaryValue: Double.random(in: 74...92),
                recordedAt: date,
                person: mom
            )
            context.insert(vital)
        }

        for weeksAgo in stride(from: 1, through: 104, by: 1) {
            guard let date = calendar.date(byAdding: .day, value: -weeksAgo * 7, to: today) else { continue }
            let status: DoseStatus = weeksAgo % 11 == 0 ? .missed : (weeksAgo % 7 == 0 ? .skipped : .taken)
            let dose = DoseLog(scheduledAt: date, status: status, recordedBy: "Jack", medication: lisinopril)
            context.insert(dose)
        }

        for quartersAgo in 1...7 {
            guard let date = calendar.date(byAdding: .month, value: -quartersAgo * 3, to: today) else { continue }
            let quarterlyVisit = Visit(
                date: date,
                provider: "Dr. Patel",
                specialty: "Primary care",
                reason: "Quarterly check",
                person: mom
            )
            quarterlyVisit.providerID = primaryCare.id
            context.insert(quarterlyVisit)
        }

        let eventKinds: [CareEventKind] = [.fall, .symptom, .mood, .appetite, .sleep, .pain]
        for monthsAgo in 1...24 {
            guard let date = calendar.date(byAdding: .month, value: -monthsAgo, to: today) else { continue }
            let kind = eventKinds[monthsAgo % eventKinds.count]
            let event = CareEvent(
                kind: kind,
                occurredAt: date,
                severity: (monthsAgo % 5) + 1,
                note: "\(kind.label) logged during a routine check-in.",
                recordedBy: monthsAgo % 2 == 0 ? "Jack" : "Sarah",
                person: mom
            )
            context.insert(event)
        }

        let dad = Person(name: "Robert Wallner", relationship: "Dad", colorIndex: 1)
        dad.birthDate = Calendar.current.date(from: DateComponents(year: 1944, month: 9, day: 3))
        context.insert(dad)

        let cardiologist = Provider(
            name: "Dr. Osei",
            specialty: "Cardiology",
            phone: "(555) 200-7070",
            person: dad
        )
        context.insert(cardiologist)

        let atorvastatin = Medication(
            name: "Atorvastatin",
            strength: "20 mg",
            form: .tablet,
            purpose: "cholesterol",
            person: dad
        )
        atorvastatin.scheduleMinutes = [21 * 60]
        atorvastatin.prescriber = "Dr. Osei"
        atorvastatin.providerID = cardiologist.id
        context.insert(atorvastatin)

        let dadContact = EmergencyContact(
            name: "Jack Wallner",
            relationship: "Son",
            phone: "(555) 010-4477",
            isPrimary: true,
            person: dad
        )
        context.insert(dadContact)
    }
}
