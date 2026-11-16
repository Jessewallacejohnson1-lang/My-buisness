//
//  SportsGrid.swift
//  Block Party — Search's Sports and Schools chips (BP app school-search 04, 10): "BlockParty. Sports" where Apple
//  Sports has its logo and "Sports", on the app's dark colours. Sports holds the sports in Apple's discs, three to a
//  row, this season's first; a sport opens its page of teams (`SportPage`). Schools holds every local school's logo in
//  the same discs, colleges first, then high schools, then Kennedy; a disc opens the school's page (`TeamPage`). With
//  nothing typed the field and pills ride the grid's scroll away, as the mock's do.
//  Mocks: `references/school-search/sports-bp-mock-2.html` (version 8), `references/sports-first/mock.html`.
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
    /// The magnifier and the prompt.
    static let sportsFieldGlyph: CGFloat = 17
    /// Apple's field and chips sit 8 pt in; the words over them keep the page's 16.
    static let sportsSide: CGFloat = 8
    static let sportsChipsTop: CGFloat = 9
    /// Every chip's glass is ink at 5%, the field's at 7%.
    static let sportsChipGlass: Double = 0.05
    static let sportsFieldGlass: Double = 0.07
    /// The warm-grey fade from the top, to paper by 440 pt, through its middle shade at 240 pt.
    static let sportsFade: CGFloat = 440
    static let sportsFadeMid: CGFloat = 240
    /// The Event calendar's light fade (BP app five-tabs 10, mock round 4): to paper by 640 pt, past the month.
    static let calendarFade: CGFloat = 640
    static let calendarFadeMid: CGFloat = 300
    /// Apple's discs (`mobbin/1.jpg`): 80 pt, three to a row 154 pt apart (a 132 pt cell and 22 under it), the logo
    /// in a 45 pt box, the name 8 pt under the disc. The first sits 24 pt under the chips.
    static let discTop: CGFloat = 24
    static let disc: CGFloat = 80
    static let discLogo: CGFloat = 45
    static let discCell: CGFloat = 132
    static let discRowGap: CGFloat = 22
    static let discNameGap: CGFloat = 8
    static let discSkeletonName: CGFloat = 12
    /// A team's second line under its school (Boys, Girls): the mock's fainter grey, the secondary ink at 62%.
    static let discDetailInk: Double = 0.62
    /// A pressed disc sinks to the mock's 90%, its name holding still.
    static let discSink: CGFloat = 0.9
    /// Everything above every pill's content, from the safe area's top (search-titles 02).
    static let sportsHeadHeight: CGFloat = sportsTitle + sportsFieldTop + sportsFieldHeight + sportsChipsTop
        + chipsHeight + headBottom
}

/// Search's header for each pill: "BlockParty." and the pill's word over a round field and the pills, in Sports' dark
/// colours (school-search 04) or the Event calendar's light ones (five-tabs 10) on every other pill (BP app
/// search-titles 02). Every size is the Sports one's (`SearchMetric.sports*`); this holds the words and colours that differ.
struct SearchHead {
    /// The word after "BlockParty.".
    let word: String
    let prompt: String
    /// The prompt and the magnifier.
    let faint: Color
    let chipGlass: Glass
    /// The selected pill's words, the page's paper inside ink.
    let chipWordsOn: Color

    /// Each pill's: its word and prompt (Jesse, search-titles, 2026-11-15), Sports alone dark.
    static func of(_ chip: SearchChip) -> SearchHead {
        switch chip {
        case .all: light(word: "Search", prompt: "Search")
        case .calendar: light(word: "Calendar", prompt: "Events")
        case .businesses: light(word: "Businesses", prompt: "Businesses")
        case .sports: sports
        case .schools: schools
        case .events: light(word: "Events", prompt: "Events")
        }
    }

    /// Apple Sports' on the app's dark colours: a capsule of glass for the field, every pill glass, the prompt and
    /// magnifier in the dark ramp's grey.
    static let sports = SearchHead(
        word: "Sports", prompt: "Sports and teams", faint: Hue.inkSecondary,
        chipGlass: .regular.tint(Hue.ink.opacity(SearchMetric.sportsChipGlass)), chipWordsOn: Hue.paper)

