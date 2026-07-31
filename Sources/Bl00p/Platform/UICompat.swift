#if os(macOS)
import SwiftUI
#else
import SwiftOpenUI
#endif

extension View {
    /// Keeps shared workflow progress UI on the portable view surface while
    /// preserving SwiftUI's richer accessibility grouping on macOS.
    func bl00pAccessibilitySummary(
        label: String,
        value: String
    ) -> some View {
        #if os(macOS)
        accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(value))
        #else
        self
        #endif
    }

    /// Combines a card into one accessibility element where SwiftUI supports
    /// it. SwiftOpenUI still receives the complete spoken label on Linux.
    func bl00pCombinedAccessibilityLabel(_ label: String) -> some View {
        #if os(macOS)
        accessibilityElement(children: .combine)
            .accessibilityLabel(Text(label))
        #else
        accessibilityLabel(label)
        #endif
    }
}

#if !os(macOS)

// SwiftOpenUI covers the SwiftUI surface bl00p uses, with a few gaps. These
// shims fill the ones that appear in otherwise portable view code so those
// files can stay identical to upstream. Gaps that only appear in macOS window
// chrome are handled at their call site instead.
extension View {
    /// SwiftOpenUI ships `background(_:in:)` for materials and hierarchical
    /// styles but not for a plain colour. `Shape.fill(_:)` produces a view, so
    /// the colour form composes from the general `background(_:alignment:)`.
    func background<S: Shape>(_ color: Color, in shape: S) -> some View {
        background(shape.fill(color))
    }

    /// SwiftUI's letter-spacing modifier has no SwiftOpenUI equivalent.
    /// Dropping it only affects the tracked-out look of uppercase section
    /// labels, not legibility, so it is a no-op here.
    func tracking(_ value: Double) -> some View { self }

    /// `List` and `TextEditor` paint an opaque background in SwiftUI that
    /// this modifier hides; SwiftOpenUI's GTK4 backend does not add one, so
    /// there is nothing to hide.
    func scrollContentBackground(_ visibility: Bl00pVisibility) -> some View { self }

    /// `Form` has one rendering on the GTK4 backend, so there is no grouped
    /// vs. plain style to switch between.
    func formStyle(_ style: Bl00pFormStyle) -> some View { self }

    /// SwiftUI uses this to extend a view's tap target beyond its rendered
    /// content. GTK4 widgets already treat their full allocated bounds as
    /// hit-testable, so bl00p's one call site (widening a disclosure row's
    /// tap target) needs no equivalent here.
    func contentShape<S: Shape>(_ shape: S) -> some View { self }

    /// SwiftUI uses this to let taps pass through a purely decorative
    /// overlay to the view beneath it. Both of bl00p's call sites are small,
    /// non-interactive decorations (a placeholder-text hint, a drop-target
    /// border) layered over already-interactive controls, so the absence is
    /// a minor click-target overlap rather than a blocked interaction.
    func allowsHitTesting(_ enabled: Bool) -> some View { self }
}

/// Stand-in for SwiftUI's `FormStyle` — only the one case bl00p passes.
enum Bl00pFormStyle {
    case grouped
}

/// Stand-in for SwiftUI's `Visibility` — only the one case bl00p passes.
enum Bl00pVisibility {
    case hidden
}

extension Button where Label == SwiftOpenUI.Label {
    /// SwiftUI's title+icon convenience initializer; SwiftOpenUI only ships
    /// the title-only and fully custom-label forms.
    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.init(action: action) {
            SwiftOpenUI.Label(title, systemImage: systemImage)
        }
    }
}

extension View {
    /// SwiftUI's accent-color override has no SwiftOpenUI equivalent.
    /// Affected controls (`ProgressView`) fall back to bl00p's default pink
    /// accent instead of the per-call tint.
    func tint(_ color: Color) -> some View { self }

    /// SwiftUI's `task(id:)` cancels and restarts its work whenever `id`
    /// changes. SwiftOpenUI only ships the run-once `task(_:)`, so this
    /// composes it with `onChange` instead: the action still runs on first
    /// appearance and on every `id` change, just without the automatic
    /// cancellation of an in-flight previous run. bl00p's two call sites
    /// (a short scroll-to-bottom delay and a focus request) are short-lived
    /// enough that an overlap is harmless.
    func task<ID: Equatable>(
        id: ID,
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @Sendable () async -> Void
    ) -> some View {
        task(priority: priority, action)
            .onChange(of: id) { _, _ in
                Task(priority: priority) { await action() }
            }
    }
}

/// Stand-in for SwiftUI's `LabeledContent`: a leading label with trailing
/// content, matching the layout bl00p's settings rows use it for.
struct LabeledContent<Content: View>: View {
    let label: String
    let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.bl00p(.body))
            Spacer()
            content()
        }
    }
}

#endif
