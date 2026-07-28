import SwiftUI
import Vision
import VisionKit

/// The camera, reading QR codes and nothing else.
///
/// `DataScannerViewController` rather than an AVFoundation session built by
/// hand: it brings the viewfinder, the guidance and the highlight with it, and
/// it asks for the camera itself at the moment it starts. That timing is the
/// point -- the permission sheet arrives when somebody has pointed the phone at
/// a card, which is when it makes sense, and never on a screen they were only
/// passing through.
struct CodeScanner: UIViewControllerRepresentable {
    /// Whether reading is wanted right now. False stops the camera, which
    /// matters: the viewfinder sits behind a card somebody is reading, and a
    /// scanner still running would fire at whatever is over their shoulder.
    let isScanning: Bool
    let onCode: (String) -> Void

    /// Whether this device can do it at all.
    ///
    /// False in the simulator, which has no camera, and on hardware without the
    /// neural engine the scanner needs. Checked before the view is built, so
    /// the screen can offer the typed address instead of an empty black box.
    static var isSupported: Bool {
        DataScannerViewController.isSupported
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            // One item, and no high frame rate tracking: a card is held still
            // and there is one code on it, so the rest is battery.
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if isScanning {
            // Throwing means the camera is unavailable or refused. There is
            // nothing to say here that the screen does not already say better,
            // and the typed field is on it.
            try? scanner.startScanning()
        } else {
            scanner.stopScanning()
        }
    }

    static func dismantleUIViewController(
        _ scanner: DataScannerViewController,
        coordinator: Coordinator
    ) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue else { continue }
                onCode(payload)
            }
        }
    }
}
