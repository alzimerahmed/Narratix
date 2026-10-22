//
//  ImportDuplicates.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Foundation

/// One imported book that matches a book already in the library
struct ImportDuplicateMatch: Equatable {
  let imported: SimpleLibraryItem
  let existing: SimpleLibraryItem
}

/// An import that produced suspected duplicates, held while the warning is
/// on screen — its `items` continue into the placement flow once resolved.
struct PendingDuplicateImport: Equatable, Identifiable {
  let id = UUID()
  /// The import's top-level items, exactly as `insertItems` returned them
  let items: [SimpleLibraryItem]
  let matches: [ImportDuplicateMatch]
  /// The location the import landed in — the placement prompt needs it
  let node: LibraryNode
  /// The folder name a multi-file import suggested, carried so it survives the warning
  let suggestedFolderName: String?
}

/// The duplicate warning's three resolutions
enum DuplicateImportAction {
  /// Delete the new records + files, keep the library's
  case skip
  /// Keep both — the import proceeds untouched
  case importAnyway
  /// Delete the library's records + files (+ cloud copies), keep the imports
  case replace
}

/// Title + duration matching between what an import just created and what's
/// already in the library. Pure lookups over `filterContents` — the file has
/// no reason to be hashed when title+duration already catches the real cases
/// (a re-dropped file, the same book in two folder drops).
enum ImportDuplicateDetector {
  /// Same tolerance the download verification uses between a remote
  /// duration and the file's: 2% of the longer one, with a 2s floor
  static func durationsMatch(_ a: Double, _ b: Double) -> Bool {
    let tolerance = max(2.0, max(a, b) * 0.02)
    return abs(a - b) <= tolerance
  }

  /// "The Book " and "the book" are the same book; diacritics too
  static func normalized(_ title: String) -> String {
    title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The books an import created — loose books themselves, and the books
  /// inside imported folders (a folder's own row is a container, not a book)
  static func importedBooks(
    of items: [SimpleLibraryItem],
    libraryService: LibraryServiceProtocol
  ) -> [SimpleLibraryItem] {
    items.flatMap { item -> [SimpleLibraryItem] in
      if item.type == .book { return [item] }
      return libraryService.filterContents(
        at: item.relativePath,
        query: nil,
        scope: .book,
        limit: nil,
        offset: nil
      ) ?? []
    }
  }

  /// Pairs each just-imported book with the first library book carrying the
  /// same title and (about) the same duration. The imports' own paths are
  /// excluded, so a batch can't match itself.
  static func findDuplicates(
    of imported: [SimpleLibraryItem],
    libraryService: LibraryServiceProtocol
  ) -> [ImportDuplicateMatch] {
    let importedBooks = Self.importedBooks(of: imported, libraryService: libraryService)
    guard !importedBooks.isEmpty else { return [] }

    let importedPaths = Set(importedBooks.map(\.relativePath))
    let existing = (
      libraryService.filterContents(
        at: nil,
        query: nil,
        scope: .book,
        limit: nil,
        offset: nil
      ) ?? []
    ).filter { !importedPaths.contains($0.relativePath) }

    return importedBooks.compactMap { book in
      let title = normalized(book.title)
      guard let match = existing.first(where: {
        normalized($0.title) == title && durationsMatch($0.duration, book.duration)
      }) else { return nil }
      return ImportDuplicateMatch(imported: book, existing: match)
    }
  }
}
