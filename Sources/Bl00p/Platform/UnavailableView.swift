#if os(macOS)
import SwiftUI
#else
import SwiftOpenUI
#endif

/// Stand-in for SwiftUI's `ContentUnavailableView`, which SwiftOpenUI does
/// not implement.
struct Bl00pUnavailableView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.bl00p(.headline, weight: .semibold))

            Text(description)
                .font(.bl00p(.callout))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