    /// Sports' own, with its word (school-search 10).
    static let schools = SearchHead(
        word: "Schools", prompt: "Schools and teams", faint: sports.faint, chipGlass: sports.chipGlass,
        chipWordsOn: sports.chipWordsOn)

    /// The Event calendar's (five-tabs 10), now every light pill's: the Sports header's shape, a round field and the
    /// pills in Search's own light colours (Jesse: "make it a lighter theme").
    /// Its pills stay plain; its field is Sports' glass, as every pill's is (`SearchPage.field`).
    private static func light(word: String, prompt: String) -> SearchHead {
        SearchHead(word: word, prompt: prompt, faint: Hue.searchFaint, chipGlass: .identity, chipWordsOn: Hue.surface)
    }
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

/// "BlockParty. Sports" where Apple Sports has its logo and "Sports" (school-search 04), and every other pill's word
/// in its place (search-titles 02): the app's wordmark and the word in Inter Tight on one baseline, both in ink. No
/// yellow on the screen.
struct SportsTitle: View {
    /// The pill's word: Search, Calendar, Businesses, Sports or Events.
    let word: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SearchMetric.sportsWordGap) {
            BlockPartyWordmark(height: SearchMetric.sportsWordmark)
                // The artwork's baseline, measured on `Wordmark.png`: the B's foot, 171 of its 216 rows down.
                .alignmentGuide(.firstTextBaseline) { $0.height * 171 / 216 }
            Text(word)
                .font(.display(SearchMetric.sportsWord))
                // "Businesses" is the longest word: on a 375 pt phone it shrinks a little rather than wrap. Only for
                // width: its own height stays, or the 37 pt room above the field shrinks every word.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Hue.ink)
        .padding(.horizontal, SearchMetric.side)
        .padding(.bottom, SearchMetric.sportsTitleLift)
        .frame(height: SearchMetric.sportsTitle, alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Block Party \(word)")
        .accessibilityAddTraits(.isHeader)
    }
}

/// The Sports chip's ground: a warm grey at the top of the screen fading to the dark paper by 440 pt, the mock's
/// "darker fade" (Jesse, 2026-11-11), drawn from the screen's top wherever it shows.
struct SportsFade: View {
    var top = Hue.sportsFadeTop
    var mid = Hue.sportsFadeMid
    var midAt = SearchMetric.sportsFadeMid
    var height = SearchMetric.sportsFade

    /// The Event calendar's: the same fade in light greys (BP app five-tabs 10).
    static let calendar = SportsFade(top: Hue.calendarFadeTop, mid: Hue.calendarFadeMid,
                                     midAt: SearchMetric.calendarFadeMid, height: SearchMetric.calendarFade)

