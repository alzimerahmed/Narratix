//
//  SimpleCollection.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import Foundation

/// Value snapshot of an `ItemCollection` — the only form allowed to cross
/// contexts (never pass the managed object out). Local-only data; nothing in
/// here ever enters a sync payload.
public struct SimpleCollection: Identifiable, Hashable, Equatable {
  /// Stable identity — collections have no path, the uuid survives renames
  public var id: String { uuid }
  public let uuid: String
  public let title: String
  /// Member count at snapshot time (display only; refetch for decisions)
  public let itemCount: Int

  public init(uuid: String, title: String, itemCount: Int = 0) {
    self.uuid = uuid
    self.title = title
    self.itemCount = itemCount
  }

  public init(from collection: ItemCollection) {
    self.uuid = collection.uuid
    self.title = collection.title
    self.itemCount = collection.items?.count ?? 0
  }
}

/// A named shelf of library items for the browse-by surfaces (series, authors).
/// `items` are already in display order — a series group is ordered by book
/// number then title, an author group by title.
public struct SimpleItemGroup: Identifiable, Hashable, Equatable {
  public var id: String { name }
  public let name: String
  public let items: [SimpleLibraryItem]

  public init(name: String, items: [SimpleLibraryItem]) {
    self.name = name
    self.items = items
  }
}
