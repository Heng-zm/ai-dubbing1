import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case khmer = "km"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .english: return "en-US"
        case .khmer: return "km-KH"
        }
    }

    var nativeName: String {
        switch self {
        case .english: return "English"
        case .khmer: return "ខ្មែរ"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .khmer: return "🇰🇭"
        }
    }

    static var deviceDefault: AppLanguage {
        let code = Locale.current.language.languageCode?.identifier
        return code == "km" ? .khmer : .english
    }
}

enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum TranslationStyle: String, CaseIterable, Identifiable, Codable {
    case natural
    case news
    case storytelling
    case formal
    case social

    var id: String { rawValue }

    var localizationKey: String { "style.\(rawValue)" }

    var promptDescription: String {
        switch self {
        case .natural:
            return "Natural, everyday spoken Khmer that sounds like a professional voice actor."
        case .news:
            return "Clear, neutral broadcast-news Khmer with precise terminology."
        case .storytelling:
            return "Warm, expressive storytelling Khmer with a comfortable narrative rhythm."
        case .formal:
            return "Polite, formal Khmer suitable for business, education, or official content."
        case .social:
            return "Punchy, friendly social-media Khmer that keeps energy and personality."
        }
    }
}

enum DubMode: String, CaseIterable, Identifiable, Codable {
    case replace
    case mix
    case background
    case smartDuck

    var id: String { rawValue }

    var localizationKey: String { "mode.\(rawValue)" }

    var symbol: String {
        switch self {
        case .replace: return "waveform.badge.minus"
        case .mix: return "waveform.badge.plus"
        case .background: return "music.note"
        case .smartDuck: return "waveform.and.person.filled"
        }
    }
}

enum TTSProvider: String, CaseIterable, Identifiable, Codable {
    case automatic
    case azure
    case apple

    var id: String { rawValue }
}

enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case video
    case audio

    var id: String { rawValue }
    var fileExtension: String { self == .video ? "mp4" : "m4a" }
    var localizationKey: String { "export.format.\(rawValue)" }
}

enum ExportKind: String, Codable {
    case video
    case audio
    case subtitle

    var symbol: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        case .subtitle: return "captions.bubble"
        }
    }
}

enum ProjectAspectRatio: String, CaseIterable, Identifiable, Codable {
    case original
    case nineSixteen
    case sixteenNine
    case oneOne

    var id: String { rawValue }
    var localizationKey: String { "aspectRatio.\(rawValue)" }

    var symbol: String {
        switch self {
        case .original: return "aspectratio"
        case .nineSixteen: return "rectangle.portrait"
        case .sixteenNine: return "rectangle"
        case .oneOne: return "square"
        }
    }

    var label: String {
        switch self {
        case .original: return "Original"
        case .nineSixteen: return "9:16"
        case .sixteenNine: return "16:9"
        case .oneOne: return "1:1"
        }
    }
}

enum BurnInSubtitleStyle: String, CaseIterable, Identifiable, Codable {
    case pill
    case neon
    case classic

    var id: String { rawValue }
    var localizationKey: String { "subtitles.style.\(rawValue)" }

    var symbol: String {
        switch self {
        case .pill: return "capsule.fill"
        case .neon: return "sparkles"
        case .classic: return "text.bubble"
        }
    }
}
