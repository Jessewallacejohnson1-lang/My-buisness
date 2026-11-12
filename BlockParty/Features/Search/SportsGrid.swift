//
//  SportsGrid.swift
//  Block Party — Search's Sports chip (BP app school-search 04): "BlockParty. Sports" where Apple Sports has its logo
//  and "Sports", on the app's dark colours, over every local school's logo in Apple's discs, three to a row, colleges
//  first, then high schools, then Kennedy. A disc opens the school's page (`TeamPage`). The header's sizes for this
//  chip are `SearchHead.sports`; with nothing typed the field and pills ride the grid's scroll away, as the mock's do.
//  Mock: `references/school-search/sports-bp-mock-2.html` (version 8).
//

import SwiftUI

nonisolated extension SearchMetric {
    // The Sports chip (school-search 04): "BlockParty. Sports" where Apple Sports has its logo and "Sports", on the
    // app's dark colours. The mock Jesse picked (`references/school-search/sports-bp-mock-2.html`, version 8),
    // measured at 3x beside Apple Sports (`mobbin/1.jpg`), from a 59 pt safe area: the wordmark 35 pt tall and
    // "Sports" 34 pt, 9 pt apart on one baseline 26 pt down; the field 54-97, the chips 109-143, the first disc 167.
    static let sportsWordmark: CGFloat = 35.2
    static let sportsWord: CGFloat = 34
    static let sportsWordGap: CGFloat = 9
    /// The title's room above the field, and how far its words sit up off that room's foot (tuned on the build so
    /// the baseline lands 26 pt down).
    static let sportsTitle: CGFloat = 37
    static let sportsTitleLift: CGFloat = 2.3
    static let sportsFieldTop: CGFloat = 17
    static let sportsFieldHeight: CGFloat = 43
    static let sportsFieldIconLead: CGFloat = 14
    static let sportsFieldIconGap: CGFloat = 8
    /// Apple's field and chips sit 8 pt in; the words over them keep the page's 16.
    static let sportsSide: CGFloat = 8
    static let sportsChipsTop: CGFloat = 9
    /// Every chip's glass is ink at 5%, the field's at 7%.
    static let sportsChipGlass: Double = 0.05
    static let sportsFieldGlass: Double = 0.07
    /// The warm-grey fade from the top, to paper by 440 pt, through its middle shade at 240 pt.
    static let sportsFade: CGFloat = 440
    static let sportsFadeMid: CGFloat = 240
    /// Apple's discs (`mobbin/1.jpg`): 80 pt, three to a row 154 pt apart (a 132 pt cell and 22 under it), the logo
    /// in a 45 pt box, the name 8 pt under the disc. The first sits 24 pt under the chips.
    static let discTop: CGFloat = 24
    static let disc: CGFloat = 80
    static let discLogo: CGFloat = 45
    static let discCell: CGFloat = 132
    static let discRowGap: CGFloat = 22
    static let discNameGap: CGFloat = 8
    static let discSkeletonName: CGFloat = 12
    /// A pressed disc sinks to the mock's 90%, its name holding still.
    static let discSink: CGFloat = 0.9
    /// Everything above the Sports chip's content, from the safe area's top.
    static let sportsHeadHeight: CGFloat = sportsTitle + sportsFieldTop + sportsFieldHeight + sportsChipsTop
        + chipsHeight + headBottom
}

/// Search's header, Search's own or the Sports chip's (school-search 04): the one choice behind every size and
/// colour that differs between them.
struct SearchHead {
    /// "BlockParty. Sports" over the field.
    let titled: Bool
    let fieldTop: CGFloat
    let fieldHeight: CGFloat
    let fieldRadius: CGFloat
    let fieldGlyph: CGFloat
    let fieldIconLead: CGFloat
    let fieldIconGap: CGFloat
    let fieldWords: CGFloat
    let prompt: String
    /// The prompt and the magnifier.
    let faint: Color
    let fieldFill: Color
    let fieldGlass: Glass
    let chipGlass: Glass
    /// The selected pill's words, the page's paper inside ink.
    let chipWordsOn: Color
    /// The field's and pills' inset from the screen's sides.
    let side: CGFloat
    let chipsTop: CGFloat
    /// Everything above the content, from the safe area's top.
    let height: CGFloat

    /// Search's own, from Jesse's Search mockup v7.
    static let plain = SearchHead(
        titled: false, fieldTop: SearchMetric.fieldTop, fieldHeight: SearchMetric.fieldHeight,
        fieldRadius: Radius.searchField, fieldGlyph: 15, fieldIconLead: SearchMetric.fieldIconLead,
        fieldIconGap: SearchMetric.fieldIconGap, fieldWords: 16, prompt: "Search", faint: Hue.searchFaint,
        fieldFill: Hue.searchField, fieldGlass: .identity, chipGlass: .identity, chipWordsOn: Hue.surface,
        side: SearchMetric.side, chipsTop: SearchMetric.chipsTop, height: SearchMetric.headHeight)

    /// Apple Sports' on the app's dark colours: a capsule of glass for the field, every pill glass, the prompt and
    /// magnifier in the dark ramp's grey.
    static let sports = SearchHead(
        titled: true, fieldTop: SearchMetric.sportsFieldTop, fieldHeight: SearchMetric.sportsFieldHeight,
        fieldRadius: SearchMetric.sportsFieldHeight / 2, fieldGlyph: 17, fieldIconLead: SearchMetric.sportsFieldIconLead,
        fieldIconGap: SearchMetric.sportsFieldIconGap, fieldWords: 17, prompt: "Schools and teams", faint: Hue.inkSecondary,
        fieldFill: .clear, fieldGlass: .regular.tint(Hue.ink.opacity(SearchMetric.sportsFieldGlass)),
        chipGlass: .regular.tint(Hue.ink.opacity(SearchMetric.sportsChipGlass)), chipWordsOn: Hue.paper,
        side: SearchMetric.sportsSide, chipsTop: SearchMetric.sportsChipsTop, height: SearchMetric.sportsHeadHeight)
}