    var body: some View {
        LinearGradient(stops: [.init(color: top, location: 0),
                               .init(color: mid, location: midAt / height),
                               .init(color: Hue.paper, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            // No smaller than offered, and no taller: a header's slice of it stays the header's height.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .background(Hue.paper)
            .clipped()
    }
}

/// The Schools chip (school-search 04, 10): every school's logo in Apple Sports' disc, three to a row, its short name
/// under it, colleges first; a disc opens the school's page. Shimmering discs while the schools are read.
struct SchoolsGrid: View {
    @Environment(SearchModel.self) private var model

    var body: some View {
        DiscGrid(loading: model.isLoading(.school)) {
            ForEach(model.schoolDiscs) { SchoolDisc(item: $0) }
        }
    }
}

/// The Sports chip (school-search 10, Jesse 2026-11-16: "i want sports on top then when you click into them you see
/// teams"): each sport the schools play in Apple Sports' disc, its symbol in the logo's 45 pt box, its name under it,
/// this season's first. A sport opens its page of teams. Shimmering discs while the schools are read.
struct SportsGrid: View {
    @Environment(SearchModel.self) private var model

    var body: some View {
        DiscGrid(loading: model.isLoading(.school)) {
            ForEach(model.sports) { sport in
                NavigationLink(value: sport) {
                    DiscCell(name: sport.name) {
                        SinkingDisc {
                            Image(systemName: sport.symbol)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Hue.ink)
                                .frame(width: SearchMetric.discLogo, height: SearchMetric.discLogo)
                        }
                    }
                }
                .buttonStyle(DiscPress())
                .accessibilityLabel(sport.name)
            }
        }
    }
}

/// A sport's teams from high school up (school-search 10, Jesse 2026-11-16: "any teams highschool and up", "Circles,
/// like sports"): its school's logo in the same disc, the school's short name under it and what tells its teams apart
/// (Boys, Girls) under that, colleges first. A disc opens the school's page, as the activity's row does.
struct SportPage: View {
    let sport: SportShelf
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            // The dark paper, flat: the bar's own ground over it meets it with no seam.
            Hue.paper.ignoresSafeArea()
            ScrollView {
                DiscGrid(loading: false) {
                    ForEach(sport.teams) { TeamDisc(team: $0) }
                }
                .padding(.top, PageMetric.bar)
                .padding(.bottom, SearchMetric.tabBarClearance)
            }
            PageBar(title: sport.name) { dismiss() }
        }
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Apple Sports' grid: three discs to a row, 24 pt under what's above, shimmering discs while it's read.
private struct DiscGrid<Cells: View>: View {
    let loading: Bool
    @ViewBuilder let cells: Cells

    var body: some View {
        Group {
            if loading {
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
                grid { cells }
                    .transition(.opacity)
            }
        }
        // The shimmering discs cross-fade into the discs (design.md, Loading).
        .animation(Motion.smooth, value: loading)
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

/// A disc and the words under it, in the grid's cell: the name in the secondary ink, and a fainter second line.
private struct DiscCell<Disc: View>: View {
    let name: String
    var detail = ""
    @ViewBuilder let disc: Disc

    var body: some View {
        VStack(spacing: SearchMetric.discNameGap) {
            disc
            VStack(spacing: 0) {
                Text(name)
                    .font(.sansSemibold(13))
                    .foregroundStyle(Hue.inkSecondary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.sansSemibold(13))
                        .foregroundStyle(Hue.inkSecondary.opacity(SearchMetric.discDetailInk))
                }
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: SearchMetric.discCell, alignment: .top)
        .contentShape(Rectangle())
    }
}

/// One team on a sport's page: its school's logo in the disc, the school and what tells the team apart under it.
private struct TeamDisc: View {
    let team: SportTeam
    @Environment(SearchModel.self) private var model

    var body: some View {
        if let opens = team.item.team {
            NavigationLink(value: opens) {
                DiscCell(name: team.school, detail: team.variant) {
                    SinkingDisc { LogoInDisc(item: team.item) }
                }
            }
            .buttonStyle(DiscPress())
            .simultaneousGesture(TapGesture().onEnded { model.remember(team.item.id) })
            .accessibilityLabel([team.school, team.item.name].joined(separator: ", "))
        }
    }
}


/// One school on the Schools chip: its logo fitted in Apple's 45 pt box on an 80 pt disc of the fill, its short
/// name under it in the secondary ink. A press sinks the disc alone, as the mock's does.
private struct SchoolDisc: View {
    let item: SearchItem
    @Environment(SearchModel.self) private var model

    var body: some View {
        if let team = item.team {
            NavigationLink(value: team) {
                DiscCell(name: team.short) {
                    SinkingDisc { LogoInDisc(item: item) }
                }
            }
            .buttonStyle(DiscPress())
            .simultaneousGesture(TapGesture().onEnded { model.remember(item.id) })
            .accessibilityLabel(item.name)
        }
    }
}

/// A school's logo fitted in Apple's 45 pt box.
private struct LogoInDisc: View {
    let item: SearchItem

    var body: some View {
        LogoDisc(logo: item.logo?.url, initial: item.initial, logoSide: SearchMetric.discLogo,
                 letter: .sansSemibold(20), disc: false)
            .frame(width: SearchMetric.discLogo, height: SearchMetric.discLogo)
    }
}

/// The disc under the finger: sinks on the app's press timing while the finger is down.
private struct SinkingDisc<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.discPressed) private var pressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
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
