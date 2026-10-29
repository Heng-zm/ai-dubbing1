import Foundation

enum Formatters {
    static func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func preciseTimecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00.0" }
        let total = Int(seconds.rounded(.down))
        let minutes = total / 60
        let secs = total % 60
        let tenths = Int((seconds - Double(total)) * 10)
        return String(format: "%d:%02d.%d", minutes, secs, tenths)
    }

    static func fileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }

    static func shortDate(_ date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateFormat = language == .khmer ? "d MMM yyyy" : "MMM d, yyyy"
        return formatter.string(from: date)
    }

    static func relativeDate(_ date: Date, language: AppLanguage) -> String {
        let seconds = Date().timeIntervalSince(date)
        let l10nKey: String
        let value: Int
        switch seconds {
        case ..<60:
            return language == .khmer ? "អម្បាញ់មិញ" : "Just now"
        case ..<3_600:
            l10nKey = "date.minutesAgo"
            value = max(1, Int(seconds / 60))
        case ..<86_400:
            l10nKey = "date.hoursAgo"
            value = max(1, Int(seconds / 3_600))
        case ..<172_800:
            return language == .khmer ? "ម្សិលមិញ" : "Yesterday"
        default:
            l10nKey = "date.daysAgo"
            value = max(1, Int(seconds / 86_400))
        }
        let format = LocalizedTables.value(for: l10nKey, language: language)
        return String(format: format, value)
    }

    static func safeFileComponent(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*:|\"<>")
        let cleaned = raw.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(70))
        return limited.isEmpty ? "KhmerDub" : limited
    }

    static func fileTimestamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

/// Small accessor used by non-View helpers that need a localized string without
/// depending on the observable Localization object.
enum LocalizedTables {
    static func value(for key: String, language: AppLanguage) -> String {
        // The canonical tables live in Localization. This fallback is only used
        // for a handful of relative-date strings and always has an English shape.
        switch key {
        case "date.minutesAgo": return language == .khmer ? "%d នាទីមុន" : "%d min ago"
        case "date.hoursAgo": return language == .khmer ? "%d ម៉ោងមុន" : "%d hr ago"
        case "date.daysAgo": return language == .khmer ? "%d ថ្ងៃមុន" : "%d days ago"
        default: return key
        }
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }

    func truncated(to length: Int, trailing: String = "…") -> String {
        guard count > length else { return self }
        return String(prefix(max(0, length - trailing.count))) + trailing
    }
}
