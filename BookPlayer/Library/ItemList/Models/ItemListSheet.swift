//
//  ItemListSheet.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 4/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Foundation

/// Represents all possible sheet types in ItemListView
enum ItemListSheet: Identifiable {
  case itemDetails(SimpleLibraryItem)
  case queuedTasks
  case foldersSelection
  case libraryOptions
  /// The collections shelf browser (list → detail)
  case collections
  /// The "Add to Collection" membership picker for the current selection
  case collectionPicker
  /// Browse-by surface (series + authors)
  case seriesBrowser

  var id: String {
    switch self {
    case .itemDetails(let item):
      return "itemDetails-\(item.id)"
    case .queuedTasks:
      return "queuedTasks"
    case .foldersSelection:
      return "foldersSelection"
    case .libraryOptions:
      return "libraryOptions"
    case .collections:
      return "collections"
    case .collectionPicker:
      return "collectionPicker"
    case .seriesBrowser:
      return "seriesBrowser"
    }
  }
}
