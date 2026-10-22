//
//  LibraryBackupService.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Foundation

/// Local JSON backup of everything the library knows about the user's books —
/// playback state, metadata, bookmarks, collections, series, DNF and notes.
///
/// # Format v1
///
/// ```json
/// {
///   "formatVersion": 1,
///   "createdAt": "<ISO8601>",
///   "app": "Narratix", "appVersion": "5.x",
///   "library": {
///     "lastPlayedPath": "Folder/book.m4b" | null,
///     "items": [Item],          // books, folders and bound volumes
///     "bookmarks": [Bookmark],  // user/play/skip/sleep, keyed to an item
///     "collections": [Collection]
///   }
/// }
/// ```
///
/// Items match existing library entries on RESTORE by uuid first and fall back
/// to relativePath (a uuid survives a rename; the path survives a re-import on
/// a fresh device). Records whose item doesn't exist are reported as skipped —
/// the backup never fabricates books the user doesn't have.
///
/// Deliberately NOT in the file: audio files, artwork, cloud credentials,
/// media-server links, sync task state — a backup is metadata, the library's
/// files and accounts stay where they are. `formatVersion` + ISO8601 dates
/// keep the format stable across app versions.
struct LibraryBackup: Codable {
  static let currentFormatVersion = 1

  let formatVersion: Int
  let createdAt: Date
  let app: String
  let appVersion: String?
  let library: Contents

  struct Contents: Codable {
    let lastPlayedPath: String?
    let items: [Item]
    let bookmarks: [Bookmark]
    let collections: [Collection]
  }

  struct Item: Codable {
    let uuid: String
    let relativePath: String
    /// "book" | "folder" | "bound" — the rawValue of LibraryItem.ItemType
    let type: String
    let title: String
    let details: String
    let originalFileName: String
    let duration: Double
    let currentTime: Double
    let percentCompleted: Double
    let isFinished: Bool
    let didNotFinish: Bool
    let note: String?
    let seriesName: String?
    let seriesOrder: Double?
    let speed: Double
    let lastPlayDate: Date?
    /// Position the item was arranged at (custom sort order)
    let orderRank: Int
  }

  struct Bookmark: Codable {
    let time: Double
    /// "user" | "play" | "skip" | "sleep" — BookmarkType rawValue
    let type: String
    let note: String?
    /// The owning item, by uuid (preferred) and path (fallback)
    let itemUuid: String
    let itemPath: String
  }

  struct Collection: Codable {
    let uuid: String
    let title: String
    /// Member items — both spellings recorded for the same reason as Item
    let itemPaths: [String]
    let itemUuids: [String]
  }
}

enum LibraryBackupError: LocalizedError, Equatable {
  case emptyLibrary
  case unsupportedFormat(Int)
  case unreadableFile

  var errorDescription: String? {
    switch self {
    case .emptyLibrary:
      return "backup_error_empty".localized
    case .unsupportedFormat(let version):
      return String.localizedStringWithFormat("backup_error_version".localized, version)
    case .unreadableFile:
      return "backup_error_unreadable".localized
    }
  }
}

struct LibraryRestoreReport {
  /// Items whose state was written back
  let itemsUpdated: Int
  /// Bookmarks actually created (existing ones count as updated)
  let bookmarksCreated: Int
  /// Collection memberships restored (new collections counted too)
  let collectionsRestored: Int
  /// Records that matched no library item — title or path for the user
  let skipped: [String]
}

/// Builds and applies `LibraryBackup`s. All decoding is forgiving — a field a
/// future version adds is ignored, a field v1 lacks decodes to nil/default —
/// and restore is idempotent: running it twice converges to the same state.
final class LibraryBackupService: BPLogger {
  let libraryService: LibraryService

  init(libraryService: LibraryService) {
    self.libraryService = libraryService
  }

  // MARK: - Export

