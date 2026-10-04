import Foundation
import XCTest
import SwiftData
@testable import AuraSync

@MainActor
final class DailyHealthMeasurementStoreTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Measurement.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testRepeatedSyncUpdatesTotalsWithoutDuplicatesAndPreservesManualData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let day = Calendar.current.startOfDay(for: Date())
        let manual = Measurement(timestamp: day, metricType: .steps, value: 42)
        context.insert(manual)
        let firstSync = try DailyHealthMeasurementStore(context: context, since: day)
        firstSync.upsert(context: context, timestamp: day, type: .steps, value: 100)
        try context.save()

        let nextSync = try DailyHealthMeasurementStore(context: context, since: day)
        XCTAssertTrue(nextSync.upsert(context: context, timestamp: day, type: .steps, value: 2000))
        XCTAssertFalse(nextSync.upsert(context: context, timestamp: day, type: .steps, value: 2000))
        // Corrections may decrease a total, too.
        XCTAssertTrue(nextSync.upsert(context: context, timestamp: day, type: .steps, value: 1900))
        try context.save()
        let rows = try context.fetch(FetchDescriptor<Measurement>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first { $0.source == .appleHealth }?.value, 1900)
        XCTAssertEqual(manual.value, 42)
    }

    func testLatestReadingReplacesLegacyMidnightRowAndKeepsOtherDays() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let day = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        let legacy = Measurement(timestamp: day, metricType: .heartRate, value: 60, source: .appleHealth)
        context.insert(legacy)
        // A cutoff in the middle of the day must still find a legacy midnight row.
        let store = try DailyHealthMeasurementStore(context: context, since: day.addingTimeInterval(3600))
        store.upsert(context: context, timestamp: day.addingTimeInterval(7200), type: .heartRate, value: 80)
        store.upsert(context: context, timestamp: yesterday, type: .heartRate, value: 65)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Measurement>()), 2)
        XCTAssertEqual(legacy.value, 80)
        XCTAssertEqual(legacy.timestamp, day.addingTimeInterval(7200))
    }

    func testUpdatesEveryMetricAndBothBloodPressureValues() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let day = Calendar.current.startOfDay(for: Date())
        let store = try DailyHealthMeasurementStore(context: context, since: day)
        for type in MetricType.allCases {
            store.upsert(context: context, timestamp: day, type: type, value: 1)
            store.upsert(context: context, timestamp: day, type: type, value: 2)
        }
        store.upsert(context: context, timestamp: day, type: .bloodPressure, value: 120, value2: 80)
        store.upsert(context: context, timestamp: day, type: .bloodPressure, value: 118, value2: 76)
        try context.save()
        let rows = try context.fetch(FetchDescriptor<Measurement>())
        XCTAssertEqual(rows.count, MetricType.allCases.count)
        for row in rows where row.metricType != .bloodPressure { XCTAssertEqual(row.value, 2) }
        XCTAssertEqual(rows.first { $0.metricType == .bloodPressure }?.value, 118)
        XCTAssertEqual(rows.first { $0.metricType == .bloodPressure }?.value2, 76)
    }
}
