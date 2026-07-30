#if os(macOS)
import AppKit
import SwiftUI

struct TranscriptScrollObserver: NSViewRepresentable {
    let observe: (Double, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ObservationView {
        let view = ObservationView()
        view.didMove = { [weak coordinator = context.coordinator] view in
            coordinator?.attach(to: view)
        }
        return view
    }

    func updateNSView(_ view: ObservationView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach(to: view)
        context.coordinator.reportViewport(userInitiated: false)
    }

    static func dismantleNSView(
        _ view: ObservationView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }

    final class ObservationView: NSView {
        var didMove: ((ObservationView) -> Void)?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            didMove?(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            didMove?(self)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: TranscriptScrollObserver

        private weak var scrollView: NSScrollView?
        private var observations: [NSObjectProtocol] = []
        private var isAttachScheduled = false
        private var isUserScrolling = false

        init(parent: TranscriptScrollObserver) {
            self.parent = parent
        }

        func attach(to view: ObservationView, mayRetry: Bool = true) {
            guard let enclosingScrollView = view.enclosingScrollView else {
                guard mayRetry, !isAttachScheduled else { return }
                isAttachScheduled = true
                Task { @MainActor [weak self, weak view] in
                    guard let self, let view else { return }
                    await Task.yield()
                    self.isAttachScheduled = false
                    self.attach(to: view, mayRetry: false)
                }
                return
            }
            guard scrollView !== enclosingScrollView else { return }

            detach()
            scrollView = enclosingScrollView
            observe(enclosingScrollView)
            reportViewport(userInitiated: false)
        }

        func detach() {
            for observation in observations {
                NotificationCenter.default.removeObserver(observation)
            }
            observations = []
            scrollView = nil
            isAttachScheduled = false
            isUserScrolling = false
        }

        func reportViewport(userInitiated: Bool) {
            guard let scrollView,
                  let documentView = scrollView.documentView else { return }

            let documentRect = scrollView.contentView.documentRect
            let visibleRect = scrollView.documentVisibleRect
            let distance: CGFloat
            if documentView.isFlipped {
                distance = documentRect.maxY - visibleRect.maxY
            } else {
                distance = visibleRect.minY - documentRect.minY
            }
            parent.observe(
                max(0, Double(distance)),
                userInitiated || isUserScrolling
            )
        }

        private func observe(_ scrollView: NSScrollView) {
            let center = NotificationCenter.default
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollView.postsFrameChangedNotifications = true
            scrollView.documentView?.postsFrameChangedNotifications = true

            observations.append(center.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reportViewport(userInitiated: false)
                }
            })
            observations.append(center.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reportViewport(userInitiated: false)
                }
            })
            if let documentView = scrollView.documentView {
                observations.append(center.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.reportViewport(userInitiated: false)
                    }
                })
            }
            observations.append(center.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isUserScrolling = true
                    self?.reportViewport(userInitiated: true)
                }
            })
            observations.append(center.addObserver(
                forName: NSScrollView.didLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reportViewport(userInitiated: true)
                }
            })
            observations.append(center.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reportViewport(userInitiated: true)
                    self?.isUserScrolling = false
                }
            })
        }
    }
}
#endif
