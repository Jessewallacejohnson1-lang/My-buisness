//
//  ShareSheetTests.swift
//  BlockPartyTests — the share sheet's card colours, what each share's card shows, and what Copy link copies
//  (BP app share-sheet 01).
//

import XCTest
@testable import BlockParty

@MainActor
final class ShareSheetTests: XCTestCase {

    // MARK: The card's colours

    /// The first look is the picture's hue at Hypelist's measured quiet: about 30% saturation and 31% brightness
    /// in the middle, greyer and lighter at the top, darker at the foot (SPEC.md, "Why it looks clean").
    func testColourLookIsThePicturesHueMutedToHypelists() {
        let orange: UInt32 = 0xE08A3C
        let look = ShareLook.colour(orange)
        let (hue, _, _) = ShareLook.hsv(of: orange)
        let (midHue, midS, midV) = ShareLook.hsv(of: look.mid)
        let (_, topS, topV) = ShareLook.hsv(of: look.top)
        let (_, _, footV) = ShareLook.hsv(of: look.foot)

        XCTAssertEqual(midHue, hue, accuracy: 0.02, "the picture's own hue")
        XCTAssertEqual(midS, 0.30, accuracy: 0.02)
        XCTAssertEqual(midV, 0.31, accuracy: 0.02)
        XCTAssertLessThan(topS, midS, "greyer at the top")
        XCTAssertGreaterThan(topV, midV, "lighter at the top")
        XCTAssertLessThan(footV, midV, "darker at the foot")
        XCTAssertTrue(look.dark, "white words on it")
    }

    /// The second look is a pale tint of the same hue, never the full BP yellow (Jesse: "not the harsh yellow").
    func testPaleLookIsALightTintOfTheSameHue() {
        let look = ShareLook.pale(0xE08A3C)
        for colour in [look.top, look.mid, look.foot] {
            let (_, s, v) = ShareLook.hsv(of: colour)
            XCTAssertLessThanOrEqual(s, 0.11 + 0.01)
            XCTAssertGreaterThanOrEqual(v, 0.92 - 0.01)
            XCTAssertNotEqual(colour, Hue.brandYellowHex)
        }
        XCTAssertFalse(look.dark, "ink words on it")
    }

    /// No picture, or a picture with no colourful hue (a called-off Event's grey): soft charcoal and a pale grey.
    func testNoColourTakesCharcoalAndPaleGrey() {
        XCTAssertEqual(ShareLook.colour(nil), .charcoal)
        XCTAssertEqual(ShareLook.colour(EventLook.grey), .charcoal)
        XCTAssertEqual(ShareLook.pale(nil), .paleGrey)
        XCTAssertEqual(ShareLook.pale(EventLook.grey), .paleGrey)
    }

    func testHSVRoundTrips() {
        for rgb: UInt32 in [0xE08A3C, 0x3C262D, 0x2E7D32, 0x1565C0] {
            let (h, s, v) = ShareLook.hsv(of: rgb)
            let back = ShareLook.hsv(h, s, v)
            for shift: UInt32 in [16, 8, 0] {
                XCTAssertEqual(Double(back >> shift & 0xFF), Double(rgb >> shift & 0xFF), accuracy: 1)
            }
        }
    }

    // MARK: What each share's card shows

    private static let photo = URL(string: "https://example.com/market.jpg")!

    private func item(imageUrl: String?) -> FeedCardItem {
        FeedCardItem(UpcomingEvent(id: "share-1", title: "Holiday Market", eventDate: "2033-12-06", startTime: "4:00 PM",
                                   location: "Minnesota St", goingCount: 3, createdAt: "2033-11-01T12:00:00Z",
                                   imageUrl: imageUrl, rsvpd: false))
    }

    func testAnEventsCardIsItsTitleDayAndPhoto() {
        let card = item(imageUrl: Self.photo.absoluteString)
        let payload = SharePayload.event(card)

        XCTAssertEqual(payload.story.title, "Holiday Market")
        XCTAssertEqual(payload.story.photo, Self.photo)
        XCTAssertTrue(payload.story.line.hasPrefix("Tue, Dec 6"), "the day written out, not the feed's capitals: \(payload.story.line)")
        XCTAssertTrue(payload.story.line.hasSuffix("4 PM"), payload.story.line)
        XCTAssertEqual(payload.card?.id, "share-1", "an Event goes to a chat")
        XCTAssertTrue(payload.isEvent)
    }

    func testAnEventWithNoPhotoHasTheYellowFace() {
        XCTAssertNil(SharePayload.event(item(imageUrl: nil)).story.photo)
    }

    func testOnlyAnEventGoesToAChat() {
        XCTAssertNil(SharePayload.appInvite().card)
        XCTAssertNil(SharePayload.event(title: "Farmers Market", dateLabel: "Sat", time: nil, location: nil).card)
    }

    // MARK: Copy link

    /// Events have no web page yet, so Copy link copies the share's words and the website (Jesse, round 2).
    func testCopyLinkCopiesTheWordsAndTheWebsite() {
        let payload = SharePayload.event(item(imageUrl: nil))
        XCTAssertEqual(payload.copied, payload.shareText + " blockpartymn.com")
    }
}
