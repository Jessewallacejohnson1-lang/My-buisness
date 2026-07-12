//
//  ShareTargets.swift
//  Hygge — the share sheet's target row (Messages · Save image · More) and the
//  platform bridges behind each (Messages composer, Photos save, OS share sheet).
//

import SwiftUI
import UIKit
import MessageUI
import Photos

/// The Duolingo-style row of round targets. Adapts: link-only shares (no image)
/// drop "Save image".
struct ShareTargetRow: View {
    @ObservedObject private var center = ShareCenter.shared
    let includesImage: Bool

    var body: some View {
        HStack(spacing: 30) {
            if center.canSendMessages {
                target("message.fill", "Messages", tint: .white, bg: Color(hex: 0x34C759)) {
                    center.sendMessages()
                }
            }
            if includesImage {
                target("square.and.arrow.down", "Save image", tint: Hue.ink, bg: Hue.canvas) {
                    center.saveImage()
                }
            }
            target("ellipsis", "More", tint: Hue.ink, bg: Hue.canvas) {
                center.shareMore()
            }
        }
    }

    private func target(_ symbol: String, _ label: String,
                        tint: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 60, height: 60)
                    .background(bg, in: Circle())
                    .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
                Text(label)
                    .font(.sans(12))
                    .foregroundStyle(Hue.ink2)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }
}

/// MFMessageComposeViewController bridge — presented imperatively from the
/// overlay window's root VC, with a retained delegate.
enum MessagesComposer {
    static var canSend: Bool { MFMessageComposeViewController.canSendText() }

    private final class Delegate: NSObject, MFMessageComposeViewControllerDelegate {
        static var retained: Delegate?
        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
            MessagesComposer.Delegate.retained = nil
        }
    }

    @MainActor
    static func present(from presenter: UIViewController, text: String, image: UIImage?) {
        guard canSend else { return }
        let vc = MFMessageComposeViewController()
        vc.body = text
        if let image, let data = image.pngData() {
            vc.addAttachmentData(data, typeIdentifier: "public.png", filename: "hygge.png")
        }
        let delegate = Delegate()
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
            DispatchQueue.main.async { Haptics.success() }   // gentle confirm; failures stay silent
        }
    }
}
