//
//  FeedInterestEditorDestination.swift
//  Block Party — Edit profile from a Town card's menu, once Your profile has been read.
//

import SwiftUI

struct FeedInterestEditorDestination: View {
    @Environment(ProfileModel.self) private var model

    var body: some View {
        Group {
            if model.loaded {
                EditProfileView(model: model)
                    .transition(.opacity)
            } else {
                EditProfileSkeleton()
                    .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: model.loaded)
        .task { if !model.loaded { await model.read() } }
    }
}

/// The editor's own layout in placeholder shapes — the 132pt avatar well, the name
/// field, the interest grid — so the real form resolves in place instead of
/// replacing a centred spinner. The screen title renders for REAL: it is known
/// before the profile fetch, so standing in for it would be a lie that also costs a
/// layout jump on swap-in.
struct EditProfileSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("Edit profile")
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)

            VStack(spacing: 26) {
                SkeletonCircle(diameter: 132)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    SkeletonLine(widthFraction: 0.14, height: 10)
                    SkeletonBlock(cornerRadius: Radius.button).frame(height: 48)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SkeletonLine(widthFraction: 0.26, height: 10)
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 10) {
                            SkeletonBlock(cornerRadius: Radius.button).frame(height: 38)
                            SkeletonBlock(cornerRadius: Radius.button).frame(height: 38)
                        }
                    }
                }
            }
            .padding(24)
            .shimmering()
            .accessibilityLabel("Loading your profile")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Hue.paper.ignoresSafeArea())
    }
}
