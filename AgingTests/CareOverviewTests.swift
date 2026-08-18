import Foundation
import SwiftData
import Testing

@testable import Aging

/// The hub screen is only as good as the lines under each tile, and those lines
/// are the part that can quietly go wrong: a count that says "1 medications", a
/// tile that reads as full when it is empty, a checklist that never completes.
@MainActor
struct CareOverviewTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    private func makePerson(in context: ModelContext) -> Person {
        let person = Person(name: "Eleanor Wallner", relationship: "Mom")
        context.insert(person)
        return person
    }

    // MARK: - Tile detail lines

    @Test func anEmptyRecordSaysSoOnEveryTile() {
        let context = makeContext()
        let person = makePerson(in: context)

        for feature in CareFeature.allCases where feature != .timeline && feature != .checkIn {
            #expect(
                CareOverview.detail(for: feature, person: person) == "None yet"
                || CareOverview.detail(for: feature, person: person) == "Nothing to do",
                "\(feature.rawValue) should read as empty"
            )
            #expect(CareOverview.isEmpty(feature, person: person))
        }
    }

    @Test func countsAreSingularWhenThereIsOne() {
        let context = makeContext()
        let person = makePerson(in: context)

        let med = Medication(name: "Lisinopril", strength: "10 mg", person: person)
        context.insert(med)
        let visit = Visit(date: Date(), reason: "Check-up", person: person)
        context.insert(visit)

        #expect(CareOverview.detail(for: .medications, person: person) == "1 medication")
        #expect(CareOverview.detail(for: .visits, person: person) == "1 visit")
        #expect(!CareOverview.isEmpty(.medications, person: person))
    }

    @Test func countsArePluralWhenThereAreMore() {
        let context = makeContext()
        let person = makePerson(in: context)

        for name in ["Lisinopril", "Metformin", "Atorvastatin"] {
            let med = Medication(name: name, person: person)
            context.insert(med)
        }

        #expect(CareOverview.detail(for: .medications, person: person) == "3 medications")
    }

    /// A tombstoned row is still in the local store until the outbox has pushed
    /// it, so a tile that read the raw relationship would keep counting a
    /// medication the user deleted minutes ago.
    @Test func deletedRowsDoNotCountTowardsATile() {
        let context = makeContext()
        let person = makePerson(in: context)

        let med = Medication(name: "Lisinopril", person: person)
        context.insert(med)
        #expect(CareOverview.detail(for: .medications, person: person) == "1 medication")

        med.tombstone(in: context)
        #expect(CareOverview.detail(for: .medications, person: person) == "None yet")
        #expect(CareOverview.isEmpty(.medications, person: person))
    }

    @Test func healthDetailsListsWhatIsRecorded() {
        let context = makeContext()
        let person = makePerson(in: context)

        #expect(CareOverview.detail(for: .healthDetails, person: person) == "None yet")

        person.allergies = ["Penicillin"]
        person.conditions = ["Hypertension", "Type 2 diabetes"]
        person.bloodType = "O+"

        let detail = CareOverview.detail(for: .healthDetails, person: person)
        #expect(detail == "1 allergy, 2 conditions, blood type")
        #expect(!CareOverview.isEmpty(.healthDetails, person: person))
    }

    @Test func tasksLeadWithWhatIsDue() {
        let context = makeContext()
        let person = makePerson(in: context)

        let overdue = CareTask(title: "Pharmacy refill", person: person)
        overdue.dueAt = Calendar.current.date(byAdding: .day, value: -2, to: Date())
        context.insert(overdue)

        let later = CareTask(title: "Book podiatrist", person: person)
        later.dueAt = Calendar.current.date(byAdding: .day, value: 9, to: Date())
        context.insert(later)

        #expect(CareOverview.detail(for: .tasks, person: person) == "2 open · 1 due")
    }

    /// Every tile has to say something. A blank line under a title is the exact
    /// "what does this even do" the screen exists to answer.
    @Test func everyFeatureProducesCopy() {
        let context = makeContext()
        let person = makePerson(in: context)

        for feature in CareFeature.allCases {
            #expect(!feature.title.isEmpty)
            #expect(!feature.blurb.isEmpty)
            #expect(!feature.symbol.isEmpty)
            #expect(!feature.quickActionTitle.isEmpty)
            #expect(!CareOverview.detail(for: feature, person: person).isEmpty)
        }
    }

    /// Jack's house style, enforced rather than remembered: no em dashes in any
    /// user-facing string this file owns.
    @Test func copyHasNoEmDashes() {
        for feature in CareFeature.allCases {
            #expect(!feature.title.contains("—"))
            #expect(!feature.blurb.contains("—"))
            #expect(!feature.quickActionTitle.contains("—"))
        }
    }

    @Test func hubOrderCoversEveryFeatureExactlyOnce() {
        #expect(Set(CareFeature.hubOrder) == Set(CareFeature.allCases))
        #expect(CareFeature.hubOrder.count == CareFeature.allCases.count)
    }

    /// The Today row is now six chips and a menu, and the risk that creates is
    /// a feature that is in neither. Check-in is the deliberate exception: it is
    /// set up once, on the person's hub, not reached for from Today.
    @Test func todayRowAndItsMenuReachEveryFeature() {
        var reached: Set<CareFeature> = []
        for action in QuickAction.todayRow {
            if case .feature(let feature) = action { reached.insert(feature) }
            reached.formUnion(action.members)
        }
        #expect(reached == Set(CareFeature.allCases).subtracting([.checkIn]))
    }

    /// A chip whose label is blank or whose menu is empty is a dead end.
    @Test func everyQuickActionHasCopy() {
        for action in QuickAction.todayRow {
            #expect(!action.title.isEmpty)
            #expect(!action.symbol.isEmpty)
            #expect(!action.title.contains("—"))
            #expect(action.colorIndex < AppTheme.featureColors.count)
            if case .medical = action { #expect(!action.members.isEmpty) }
        }
    }

    @Test func featureColorsCoverEveryFeature() {
        for feature in CareFeature.allCases {
            #expect(feature.colorIndex < AppTheme.featureColors.count)
        }
        #expect(Set(CareFeature.allCases.map(\.colorIndex)).count == CareFeature.allCases.count)
    }

    // MARK: - Setup checklist

    @Test func aFreshRecordHasNothingSetUp() {
        let context = makeContext()
        let person = makePerson(in: context)

        let steps = SetupChecklist.steps(for: person, remindersEnabled: false, hasSharedWithFamily: false, hasCheckIn: false)

        #expect(steps.count == 6)
        #expect(SetupChecklist.completed(steps) == 0)
        #expect(!SetupChecklist.isFinished(steps))
    }

    @Test func stepsTickOffAsTheRecordFillsIn() {
        let context = makeContext()
        let person = makePerson(in: context)

        let med = Medication(name: "Lisinopril", person: person)
        context.insert(med)
        person.allergies = ["Penicillin"]
        let contact = EmergencyContact(name: "Dr. Patel", phone: "555-0100", person: person)
        context.insert(contact)

        let steps = SetupChecklist.steps(for: person, remindersEnabled: true, hasSharedWithFamily: false, hasCheckIn: false)

        #expect(SetupChecklist.completed(steps) == 4)
        #expect(steps.first { $0.kind == .addMedication }?.isDone == true)
        #expect(steps.first { $0.kind == .doseReminders }?.isDone == true)
        #expect(steps.first { $0.kind == .healthDetails }?.isDone == true)
        #expect(steps.first { $0.kind == .emergencyContact }?.isDone == true)
        #expect(steps.first { $0.kind == .inviteFamily }?.isDone == false)
    }

    /// The card takes itself off the screen when there is nothing left to say.
    @Test func aFullyConfiguredRecordFinishesTheChecklist() {
        let context = makeContext()
        let person = makePerson(in: context)

        let med = Medication(name: "Lisinopril", person: person)
        context.insert(med)
        person.conditions = ["Hypertension"]
        let contact = EmergencyContact(name: "Dr. Patel", phone: "555-0100", person: person)
        context.insert(contact)

        let steps = SetupChecklist.steps(for: person, remindersEnabled: true, hasSharedWithFamily: true, hasCheckIn: true)

        #expect(SetupChecklist.isFinished(steps))
        #expect(SetupChecklist.completed(steps) == steps.count)
    }

    @Test func everyStepExplainsItself() {
        let context = makeContext()
        let person = makePerson(in: context)
        let steps = SetupChecklist.steps(for: person, remindersEnabled: false, hasSharedWithFamily: false, hasCheckIn: false)

        for step in steps {
            #expect(!step.title.isEmpty)
            #expect(!step.detail.isEmpty, "\(step.kind.rawValue) needs a reason, not just a chore")
            #expect(!step.title.contains("—"))
            #expect(!step.detail.contains("—"))
        }
    }

    @Test func hidingTheSetupCardIsRememberedPerPerson() {
        let defaults = UserDefaults(suiteName: "care-overview-tests-\(UUID().uuidString)")!
        let mom = UUID()
        let dad = UUID()

        #expect(!SetupCardPreferences.isHidden(personID: mom, defaults: defaults))

        SetupCardPreferences.setHidden(true, personID: mom, defaults: defaults)
        #expect(SetupCardPreferences.isHidden(personID: mom, defaults: defaults))
        #expect(!SetupCardPreferences.isHidden(personID: dad, defaults: defaults))

        SetupCardPreferences.clear(personID: mom, defaults: defaults)
        #expect(!SetupCardPreferences.isHidden(personID: mom, defaults: defaults))
    }

    // MARK: - Per-step dismissal

    /// The whole point of dismissing per step: waving away the invite row must
    /// leave the other five alone, and must not touch the other person.
    @Test func dismissingOneStepKeepsTheRest() {
        let defaults = UserDefaults(suiteName: "care-overview-tests-\(UUID().uuidString)")!
        let mom = UUID()
        let dad = UUID()

        #expect(SetupStepPreferences.dismissed(personID: mom, defaults: defaults).isEmpty)

        SetupStepPreferences.dismiss(.inviteFamily, personID: mom, defaults: defaults)

        #expect(SetupStepPreferences.dismissed(personID: mom, defaults: defaults) == [.inviteFamily])
        #expect(SetupStepPreferences.dismissed(personID: dad, defaults: defaults).isEmpty)
    }

    @Test func dismissalsCanBePutBack() {
        let defaults = UserDefaults(suiteName: "care-overview-tests-\(UUID().uuidString)")!
        let mom = UUID()

        SetupStepPreferences.dismiss(.inviteFamily, personID: mom, defaults: defaults)
        SetupStepPreferences.dismiss(.checkIn, personID: mom, defaults: defaults)

        SetupStepPreferences.restore(.checkIn, personID: mom, defaults: defaults)
        #expect(SetupStepPreferences.dismissed(personID: mom, defaults: defaults) == [.inviteFamily])

        // What Settings → "Set up again" leans on.
        SetupStepPreferences.restoreAll(personID: mom, defaults: defaults)
        #expect(SetupStepPreferences.dismissed(personID: mom, defaults: defaults).isEmpty)
    }

    @Test func visibleStepsDropTheDismissedOnes() {
        let context = makeContext()
        let person = makePerson(in: context)
        let steps = SetupChecklist.steps(for: person, remindersEnabled: false, hasSharedWithFamily: false, hasCheckIn: false)

        let visible = SetupChecklist.visible(steps, dismissed: [.inviteFamily, .checkIn])

        #expect(visible.count == steps.count - 2)
        #expect(!visible.contains { $0.kind == .inviteFamily })
        #expect(!visible.contains { $0.kind == .checkIn })
    }

    /// Dismissing every remaining step has to empty the card rather than leave
    /// a heading with nothing under it.
    @Test func dismissingEverythingLeavesNothingToShow() {
        let context = makeContext()
        let person = makePerson(in: context)
        let steps = SetupChecklist.steps(for: person, remindersEnabled: false, hasSharedWithFamily: false, hasCheckIn: false)

        let visible = SetupChecklist.visible(steps, dismissed: Set(steps.map(\.kind)))

        #expect(visible.isEmpty)
    }
}