  func export() throws -> LibraryBackup {
    let items = libraryService.filterContents(
      at: nil, query: nil, scope: nil, limit: nil, offset: nil
    ) ?? []

    guard !items.isEmpty else { throw LibraryBackupError.emptyLibrary }

    var bookmarks = [LibraryBackup.Bookmark]()
    for item in items where item.type != .folder {
      for type in [BookmarkType.user, .play, .skip, .sleep] {
        for bookmark in libraryService.getBookmarks(of: type, relativePath: item.relativePath) ?? [] {
          bookmarks.append(
            .init(
              time: bookmark.time,
              type: Self.bookmarkTypeName(type),
              note: bookmark.note,
              itemUuid: item.uuid,
              itemPath: item.relativePath
            )
          )
        }
      }
    }

    let collections = libraryService.fetchCollections().map { collection in
      /// Membership reads as paths; uuids go alongside so a renamed item still
      /// matches on restore
      let members = libraryService.fetchCollectionItems(uuid: collection.uuid)
      return LibraryBackup.Collection(
        uuid: collection.uuid,
        title: collection.title,
        itemPaths: members.map(\.relativePath),
        itemUuids: members.map(\.uuid)
      )
    }

    return LibraryBackup(
      formatVersion: LibraryBackup.currentFormatVersion,
      createdAt: Date(),
      app: "Narratix",
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
      library: .init(
        lastPlayedPath: libraryService.getLibraryLastItem()?.relativePath,
        items: items.map(Self.itemRecord),
        bookmarks: bookmarks,
        collections: collections
      )
    )
  }

  /// The backup file: JSON in the app's backup folder, timestamped so repeated
  /// exports keep a history and a share-sheet send has a real file to carry
  func exportFile() throws -> URL {
    let backup = try export()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(backup)

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    let folder = DataManager.getBackupFolderURL()
    let url = folder.appendingPathComponent("Narratix-Backup-\(formatter.string(from: Date())).json")
    try data.write(to: url)
    return url
  }

  private static func itemRecord(_ item: SimpleLibraryItem) -> LibraryBackup.Item {
    .init(
      uuid: item.uuid,
      relativePath: item.relativePath,
      type: Self.itemTypeName(item.type),
      title: item.title,
      details: item.details,
      originalFileName: item.originalFileName,
      duration: item.duration,
      currentTime: item.currentTime,
      percentCompleted: item.percentCompleted,
      isFinished: item.isFinished,
      didNotFinish: item.didNotFinish,
      note: item.note,
      seriesName: item.seriesName,
      seriesOrder: item.seriesOrder,
      speed: item.speed,
      lastPlayDate: item.lastPlayDate,
      orderRank: Int(item.orderRank)
    )
  }

  // MARK: - Restore

  /// Read a backup file (or the share sheet's copy of one) into the document
  func loadBackup(from url: URL) throws -> LibraryBackup {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url) else {
      throw LibraryBackupError.unreadableFile
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let backup: LibraryBackup
    do {
      backup = try decoder.decode(LibraryBackup.self, from: data)
    } catch {
      throw LibraryBackupError.unreadableFile
    }
    guard backup.formatVersion <= LibraryBackup.currentFormatVersion else {
      throw LibraryBackupError.unsupportedFormat(backup.formatVersion)
    }
    return backup
  }

