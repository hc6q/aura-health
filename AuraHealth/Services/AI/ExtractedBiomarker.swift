import Foundation

// MARK: - Models

struct ExtractedBiomarker: Codable, Identifiable {
    var id: String { "\(marker)-\(testDate)" }
    let marker: String
    let value: Double
    let unit: String
    let refMin: Double?
    let refMax: Double?
    let lab: String
    let testDate: String

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var parsedDate: Date {
        Self.dateFormatter.date(from: testDate) ?? Date()
    }
}
