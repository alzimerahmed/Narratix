//
//  NSManagedObjectContext+LibraryItem.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import CoreData
import Foundation

extension NSManagedObjectContext {
  /// The managed `LibraryItem` a path resolves to — one lookup, on whatever
  /// context is passed. The module-qualified name stays in here: bare
  /// `LibraryItem` collides with `DeveloperToolsSupport.LibraryItem`.
  /// (Both queue-like services carried this helper privately — one copy now.)
  func libraryItem(for relativePath: String) -> BookPlayerKit.LibraryItem? {
    let fetch = BookPlayerKit.LibraryItem.fetchRequest()
    /// Literal key: `#keyPath` rejects the module-qualified type
    fetch.predicate = NSPredicate(format: "%K == %@", "relativePath", relativePath)
    fetch.fetchLimit = 1
    return try? self.fetch(fetch).first
  }
}
