//
//  ShareTargets.swift
//  Block Party — the platform bridges behind the share sheet's apps: Messages' composer and the Photos save.
//

import SwiftUI
import UIKit
import MessageUI
import Photos

/// MFMessageComposeViewController bridge — presented imperatively from the
/// overlay window's root VC, with a retained delegate.
enum MessagesComposer {
    static var canSend: Bool { MFMessageComposeViewController.canSendText() }

    private final class Delegate: NSObject, MFMessageComposeViewControllerDelegate {
        static var retained: Delegate?
        var sent: () -> Void = {}
        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
            if result == .sent { sent() }
            MessagesComposer.Delegate.retained = nil
        }
    }

    @MainActor
    static func present(from presenter: UIViewController, text: String, image: UIImage?, recipients: [String] = [],
                        sent: @escaping () -> Void = {}) {
        guard canSend else { return }
        let vc = MFMessageComposeViewController()
        vc.body = text
        vc.recipients = recipients
        if let image, let data = image.pngData() {
            vc.addAttachmentData(data, typeIdentifier: "public.png", filename: "blockparty.png")
        }
        let delegate = Delegate()
        delegate.sent = sent
        Delegate.retained = delegate
        vc.messageComposeDelegate = delegate
        presenter.present(vc, animated: true)
    }
}

/// Photos add-only save. iOS prompts for add permission on first write; the
/// usage string is NSPhotoLibraryAddUsageDescription (Task 4, Step 4).
enum PhotoSaver {
    static func save(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, _ in
            // Only confirm on a real save; a denied/failed write gets an error tick, not a false success.
            DispatchQueue.main.async { success ? Haptics.success() : Haptics.error() }
        }
    }
}
