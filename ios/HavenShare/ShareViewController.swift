import SwiftUI
import UIKit

/// The share extension's entry point, named by NSExtensionPrincipalClass.
///
/// A UIViewController because that is what the share point vends; everything
/// inside it is SwiftUI. It opens on the sheet the moment the input is read,
/// which is the whole budget: the system kills a share extension that is slow
/// to launch, which is also why nothing here touches the network.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // The sheet draws its own background over the host app.
        view.backgroundColor = .clear

        Task { @MainActor in
            guard let queue = CaptureQueue.inAppGroup() else {
                // The App Group is not provisioned, so there is nowhere to put
                // a capture. Saying so beats a save that silently goes
                // nowhere.
                return present(.unavailable)
            }
            let subject = await ShareInput.read(
                extensionContext?.inputItems as? [NSExtensionItem] ?? [],
                storingImagesIn: queue
            )
            guard let subject else { return present(.unsupported) }
            present(
                .ready(
                    ShareSheetModel(
                        subject: subject,
                        mirror: DirectoryMirrorStore.inAppGroup()?.load()
                    ),
                    queue
                )
            )
        }
    }

    private func present(_ state: ShareSheetState) {
        let sheet = ShareSheet(
            state: state,
            onFinish: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(
                    withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
                )
            }
        )
        let host = UIHostingController(rootView: sheet)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
