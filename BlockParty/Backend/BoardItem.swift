//
//  BoardItem.swift
//  Block Party — the row model `CommunityAPI.getTodayInStJoe()` returns.
//
//  Data (see CommunityAPI.getTodayInStJoe): published board_items — today's
//  events first (by start time), then null-start announcements published in the
//  last 48h — first 3 rows. `timeLabel` is present for dated events; `url` is
//  the item's source_url, meant to open in an in-app SFSafariViewController.
//
//  This model previously lived alongside the "Today in St. Joe" hero card in
//  Features/Home. That card was never mounted and has been removed; the model
//  stays because CommunityAPI (which mirrors @hygge/core 1:1) returns it.
//

import Foundation

struct BoardItem: Identifiable, Hashable {
    let id: String
    let title: String
    let timeLabel: String?
    let url: URL?
}
