import Foundation

/// Converts typed service errors into user-facing copy in the selected app
/// language. Detailed provider messages are appended when they are useful for
/// diagnosing a failed request.
@MainActor
enum ErrorPresenter {
    static func message(for error: Error, localization: Localization) -> String {
        if error is CancellationError {
            return localization.t("error.cancelled")
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return localization.t("error.cancelled")
        }
        if let error = error as? AIServiceError {
            switch error {
            case .missingConfiguration:
                return localization.t("error.missingKey")
            case .invalidURL:
                return localization.t("error.invalidURL")
            case .network:
                return localization.t("error.network")
            case .http(let status, let message):
                let base = localization.f("error.http", status)
                let detail = message.trimmed
                return detail.isEmpty ? base : "\(base)\n\(detail.truncated(to: 240))"
            case .decoding, .unsupportedResponse:
                return localization.t("error.decoding")
            case .emptyResponse:
                return localization.t("error.empty")
            case .noSpeech:
                return localization.t("error.transcriptionEmpty")
            case .fileTooLarge:
                return localization.t("error.fileTooLarge")
            case .noMedia:
                return localization.t("error.noMedia")
            case .cancelled:
                return localization.t("error.cancelled")
            }
        }
        if let error = error as? TTSError {
            switch error {
            case .noKhmerVoice:
                return localization.t("error.noKhmerVoice")
            case .missingAzureKey:
                return localization.t("error.azureMissing")
            case .invalidRegion:
                return localization.t("error.azureRegion")
            case .emptyText:
                return localization.t("error.noTranslatedText")
            case .renderFailed:
                return localization.t("error.voiceRender")
            case .timeout:
                return localization.t("error.timeout")
            }
        }
        if let error = error as? AzureSpeechError {
            switch error {
            case .missingKey:
                return localization.t("error.azureMissing")
            case .invalidRegion:
                return localization.t("error.azureRegion")
            case .emptyText:
                return localization.t("error.noTranslatedText")
            case .invalidResponse:
                return localization.t("error.provider")
            case .http(let status, let message):
                let base = localization.f("error.http", status)
                return message.trimmed.isEmpty ? base : "\(base)\n\(message.truncated(to: 240))"
            case .network:
                return localization.t("error.network")
            }
        }
        if let error = error as? MediaError {
            switch error {
            case .noAudio:
                return localization.t("error.noAudio")
            case .noVideo:
                return localization.t("error.exportNoVideo")
            case .invalidFile, .copyFailed, .metadataFailed, .unsupportedType:
                return localization.t("error.invalidFile")
            case .audioExportFailed:
                return localization.t("error.export")
            }
        }
        if let error = error as? ExportError {
            switch error {
            case .noSegments:
                return localization.t("error.noSegments")
            case .noTranslatedText:
                return localization.t("error.noTranslatedText")
            case .noMedia:
                return localization.t("error.noMedia")
            case .noVideo:
                return localization.t("error.exportNoVideo")
            case .noVoice:
                return localization.t("error.noKhmerVoice")
            case .invalidTiming:
                return localization.t("error.invalidTiming")
            case .renderFailed:
                return localization.t("error.export")
            case .subtitleFailed:
                return localization.t("error.subtitle")
            }
        }
        if let error = error as? KeychainError {
            _ = error
            return localization.t("error.keychain")
        }
        if let error = error as? PhotoLibraryError {
            switch error {
            case .permissionDenied:
                return localization.t("error.photoPermission")
            case .saveFailed:
                return localization.t("error.photoSave")
            }
        }
        let fallback = error.localizedDescription.trimmed
        return fallback.isEmpty ? localization.t("error.generic") : fallback
    }
}