  /// Write the backup's state onto the current library. Anything that can't be
  /// matched is skipped, not created — restore never invents books.
  @discardableResult
  func restore(_ backup: LibraryBackup) -> LibraryRestoreReport {
    var updated = 0
    var bookmarksCreated = 0
    var collectionsRestored = 0
    var skipped = [String]()

    for record in backup.library.items {
      guard let item = resolveItem(uuid: record.uuid, path: record.relativePath) else {
        skipped.append(record.title)
        continue
      }

      let path = item.relativePath
      /// Only owned progress fields move — the restore never "advances" a book
      /// the user is further into on this device
      if record.currentTime > item.currentTime {
        libraryService.updatePlaybackTime(
          relativePath: path, time: record.currentTime, date: record.lastPlayDate ?? Date(), scheduleSave: false
        )
      }
      /// Finished/DNF are terminal: a true moves forward, a false never
      /// clears what this device already marked — folder records cascade the
      /// flag into every descendant, so a false would un-finish whole folders
      if record.isFinished {
        libraryService.markAsFinished(flag: true, relativePath: path)
      }
      if record.didNotFinish {
        libraryService.markAsDidNotFinish(flag: true, relativePath: path)
      }
      /// A backup field only overwrites when it carries something — nil can
      /// mean "no note" or "the field didn't exist in that format version"
      if let note = record.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        libraryService.updateNote(note, at: path)
      }
      if let seriesName = record.seriesName,
        !seriesName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        libraryService.updateSeriesInfo(name: seriesName, order: record.seriesOrder, at: path)
      }
      libraryService.updateBookSpeed(at: path, speed: Float(record.speed))
      if item.details.isEmpty, !record.details.isEmpty {
        libraryService.updateDetails(at: path, details: record.details)
      }
      updated += 1
    }

    for record in backup.library.bookmarks {
      guard let item = resolveItem(uuid: record.itemUuid, path: record.itemPath),
        let type = Self.bookmarkType(named: record.type)
      else {
        skipped.append(record.itemPath)
        continue
      }
      if let existing = libraryService.getBookmark(
        at: record.time, relativePath: item.relativePath, type: type
      ) {
        if let note = record.note, existing.note != note {
          libraryService.addNote(note, bookmark: existing)
        }
        continue
      }
      if let created = libraryService.createBookmark(
        at: record.time, relativePath: item.relativePath, uuid: UUID().uuidString, type: type
      ) {
        if let note = record.note {
          libraryService.addNote(note, bookmark: created)
        }
        bookmarksCreated += 1
      }
    }

    for record in backup.library.collections {
      let paths = zip(record.itemUuids, record.itemPaths).compactMap { uuid, path in
        resolveItem(uuid: uuid, path: path)?.relativePath
      }
      guard !paths.isEmpty else {
        skipped.append(record.title)
        continue
      }
      /// Same-titled collection → merge into it; a bare uuid match counts too —
      /// creating twice would scatter membership
      let target =
        libraryService.fetchCollections().first(where: {
          $0.uuid == record.uuid || $0.title.localizedCaseInsensitiveCompare(record.title) == .orderedSame
        }) ?? libraryService.createCollection(title: record.title)
      if let target {
        libraryService.addToCollection(uuid: target.uuid, items: paths)
        collectionsRestored += 1
      }
    }

    if let lastPath = backup.library.lastPlayedPath,
      libraryService.getSimpleItem(with: lastPath) != nil {
      libraryService.setLibraryLastBook(with: lastPath)
    }

    return LibraryRestoreReport(
      itemsUpdated: updated,
      bookmarksCreated: bookmarksCreated,
      collectionsRestored: collectionsRestored,
      skipped: skipped
    )
  }

  /// String names for the int-backed item/bookmark types — the file format
  /// speaks names so a re-ordered enum can't corrupt an old backup
  private static func itemTypeName(_ type: SimpleItemType) -> String {
    switch type {
    case .book: return "book"
    case .folder: return "folder"
    case .bound: return "bound"
    }
  }

  private static func bookmarkTypeName(_ type: BookmarkType) -> String {
    switch type {
    case .user: return "user"
    case .play: return "play"
    case .skip: return "skip"
    case .sleep: return "sleep"
    }
  }

  private static func bookmarkType(named name: String) -> BookmarkType? {
    switch name {
    case "user": return .user
    case "play": return .play
    case "skip": return .skip
    case "sleep": return .sleep
    default: return nil
    }
  }

  /// Match an item by uuid first (survives renames), path second (survives
  /// re-import on a fresh install)
  private func resolveItem(uuid: String, path: String) -> SimpleLibraryItem? {
    libraryService.getSimpleItem(for: uuid) ?? libraryService.getSimpleItem(with: path)
  }
}
