//
//  EditPostTests.swift
//  BlockPartyTests — editing your own post (BP app town-feed 44): who may, what Edit opens on, when Done lights, what
//  goes out, how the check's answer reads, and that every list shows a saved edit at once.
//

import XCTest
@testable import BlockParty

@MainActor
final class EditPostTests: XCTestCase {
    private let pal = TownPost.Person(id: "00000000-0000-0000-0000-0000000000d4", name: "Sam Lee")
    private let habit = AtName(kind: .place, id: "aa01", name: "Bad Habit Brewing")

    private func post(words: String = "Farmers market was packed this moring.", place: String? = "St. Joseph Farmers Market",
                      photo: URL? = URL(string: "https://example.com/p.jpg"), names: [AtName] = []) -> TownPost {
        TownPost(id: "post-1", poster: .init(id: "ABC-123", name: "Avery Lund"), words: words, photo: photo, aspect: 1.49,
                 place: place, tagged: [pal], atNames: names, friendsOnly: true, posted: .now, leavesAt: .now.addingTimeInterval(86_400))
    }

    func testOnlyThePosterSeesEdit() {
        let mine = post()
        XCTAssertTrue(mine.editable(by: "abc-123"), "the same account, whatever its case")
        XCTAssertFalse(mine.editable(by: "someone-else"))
        XCTAssertFalse(mine.editable(by: nil), "signed out")
        XCTAssertFalse(mine.editable(by: ""))
    }

    func testEditOpensOnThePostsWordsPlaceNamesAndAudience() {
        let draft = NewPostDraft(editing: post(names: [habit]))
        XCTAssertEqual(draft.words, "Farmers market was packed this moring.")
        XCTAssertEqual(draft.location, "St. Joseph Farmers Market")
        XCTAssertEqual(draft.atNames, [habit])
        XCTAssertTrue(draft.friendsOnly, "the pill shows who can see it, locked")
        XCTAssertEqual(NewPostDraft(editing: post(place: nil)).location, nil)
    }

    func testDoneLightsOnlyForAChangeToTheWordsOrThePlace() {
        let original = post()
        var draft = NewPostDraft(editing: original)
        XCTAssertFalse(draft.changed(from: original))
        draft.words += "  \n"
        XCTAssertFalse(draft.changed(from: original), "spaces at the end aren't a change")
        draft.words = "Farmers market was packed this morning."
        XCTAssertTrue(draft.changed(from: original))
        draft = NewPostDraft(editing: original)
        draft.place = "Centennial Park"
        XCTAssertTrue(draft.changed(from: original))
        draft.place = "   "
        XCTAssertTrue(draft.changed(from: original), "taking the Place away is a change")
        XCTAssertFalse(NewPostDraft(editing: post(place: nil)).changed(from: post(place: "  ")), "a blank Place is none")
    }

    func testAnEditSendsOnlyTheTrimmedWordsThePlaceAndTheNamesStillInTheWords() {
        var draft = NewPostDraft(editing: post(names: [habit, AtName(kind: .user, id: pal.id, name: "Sam Lee")]))
        draft.words = "  Pint night at @Bad Habit Brewing \n"
        draft.place = " Bad Habit Brewing "
        XCTAssertEqual(draft.edit(of: post()),
                       PostEditInput(id: "post-1", words: "Pint night at @Bad Habit Brewing", place: "Bad Habit Brewing", atNames: [habit]))
    }

    func testAPhotoPostMayLoseAllItsWordsAWordsOnlyPostMayNot() {
        let model = NewPostModel()
        model.startEditing(post())
        XCTAssertFalse(model.ready, "nothing changed yet")
        model.draft.words = ""
        XCTAssertTrue(model.ready, "the photo stays, so the post still has something")
        XCTAssertTrue(model.hasPhoto)
        let wordsOnly = NewPostModel()
        wordsOnly.startEditing(post(photo: nil))
        wordsOnly.draft.words = "   "
        XCTAssertFalse(wordsOnly.ready)
        XCTAssertTrue(wordsOnly.edited, "the X still asks before throwing the change away")
    }

    func testASavedEditChangesOnlyTheWordsPlaceAndNames() {
        let before = post()
        let after = before.edited(PostEditInput(id: "post-1", words: "New words", place: nil, atNames: [habit]))
        XCTAssertEqual(after.words, "New words")
        XCTAssertNil(after.place)
        XCTAssertEqual(after.atNames, [habit])
        XCTAssertEqual(after.photo, before.photo)
        XCTAssertEqual(after.tagged, before.tagged)
        XCTAssertEqual(after.friendsOnly, before.friendsOnly)
        XCTAssertEqual(after.poster, before.poster)
        XCTAssertEqual(before.edited(PostEditInput(id: "other", words: "x", place: nil, atNames: [])), before,
                       "another post's edit leaves this one alone")
    }

    func testEveryListShowsASavedEditAtOnce() {
        let hides = FeedHides(choose: { _ in nil }, readMuted: { [] }, deletePost: { _ in })
        let mine = post()
        XCTAssertEqual(hides.edited(mine), mine)
        hides.saved(PostEditInput(id: "post-1", words: "Fixed", place: "Centennial Park", atNames: []))
        XCTAssertEqual(hides.edited(mine).words, "Fixed")
        XCTAssertEqual(hides.edited(mine).place, "Centennial Park")
        let other = TownPost(id: "post-2", poster: mine.poster, words: "Untouched", posted: .now, leavesAt: .now)
        XCTAssertEqual(hides.edited(other).words, "Untouched")
    }

    func testTheChecksAnswerReads() {
        XCTAssertEqual(PostEditAnswer.from(status: 200, ok: true, reason: ""), .saved)
        XCTAssertEqual(PostEditAnswer.from(status: 200, ok: false, reason: " Keep it kind. "), .refused("Keep it kind."))
        XCTAssertEqual(PostEditAnswer.from(status: 200, ok: false, reason: nil), .refused(PostEditCopy.refused))
        XCTAssertEqual(PostEditAnswer.from(status: 200, ok: nil, reason: nil), .noAnswer, "an answer that didn't read")
        XCTAssertEqual(PostEditAnswer.from(status: 429, ok: nil, reason: nil), .limit)
        XCTAssertEqual(PostEditAnswer.from(status: 410, ok: nil, reason: nil), .gone)
        XCTAssertEqual(PostEditAnswer.from(status: 403, ok: nil, reason: nil), .gone)
        XCTAssertEqual(PostEditAnswer.from(status: 502, ok: nil, reason: nil), .noAnswer)
        XCTAssertNil(PostEditAnswer.saved.problem)
        XCTAssertEqual(PostEditAnswer.limit.problem, PostEditCopy.limit)
        XCTAssertEqual(PostEditAnswer.noAnswer.problem, "Couldn't check it. Try again.")
    }
}
