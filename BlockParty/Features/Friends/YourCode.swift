//
//  YourCode.swift
//  Block Party — Your code (BP app docs/plans/friends, ticket 07): the last button on the Friends
//  card opens Apple's sheet with your photo, name, Neighbor since and a QR code of your link. A
//  neighbour points their iPhone camera at it and lands on your page with Add friend; Scan a code
//  opens Apple's own scanner (VisionKit), asking for the camera only then; Share sends a picture
//  of the code with the invite words.
//
//  References: Strava's and LinkedIn's QR code pages and BeReal's scanner (BP app
//  references/friends-tab-ideas/refs). The sheet's sizes are the draft Jesse approved on
//  2026-10-21; mock Jesse said yes to on 2026-10-29: https://claude.ai/artifact/FQ4mw4QbZvGYq8SzTshGvE
//
//  The code holds the app link (`blockparty://neighbor/<id>`) until Apple's paid developer account
//  turns on app links for blockpartymn.com; then `link(for:)` switches to the website's
//  `/n/<id>`, which `userID(from:)` already reads, so codes made before still work (BP app
//  backlog 10).
//

import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import Vision
import VisionKit

extension FriendsMetric {
    // The approved draft (BP app references/friends-tab-ideas/mock.html, "your code").
    static let codeTop: CGFloat = 41
    static let codeFace: CGFloat = 88
    static let codeFaceRing: CGFloat = 3
    static let codeNameTop: CGFloat = 12
    static let codeSinceTop: CGFloat = 2
    static let codeCardTop: CGFloat = 26
    static let codeCard: CGFloat = 260
    static let codeCardRadius: CGFloat = 28
    static let code: CGFloat = 212
    /// Pixels a module, and white modules round the code for Share.
    static let codeScale: CGFloat = 12
    static let codeMargin: CGFloat = 4
    static let codeHintTop: CGFloat = 18
    static let codeActsTop: CGFloat = 26
    static let codeActsGap: CGFloat = 10
    static let codeBottom: CGFloat = 16
    /// The scanner's pill, over the camera.
    static let scanPill: CGFloat = 44
    static let scanPillSide: CGFloat = 18
    static let scanPillBottom: CGFloat = 40
    /// How long the pill stays up.
    static let scanPillHold: Duration = .seconds(2)
}

