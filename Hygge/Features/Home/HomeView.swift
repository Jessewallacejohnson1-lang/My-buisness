//
//  HomeView.swift
//  Hygge — Home / Timeline. Masthead, weather, today's events, around town, quest.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = HomeModel()

    private var api: CommunityAPI { CommunityAPI(auth: auth) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Masthead(name: model.name)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                WeatherBar()
                    .padding(.horizontal, 18)

                todaySection
                    .padding(.horizontal, 18)

                AroundTownCarousel()

                QuestSection(quest: model.quest, count: model.questCount, done: model.questDone) {
                    Task { await model.completeQuest(api) }
                }
                .padding(.horizontal, 18)

                Color.clear.frame(height: 96) // clear the floating tab bar
            }
        }
        .background(Hue.canvas)
        .refreshable { await model.load(api) }
        .task { await model.load(api) }
    }

    @ViewBuilder
    private var todaySection: some View {
        if model.loading && !model.loaded {
            TodayLoadingCard()
        } else if model.today.isEmpty {
            TodayCard()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Today")
                        .font(.displaySemi(22))
                        .foregroundStyle(Hue.ink)
                    Spacer()
                    Text("\(model.today.count) thing\(model.today.count == 1 ? "" : "s")")
                        .font(.mono(12))
                        .monospacedDigit()
                        .foregroundStyle(Hue.ink3)
                }
                ForEach(model.today) { event in
                    EventRow(event: event) {
                        Task { await model.toggleRsvp(api, event) }
                    }
                }
            }
        }
    }
}

/// Subtle placeholder while today's events load.
struct TodayLoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 6).fill(Hue.paper200).frame(width: 80, height: 12)
            RoundedRectangle(cornerRadius: 6).fill(Hue.paper200).frame(width: 200, height: 20)
            RoundedRectangle(cornerRadius: 6).fill(Hue.paper200).frame(maxWidth: .infinity).frame(height: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hyggeCard(padding: 18)
        .redacted(reason: .placeholder)
    }
}
