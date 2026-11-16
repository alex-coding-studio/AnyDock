import Foundation

@MainActor
enum TrayTimeFormat {
    private static let formatter = DateFormatter()

    static func short(_ date: Date) -> String {
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d"
        return formatter.string(from: date)
    }
}
