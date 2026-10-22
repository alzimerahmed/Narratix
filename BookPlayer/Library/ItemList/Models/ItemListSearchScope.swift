//
//  ItemListSearchScope.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 10/8/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import SwiftUI

enum ItemListSearchScope: String, CaseIterable, Identifiable {
  var id: Self { self }

  case all, books, folders

  var title: LocalizedStringKey {
    switch self {
    case .all: "All"
    case .books: "books_title"
    case .folders: "folders_title"
    }
  }

  /// Maps the UI scope to the Core Data item type used by `LibraryService.filterContents`.
  /// `nil` means no type restriction (all items).
  var itemTypeScope: SimpleItemType? {
    switch self {
    case .all: nil
    case .books: .book
    case .folders: .folder
    }
  }
}

/// The library's listening-state triage filter (New / Started / Finished / DNF).
/// `.all` means no state restriction — the list's default.
enum ItemListeningFilter: String, CaseIterable, Identifiable {
  var id: Self { self }

  case all, new, started, finished, didNotFinish

  var title: LocalizedStringKey {
    switch self {
    case .all: "filter_all_title"
    case .new: "filter_new_title"
    case .started: "filter_started_title"
    case .finished: "filter_finished_title"
    case .didNotFinish: "filter_did_not_finish_title"
    }
  }

  /// Maps to the state predicate used by `LibraryService.filterContents`.
  /// `nil` means no state restriction (all items).
  var listeningState: ListeningState? {
    switch self {
    case .all: nil
    case .new: .notStarted
    case .started: .inProgress
    case .finished: .finished
    case .didNotFinish: .didNotFinish
    }
  }
}
