import Foundation

/// Shared formatting helpers for byte counts, durations, and relative times.
enum FormatHelpers {
    /// Human-readable byte count, e.g. "1.2 GB".
    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }

    /// Duration formatted as M:SS, e.g. "3:07".
    static func duration(_ value: TimeInterval) -> String {
        let totalSeconds = max(0, Int(value.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Relative time, e.g. "2 hours ago".
    static func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