/// The header carried by the Sports grid's scroll, 1:1 both ways, as the mock's field and pills scroll away with the
/// discs (the run's review). Its own view reading the box, so only it redraws as the scroll moves (`BarTravel`).
struct CarriedHeader<Content: View>: View {
    let travel: BarTravel
    @ViewBuilder let content: Content

    var body: some View {
        content.offset(y: -travel.points)
    }
}

/// "BlockParty. Sports" where Apple Sports has its logo and "Sports" (school-search 04): the app's wordmark and the
/// word in Inter Tight on one baseline, both in ink. No yellow on the screen.
struct SportsTitle: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SearchMetric.sportsWordGap) {
            BlockPartyWordmark(height: SearchMetric.sportsWordmark)
                // The artwork's baseline, measured on `Wordmark.png`: the B's foot, 171 of its 216 rows down.
                .alignmentGuide(.firstTextBaseline) { $0.height * 171 / 216 }
            Text("Sports")
                .font(.display(SearchMetric.sportsWord))
        }
        .foregroundStyle(Hue.ink)
        .padding(.horizontal, SearchMetric.side)
        .padding(.bottom, SearchMetric.sportsTitleLift)
        .frame(height: SearchMetric.sportsTitle, alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Block Party Sports")
        .accessibilityAddTraits(.isHeader)
    }
}

/// The Sports chip's ground: a warm grey at the top of the screen fading to the dark paper by 440 pt, the mock's
/// "darker fade" (Jesse, 2026-11-11), drawn from the screen's top wherever it shows.
struct SportsFade: View {
    var body: some View {
        LinearGradient(stops: [.init(color: Hue.sportsFadeTop, location: 0),
                               .init(color: Hue.sportsFadeMid, location: SearchMetric.sportsFadeMid / SearchMetric.sportsFade),
                               .init(color: Hue.paper, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: SearchMetric.sportsFade)
            // No smaller than offered, and no taller: a header's slice of it stays the header's height.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .background(Hue.paper)
            .clipped()
    }
}

/// The Sports chip (school-search 04): every school's logo in Apple Sports' disc, three to a row, its short name
/// under it, colleges first; a disc opens the school's page. Shimmering discs while the schools are read.
struct SportsGrid: View {
    @Environment(SearchModel.self) private var model

    var body: some View {
        Group {
            if model.isLoading(.school) {
                grid {
                    ForEach(0..<9, id: \.self) { _ in
                        VStack(spacing: SearchMetric.discNameGap) {
                            SkeletonCircle(diameter: SearchMetric.disc)
                            SkeletonLine(height: SearchMetric.discSkeletonName)
                                .frame(width: SearchMetric.disc * 0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: SearchMetric.discCell, alignment: .top)
                    }
                }
                .shimmering()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading")
                .transition(.opacity)
            } else {
                grid { ForEach(model.schoolDiscs) { SchoolDisc(item: $0) } }
                    .transition(.opacity)
            }
        }
        // The shimmering discs cross-fade into the schools (design.md, Loading).
        .animation(Motion.smooth, value: model.isLoading(.school))
        // 24 pt from the chips' foot to the first disc.
        .padding(.top, SearchMetric.discTop - (SearchMetric.chipsHeight - SearchMetric.chipHeight) / 2
                 - SearchMetric.headBottom)
    }

    private func grid(@ViewBuilder _ cells: () -> some View) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: SearchMetric.discRowGap) {
            cells()
        }
        .padding(.horizontal, SearchMetric.sportsSide)
    }
}

/// One school on the Sports chip: its logo fitted in Apple's 45 pt box on an 80 pt disc of the fill, its short
/// name under it in the secondary ink. A press sinks the disc alone, as the mock's does.
private struct SchoolDisc: View {
    let item: SearchItem
    @Environment(SearchModel.self) private var model

    var body: some View {
        if let team = item.team {
            NavigationLink(value: team) {
                VStack(spacing: SearchMetric.discNameGap) {
                    SinkingDisc(item: item)
                    Text(team.short)
                        .font(.sansSemibold(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: SearchMetric.discCell, alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(DiscPress())
            .simultaneousGesture(TapGesture().onEnded { model.remember(item.id) })
            .accessibilityLabel(item.name)
        }
    }
}

/// The disc under the finger: sinks on the app's press timing while the finger is down.
private struct SinkingDisc: View {
    let item: SearchItem
    @Environment(\.discPressed) private var pressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LogoDisc(logo: item.logo?.url, initial: item.initial, logoSide: SearchMetric.discLogo,
                 letter: .sansSemibold(20), disc: false)
            .frame(width: SearchMetric.discLogo, height: SearchMetric.discLogo)
            .frame(width: SearchMetric.disc, height: SearchMetric.disc)
            .background(Hue.fill, in: Circle())
            .scaleEffect(pressed && !reduceMotion ? SearchMetric.discSink : 1)
            .animation(Press.animation(down: pressed, reduceMotion: reduceMotion), value: pressed)
    }
}

/// Tells the disc inside that the finger is down; the cell itself holds still.
private struct DiscPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.discPressed, configuration.isPressed)
    }
}

private extension EnvironmentValues {
    @Entry var discPressed = false
}
