//
//  FeedInterestEditorDestination.swift
//  Block Party — loads the real profile before mounting the existing editor.
//

import SwiftUI

struct FeedInterestEditorDestination: View {
    @StateObject private var model = ProfileModel()

    var body: some View {
        Group {
            if model.loaded {
                EditProfileView(model: model)
            } else {
                ProgressView()
                    .tint(Hue.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Hue.paper)
            }
        }
        .task {
            guard !model.loaded, !model.loading else { return }
            await model.load()
        }
    }
}
