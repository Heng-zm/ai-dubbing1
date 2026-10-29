import Foundation
import Photos

enum PhotoLibraryError: LocalizedError {
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Photos permission is required to save the video."
        case .saveFailed:
            return "The video could not be saved to Photos."
        }
    }
}

enum PhotoLibrarySaver {
    static func saveVideo(at url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PhotoLibraryError.saveFailed
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryError.permissionDenied
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PhotoLibraryError.saveFailed)
                }
            }
        }
    }
}
