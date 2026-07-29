import Foundation

/// Estimates how tall a wrapped block of text will render, for auto-sizing
/// the composer's editor.
///
/// AppKit measures this exactly via `NSString.boundingRect`. SwiftOpenUI does
/// not expose GTK4's Pango layout engine through its public API, so the Linux
/// path estimates wrapped line count from an average character width instead
/// of laying the text out precisely. The estimate only drives a height clamp
/// between 24 and `ComposerLimits.maximumEditorHeight`, so a few points of
/// error does not affect correctness — worst case the editor is slightly
/// taller or shorter than the exact fit.
enum PortableTextMetrics {
    static func wrappedHeight(
        for text: String,
        width: CGFloat,
        pointSize: CGFloat,
        lineHeightMultiple: CGFloat = 1.28
    ) -> CGFloat {
        let lineHeight = pointSize * lineHeightMultiple
        // Regular-weight system fonts average roughly half their point size
        // in advance width for mixed-case Latin text.
        let averageCharacterWidth = max(1, pointSize * 0.52)
        let charactersPerLine = max(1, Int(width / averageCharacterWidth))

        let paragraphs = text.isEmpty ? [""] : text.components(separatedBy: "\n")
        let wrappedLineCount = paragraphs.reduce(0) { total, paragraph in
            let length = paragraph.count
            let linesInParagraph = length == 0
                ? 1
                : Int(ceil(Double(length) / Double(charactersPerLine)))
            return total + max(1, linesInParagraph)
        }

        return CGFloat(wrappedLineCount) * lineHeight
    }
}
