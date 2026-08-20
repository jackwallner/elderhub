import Foundation
import SwiftData
import Testing

@testable import Aging

/// `Medication.weekdays` was in the model, the sync payload and the reminder
/// planner from the start, and nothing rendered it: a tablet taken on Mondays
/// printed on the emergency card, on the exported one-pager and in the
/// medication list as a tablet taken every day.
@MainActor
struct WeekdayScheduleTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    // MARK: The label

    @Test func everyDayNeedsNoWords() {
        #expect(ScheduleEngine.weekdayLabel(for: [], calendar: calendar).isEmpty)
        #expect(ScheduleEngine.weekdayLabel(for: [1, 2, 3, 4, 5, 6, 7], calendar: calendar).isEmpty)
    }

    @Test func oneDayReadsAsThePluralNobodyHasToDecode() {
        #expect(ScheduleEngine.weekdayLabel(for: [2], calendar: calendar) == "Mondays")
        #expect(ScheduleEngine.weekdayLabel(for: [1], calendar: calendar) == "Sundays")
    }

    @Test func severalDaysReadInWeekOrderWhateverOrderTheyWereStoredIn() {
        #expect(ScheduleEngine.weekdayLabel(for: [6, 2, 4], calendar: calendar) == "Mon, Wed, Fri")
    }

    @Test func aWeekBeginningOnMondayIsNotReadBackToFront() {
        var monday = calendar
        monday.firstWeekday = 2
        #expect(ScheduleEngine.weekdayLabel(for: [1, 2], calendar: monday) == "Mon, Sun")
        #expect(ScheduleEngine.orderedWeekdays(calendar: monday) == [2, 3, 4, 5, 6, 7, 1])
    }

    @Test func nonsenseWeekdayNumbersAreIgnoredRatherThanCrashing() {
        #expect(ScheduleEngine.weekdayLabel(for: [0, 9], calendar: calendar).isEmpty)
    }

    // MARK: The one schedule string

    @Test func aWeeklyMedicationSaysWhichDay() {
        let context = makeContext()
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)

        let med = Medication(name: "Alendronate", strength: "70 mg", person: person)
        med.scheduleMinutes = [7 * 60]
        med.weekdays = [2]
        context.insert(med)

        #expect(med.scheduleLabel.contains("Mondays"))
        #expect(med.scheduleLabel.contains("7:00"))
    }

    @Test func aDailyMedicationSaysOnlyItsTimes() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let med = Medication(name: "Metformin", strength: "500 mg", person: person)
        med.scheduleMinutes = [8 * 60, 20 * 60]
        context.insert(med)

        #expect(!med.scheduleLabel.contains("Mon"))
        #expect(med.scheduleLabel.contains(","))
    }

    @Test func anAsNeededMedicationHasNoScheduleToPrint() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let med = Medication(name: "Paracetamol", person: person)
        med.isAsNeeded = true
        med.scheduleMinutes = []
        context.insert(med)

        #expect(med.scheduleLabel.isEmpty)
    }

    // MARK: The page somebody hands to a nurse

    @Test func theExportedListSaysWhichDaysAWeeklyTabletIsTaken() {
        let context = makeContext()
        let person = Person(name: "Eleanor Wallner", relationship: "Mom")
        context.insert(person)

        let weekly = Medication(name: "Alendronate", strength: "70 mg", person: person)
        weekly.scheduleMinutes = [7 * 60]
        weekly.weekdays = [2]
        context.insert(weekly)

        let daily = Medication(name: "Metformin", strength: "500 mg", person: person)
        daily.scheduleMinutes = [8 * 60]
        context.insert(daily)

        let output = MedListExporter.plainText(for: person)
        let weeklyLine = output.split(separator: "\n").first { $0.contains("Alendronate") } ?? ""
        let dailyLine = output.split(separator: "\n").first { $0.contains("Metformin") } ?? ""

        #expect(weeklyLine.contains("Mondays"))
        #expect(!dailyLine.contains("Mon"))
    }
}
