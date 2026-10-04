import Foundation
import SwiftData

@Model
final class Measurement {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var metricType: MetricType = MetricType.weight
    var value: Double = 0
    var value2: Double? // Secondary value (e.g., diastolic BP)
    var unit: String = ""
    var source: MeasurementSource = MeasurementSource.manual
    var notes: String = ""

    init(
        timestamp: Date = Date(),
        metricType: MetricType,
        value: Double,
        value2: Double? = nil,
        unit: String? = nil,
        source: MeasurementSource = .manual,
        notes: String = ""
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.metricType = metricType
        self.value = value
        self.value2 = value2
        self.unit = unit ?? metricType.unit
        self.source = source
        self.notes = notes
    }

    /// Formatted display value (e.g., "120/80" for BP, "72" for HR)
    var displayValue: String {
        if metricType == .bloodPressure, let diastolic = value2 {
            return "\(Int(value))/\(Int(diastolic))"
        }
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}

/// One imported reading per metric and local day. Manual entries stay independent.
@MainActor
final class DailyHealthMeasurementStore {
    private struct Key: Hashable {
        let type: MetricType
        let day: Date
    }

    private let calendar: Calendar
    private var measurements: [Key: Measurement] = [:]

    init(context: ModelContext, since startDate: Date, calendar: Calendar = .current) throws {
        self.calendar = calendar
        let dayStart = calendar.startOfDay(for: startDate)
        let descriptor = FetchDescriptor<Measurement>(
            predicate: #Predicate { $0.timestamp >= dayStart },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        for measurement in try context.fetch(descriptor) where measurement.source == .appleHealth {
            let key = Key(type: measurement.metricType, day: calendar.startOfDay(for: measurement.timestamp))
            if measurements[key] == nil {
                measurements[key] = measurement
            }
        }
    }

    /// Returns true when a row is inserted or changed, including a revised daily total.
    @discardableResult
    func upsert(context: ModelContext, timestamp: Date, type: MetricType,
                value: Double, value2: Double? = nil) -> Bool {
        let key = Key(type: type, day: calendar.startOfDay(for: timestamp))
        if let existing = measurements[key] {
            guard existing.value != value || existing.value2 != value2 || existing.timestamp != timestamp else {
                return false
            }
            existing.value = value
            existing.value2 = value2
            existing.timestamp = timestamp
            return true
        }
        let measurement = Measurement(timestamp: timestamp, metricType: type,
                                      value: value, value2: value2, source: .appleHealth)
        context.insert(measurement)
        measurements[key] = measurement
        return true
    }
}