/// What a code holds, and the picture of it.
nonisolated enum YourCode {
    static let scheme = "blockparty"
    static let host = "neighbor"
    /// The website's form, once app links are on (BP app backlog 10).
    static let webHosts: Set<String> = ["blockpartymn.com", "www.blockpartymn.com"]
    static let webPath = "n"

    /// Your link, the code's words.
    static func link(for userID: String) -> URL {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        parts.path = "/" + userID.lowercased()
        return parts.url!
    }

    /// The neighbour a link names, as a lowercase id: the app link or the website's `/n/<id>`.
    /// Anything else, and any id that isn't one, is nil: a scanned code is anyone's words.
    static func userID(from url: URL) -> String? {
        let path = url.pathComponents.filter { $0 != "/" }
        let id: String? = switch url.scheme?.lowercased() {
        case scheme: url.host()?.lowercased() == host && path.count == 1 ? path[0] : nil
        case "https": webHosts.contains(url.host()?.lowercased() ?? "") && path.count == 2 && path[0] == webPath ? path[1] : nil
        default: nil
        }
        return id.flatMap(UUID.init(uuidString:)).map { $0.uuidString.lowercased() }
    }

    static func userID(from scanned: String) -> String? {
        URL(string: scanned.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(userID(from:))
    }

    /// The QR code of `url`, black on white with `margin` modules of white round it, `scale`
    /// pixels a module. Drawn with no smoothing, it stays sharp at any size.
    static func image(for url: URL, scale: CGFloat = 1, margin: CGFloat = 0) -> UIImage? {
        let qr = CIFilter.qrCodeGenerator()
        qr.message = Data(url.absoluteString.utf8)
        qr.correctionLevel = "M"
        guard let code = qr.outputImage else { return nil }
        let size = code.extent.insetBy(dx: -margin, dy: -margin)
        let framed = code.composited(over: CIImage(color: .white).cropped(to: size))
            .transformed(by: CGAffineTransform(translationX: margin, y: margin).scaledBy(x: scale, y: scale))
        guard let cg = CIContext().createCGImage(framed, from: framed.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// You, as your code shows you.
struct CodeOwner: Equatable {
    var id: String
    var name: String
    var avatarUrl: String?
    /// "October 2026".
    var since: String?

    #if DEBUG
    /// INVENTED, for `-town-samples`: a neighbour on a bundled town photo.
    static let sample = CodeOwner(id: "6f1c2a9e-3b4d-4e8f-9a1b-2c3d4e5f6a7b", name: "Jordan Ahn",
                                  avatarUrl: Bundle.main.url(forResource: "sju-arboretum-trail", withExtension: "jpg")?.absoluteString,
                                  since: "March 2026")
    #endif
}

/// Your code in Apple's sheet, as tall as what it holds. Scan a code opens the scanner over it;
/// a neighbour found there closes both and `open` pushes their page.
struct YourCodeSheet: View {
    let open: (Neighbor) -> Void
    @StateObject private var model = ProfileModel()
    @ObservedObject private var auth = AuthStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var scanning = false
    @State private var height: CGFloat = 640
    /// Your code, drawn once for the card and once framed in white for Share.
    @State private var codes: (card: UIImage, share: UIImage)?

    private var owner: CodeOwner? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-town-samples") { return .sample }
        #endif
        return auth.userId.map { CodeOwner(id: $0, name: model.displayName, avatarUrl: model.avatarUrl, since: model.sinceLabel) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Avatar(avatarUrl: owner?.avatarUrl, size: FriendsMetric.codeFace, outlined: true)
                .overlay(Circle().strokeBorder(Hue.surface, lineWidth: FriendsMetric.codeFaceRing))
                .mapFloatShadow()
            // A space until they arrive, so the sheet is as tall from the start.
            Text(owner.map(\.name).flatMap { $0.isEmpty ? nil : $0 } ?? " ")
                .font(.eventDisplay(26))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
                .padding(.top, FriendsMetric.codeNameTop)
                .accessibilityAddTraits(.isHeader)
            Text(owner?.since.map { "Neighbor since \($0)" } ?? " ")
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.top, FriendsMetric.codeSinceTop)
            code
                .padding(.top, FriendsMetric.codeCardTop)
            Text("Let a neighbor scan this.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.top, FriendsMetric.codeHintTop)
            HStack(spacing: FriendsMetric.codeActsGap) {
                Button { scanning = true } label: {
                    action("Scan a code", glyph: "viewfinder", ink: true)
                }
                .buttonStyle(PressableStyle())
                if let picture = codes?.share {
                    let image = Image(uiImage: picture)
                    ShareLink(item: image, message: Text(FriendsInvite.message),
                              preview: SharePreview("Your code", image: image)) {
                        action("Share", glyph: "square.and.arrow.up", ink: false)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.top, FriendsMetric.codeActsTop)
            .padding(.horizontal, FriendsMetric.inviteSide)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, FriendsMetric.codeTop)
        .padding(.bottom, FriendsMetric.codeBottom)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Hue.paper)
        .task { await model.load() }
        .task(id: owner?.id) {
            guard let owner else { codes = nil; return }
            let link = YourCode.link(for: owner.id)
            if let card = YourCode.image(for: link),
               let share = YourCode.image(for: link, scale: FriendsMetric.codeScale, margin: FriendsMetric.codeMargin) {
                codes = (card, share)
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            CodeScanner(me: owner?.id) { neighbor in
                scanning = false
                dismiss()
                open(neighbor)
            }
        }
    }

    /// The code on its white card. It says nothing to VoiceOver but what it is.
    private var code: some View {
        RoundedRectangle(cornerRadius: FriendsMetric.codeCardRadius, style: .continuous)
            .fill(Hue.surface)
            .overlay {
                RoundedRectangle(cornerRadius: FriendsMetric.codeCardRadius, style: .continuous)
                    .strokeBorder(Hue.hairline, lineWidth: FriendsMetric.hairline)
            }
            .shadow(color: Hue.ink.opacity(0.08), radius: 15, y: 8)
            .overlay {
                if let picture = codes?.card {
                    Image(uiImage: picture)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: FriendsMetric.code, height: FriendsMetric.code)
                }
            }
            .frame(width: FriendsMetric.codeCard, height: FriendsMetric.codeCard)
            .accessibilityElement()
            .accessibilityLabel("Your code")
            .accessibilityAddTraits(.isImage)
    }

    private func action(_ word: String, glyph: String, ink: Bool) -> some View {
        Label(word, systemImage: glyph)
            .font(.sansSemibold(17))
            .foregroundStyle(ink ? Hue.surface : Hue.ink)
            .frame(maxWidth: .infinity)
            .frame(height: FriendsMetric.invite)
            .background(Capsule().fill(ink ? Hue.ink : Hue.fill))
    }
}

/// Scan a code: Apple's scanner over the whole screen, our white round X over it. A Block Party
/// code is read (`get_neighbor`) and hands back that neighbour; any other code, or one naming
/// nobody you can find, shows the pill for a moment and the scanner keeps looking.
struct CodeScanner: View {
    /// Your own id: your own code finds nothing.
    let me: String?
    let found: (Neighbor) -> Void

    enum Camera { case asking, ready, off, missing }
    private typealias Round = FeedEventDetailDestination.Metric

    @State private var camera = Camera.asking
    @State private var pill: String?
    @State private var reading = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch camera {
            case .asking: Hue.ink.ignoresSafeArea()
            case .ready: Scanner(seen: seen).ignoresSafeArea()
            case .off:
                Hue.paper.ignoresSafeArea()
                ContactsNote(glyph: "camera", title: "Camera is off",
                             line: "Allow Block Party to use the camera to scan a neighbor's code.",
                             button: "Allow in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .frame(maxHeight: .infinity)
            case .missing:
                Hue.paper.ignoresSafeArea()
                ContactsNote(glyph: "camera", title: nil, line: "This iPhone can't scan codes.")
                    .frame(maxHeight: .infinity)
            }
            // The Event page's white round button, where its back sits.
            FeedEventDetailDestination.circleButton(glyph: Image(systemName: "xmark"), label: "Close",
                                                    reduceMotion: reduceMotion) { dismiss() }
                .padding(.leading, Round.inset - (Round.tapBox - Round.button) / 2)
                .padding(.top, Round.buttonTop - (Round.tapBox - Round.button) / 2)
        }
        .overlay(alignment: .bottom) {
            if let pill {
                Text(pill)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .padding(.horizontal, FriendsMetric.scanPillSide)
                    .frame(height: FriendsMetric.scanPill)
                    .background(Capsule().fill(Hue.surface).mapFloatShadow())
                    .padding(.bottom, FriendsMetric.scanPillBottom)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 12)))
            }
        }
        .animation(Motion.snappy, value: pill)
        .task(id: pill) {
            guard pill != nil else { return }
            try? await Task.sleep(for: FriendsMetric.scanPillHold)
            pill = nil
        }
        .task { camera = await Self.askCamera() }
    }

    /// The camera, asked for here and nowhere else. A simulator has no scanner.
    private static func askCamera() async -> Camera {
        guard DataScannerViewController.isSupported else { return .missing }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .ready
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video) ? .ready : .off
        default: return .off
        }
    }

    private func seen(_ words: String) {
        guard !reading else { return }
        guard let id = YourCode.userID(from: words) else {
            say("Not a Block Party code")
            return
        }
        guard id != me?.lowercased() else {
            say("That's your code")
            return
        }
        reading = true
        Task {
            defer { reading = false }
            do {
                if let neighbor = try await Neighbor.read(id) {
                    Haptics.success()
                    found(neighbor)
                } else {
                    say("Not a Block Party code")
                }
            } catch {
                say("Check your connection and try again.")
            }
        }
    }

    private func say(_ words: String) {
        Haptics.error()
        pill = words
        AccessibilityNotification.Announcement(words).post()
    }
}

/// VisionKit's scanner for QR codes, with Apple's own box round what it sees and its guidance.
private struct Scanner: UIViewControllerRepresentable {
    let seen: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, recognizesMultipleItems: false,
                                                isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true,
                                                isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        // A turn late, once it's in the window (swift-traps.md, UIKit inside SwiftUI).
        Task { try? scanner.startScanning() }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.seen = seen
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(seen: seen) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var seen: (String) -> Void
        init(seen: @escaping (String) -> Void) { self.seen = seen }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let code) in added {
                if let words = code.payloadStringValue { seen(words) }
            }
        }
    }
}

extension Neighbor {
    /// One neighbour by id (`get_neighbor`); under DEBUG `-town-samples` the sample by that id. nil
    /// for nobody you can find.
    static func read(_ id: String) async throws -> Neighbor? {
        switch RealLifeActions.backend(for: ProcessInfo.processInfo.arguments) {
        case .live: return try await CommunityAPI(auth: AuthStore.shared).getNeighbor(id)
        case .offline: throw URLError(.notConnectedToInternet)
        case .samples: return Neighbor.samples.first { $0.id == id }
        }
    }
}
