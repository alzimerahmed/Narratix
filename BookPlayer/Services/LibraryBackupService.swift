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
  /// The name stamped into the backup's `app` field and its filenames —
  /// one literal for both surfaces
  static let appName = "Narratix"

  let libraryService: LibraryService

  init(libraryService: LibraryService) {
    self.libraryService = libraryService
  }

  // MARK: - Export

  func export() async throws -> LibraryBackup {
    /// Reads below go through the main-queue-confined viewContext — this
    /// method runs on a cooperative thread, so they hop onto the context's
    /// queue instead of racing main-thread work
    let items = await self.libraryService.performOnContext {
      self.libraryService.filterContents(
        at: nil, query: nil, scope: nil, limit: nil, offset: nil
      ) ?? []
    }

    guard !items.isEmpty else { throw LibraryBackupError.emptyLibrary }

    /// One grouped fetch for all bookmark types — four fetches per item was
    /// the export's dominant cost on big libraries, and it ran on the caller's
    /// actor; the grouped read happens on the store's background context
    let bookmarkedPaths = items.filter { $0.type != .folder }.map(\.relativePath)
    let bookmarksByItem = await self.libraryService.getBookmarks(forItemsAt: bookmarkedPaths)

    var bookmarks = [LibraryBackup.Bookmark]()
    for item in items where item.type != .folder {
      for bookmark in bookmarksByItem[item.relativePath] ?? [] {
        bookmarks.append(
          .init(
            time: bookmark.time,
            type: Self.bookmarkTypeName(bookmark.type),
            note: bookmark.note,
            itemUuid: item.uuid,
            itemPath: item.relativePath
          )
        )
      }
    }

    let collections = await self.libraryService.performOnContext {
      self.libraryService.fetchCollections().map { collection in
        /// Membership reads as paths; uuids go alongside so a renamed item still
        /// matches on restore
        let members = self.libraryService.fetchCollectionItems(uuid: collection.uuid)
        return LibraryBackup.Collection(
          uuid: collection.uuid,
          title: collection.title,
          itemPaths: members.map(\.relativePath),
          itemUuids: members.map(\.uuid)
        )
      }
    }

    return LibraryBackup(
      formatVersion: LibraryBackup.currentFormatVersion,
      createdAt: Date(),
      app: Self.appName,
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
      library: .init(
        lastPlayedPath: await self.libraryService.performOnContext { self.libraryService.getLibraryLastItem()?.relativePath },
        items: items.map(Self.itemRecord),
        bookmarks: bookmarks,
        collections: collections
      )
    )
  }

  /// The backup file: JSON in the app's library-backup folder (Application
  /// Support — Documents/BPBackup belongs to the sync-deleted flow), timestamped
  /// so repeated exports keep a history and a share-sheet send has a real file
  func exportFile() async throws -> URL {
    let backup = try await export()
    return try writeLocalCopy(data: try Self.encode(backup))
  }

  /// One timestamped-name format for the on-device copy and the share
  /// sheet's default filename — both produce "Narratix-Backup-…"
  static func backupFileName(for date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    return "\(appName)-Backup-\(formatter.string(from: date))"
  }

  /// Writes already-encoded backup JSON into the library-backup folder —
  /// `recordLocalCopy` reuses the exported document's bytes instead of
  /// re-running the export
  func writeLocalCopy(data: Data) throws -> URL {
    let folder = DataManager.getLibraryBackupFolderURL()
    let url = folder.appendingPathComponent(Self.backupFileName() + ".json")
    try data.write(to: url)
    return url
  }

  /// The encoder settings the share sheet and the local copy share — one
  /// byte shape regardless of which path wrote it
  static func encode(_ backup: LibraryBackup) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(backup)
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

  /// A real library backup is JSON of at most a few MB — a picked file could
  /// be anything, so the read caps out before the bytes land in memory
  private static let maxBackupFileSize = 64 * 1024 * 1024

  /// Read a backup file (or the share sheet's copy of one) into the document
  func loadBackup(from url: URL) throws -> LibraryBackup {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    guard fileSize <= Self.maxBackupFileSize else {
      throw LibraryBackupError.unreadableFile
    }
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
  func restore(_ backup: LibraryBackup) async -> LibraryRestoreReport {
    var updated = 0
    var bookmarksCreated = 0
    var collectionsRestored = 0
    var skipped = [String]()

    /// Every fetch and write below goes through the main-queue-confined
    /// viewContext — this method runs on a cooperative thread, so each record
    /// hops onto the context's queue instead of racing main-thread work
    for record in backup.library.items {
      /// One fetch + direct field writes per record, inside
      /// `applyRestoredState`: the batch emits no sync events (a restore is
      /// local state replay, not new intent for the server) and saves once —
      /// the per-field path cost a save and an `.update` job per field. Each
      /// hop also yields the queue, so a big restore keeps the UI breathing
      let applied = await self.libraryService.performOnContext {
        self.libraryService.applyRestoredState(
          uuid: record.uuid,
          relativePath: record.relativePath,
          state: .init(
            currentTime: record.currentTime,
            lastPlayDate: record.lastPlayDate,
            isFinished: record.isFinished,
            didNotFinish: record.didNotFinish,
            note: record.note,
            seriesName: record.seriesName,
            seriesOrder: record.seriesOrder,
            speed: record.speed,
            details: record.details
          )
        )
      }
      if applied {
        updated += 1
      } else {
        skipped.append(record.title)
      }
    }

    for record in backup.library.bookmarks {
      guard let type = Self.bookmarkType(named: record.type) else {
        skipped.append(record.itemPath)
        continue
      }
      let created = await self.libraryService.performOnContext {
        self.libraryService.applyRestoredBookmark(
          at: record.time,
          type: type,
          note: record.note,
          uuid: record.itemUuid,
          relativePath: record.itemPath
        )
      }
      if created {
        bookmarksCreated += 1
      }
    }

    for record in backup.library.collections {
      /// Membership resolves to live paths — a member the library doesn't
      /// have just doesn't attach
      let memberPaths = await self.libraryService.performOnContext {
        zip(record.itemUuids, record.itemPaths).compactMap { uuid, path in
          self.resolvePath(uuid: uuid, path: path)
        }
      }
      guard !memberPaths.isEmpty else {
        skipped.append(record.title)
        continue
      }
      /// Same-titled/uuid collection → merge, never duplicate
      let restored = await self.libraryService.performOnContext {
        self.libraryService.applyRestoredCollection(
          uuid: record.uuid,
          title: record.title,
          memberPaths: memberPaths
        )
      }
      if restored != nil {
        collectionsRestored += 1
      }
    }

    /// The whole batch's one save — every write above left the context dirty
    await self.libraryService.performOnContext {
      if let lastPath = backup.library.lastPlayedPath,
        self.libraryService.getSimpleItem(with: lastPath) != nil {
        self.libraryService.setLibraryLastBook(with: lastPath)
      }
      self.libraryService.saveRestoreBatch()
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

  /// Match an item's live path by uuid first (survives renames), path second
  /// (survives re-import on a fresh install)
  private func self.resolvePath(uuid: String, path: String) -> String? {
    if let byUuid = self.libraryService.getSimpleItem(for: uuid) {
      return byUuid.relativePath
    }
    return self.libraryService.getSimpleItem(with: path) != nil ? path : nil
  }
}
