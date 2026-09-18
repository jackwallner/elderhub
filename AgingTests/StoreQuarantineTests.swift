import Foundation
import SwiftData
import Testing

@testable import Aging

/// An unopenable store is moved aside, never deleted: for a user outside a
/// family group it is the only copy of the records.
@MainActor
@Suite(.serialized)
struct StoreQuarantineTests {
    @Test func unreadableStoreIsMovedAsideNotDeleted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = dir.appendingPathComponent("Aging.store")
        let wal = URL(fileURLWithPath: store.path + "-wal")
        try Data("records".utf8).write(to: store)
        try Data("wal".utf8).write(to: wal)

        let moved = CareModelStore.quarantineStore(at: store)

        #expect(moved.count == 2)
        #expect(!FileManager.default.fileExists(atPath: store.path))
        let copy = try #require(moved.first { !$0.lastPathComponent.contains("-wal") })
        #expect(copy.lastPathComponent.hasPrefix("Aging.store.corrupt-"))
        #expect(try Data(contentsOf: copy) == Data("records".utf8))
    }

    @Test func successfulSaveReportsNothing() {
        let container = CareModelStore.makeInMemoryContainer()
        let context = container.mainContext
        SaveFailureReporter.shared.message = nil
        let person = Person(name: "Mom", relationship: "Mother", colorIndex: 0, isSelf: false)
        context.insert(person)
        #expect(context.saveOrReport())
        #expect(SaveFailureReporter.shared.message == nil)
        #expect(!context.hasChanges)
    }

    @Test func reportedFailureNamesNoRecord() {
        SaveFailureReporter.shared.message = nil
        SaveFailureReporter.shared.report(CocoaError(.fileWriteOutOfSpace))
        let message = SaveFailureReporter.shared.message ?? ""
        #expect(message.contains("could not be saved"))
        #expect(!message.contains("—"))
        SaveFailureReporter.shared.message = nil
    }
}
