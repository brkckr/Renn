import Photos
import os
import RENNDomain

/// Add-only Photos saving (05 V09, 06 C06). Requests add-only permission at the first save,
/// never full library access, and never deletes or edits library content.
struct PhotoLibrarySaver: PhotosSaving {
    func saveVideo(at url: URL) async -> PhotosSaveOutcome {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else { return .permissionDenied }

        let identifier = OSAllocatedUnfairLock<String?>(initialState: nil)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: url, options: options)
                let localIdentifier = request.placeholderForCreatedAsset?.localIdentifier
                identifier.withLock { $0 = localIdentifier }
            }
            return .saved(localIdentifier: identifier.withLock { $0 })
        } catch {
            return .failed
        }
    }
}
