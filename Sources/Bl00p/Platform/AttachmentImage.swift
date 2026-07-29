import Foundation

#if os(macOS)
import AppKit
import SwiftUI
#else
import SwiftOpenUI
#endif

/// Loads an image attachment from disk for the composer chip and the sent
/// thumbnail. On macOS this decodes through AppKit so a corrupt or
/// non-image file falls back to the placeholder icon. SwiftOpenUI's
/// `Image(filePath:)` does not expose a synchronous decode-and-validate step,
/// so the Linux path only confirms the file exists and lets the renderer
/// report an unloadable file the same way it reports a missing one.
struct AttachmentImageView: View {
    let path: String

    var body: some View {
        #if os(macOS)
        if let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            fallback
        }
        #else
        if FileManager.default.fileExists(atPath: path) {
            Image(filePath: path)
                .resizable()
                .scaledToFill()
        } else {
            fallback
        }
        #endif
    }

    private var fallback: some View {
        Image(systemName: "photo")
            .font(.system(size: 20))
    }
}

enum AttachmentImageValidation {
    static func isLoadableImage(at url: URL) -> Bool {
        #if os(macOS)
        NSImage(contentsOf: url) != nil
        #else
        FileManager.default.fileExists(atPath: url.path)
        #endif
    }
}
