//
//  LibraryService+Restore.swift
//  BookPlayerKit
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import CoreData
import Foundation

/// Backup-restore write paths (Phase 4 — backup batching).
///
/// A restore replays the device's OWN state: it is not user intent the server
/// needs to hear about, so these methods write managed objects directly —
/// none of the per-field `saveContext()` calls or passthrough events the
/// interactive APIs issue. One `saveRestoreBatch()` closes the batch.
///
/// The merge rules mirror what the restore's per-field calls did: progress
/// and terminal flags only move forward, a blank detail never overwrites.
extension LibraryService {
  /// A backup record's writable fields, as a value type so the app-layer
  /// backup service hands no managed objects — and none of its own types —
  /// across the framework boundary
  public struct RestoredItemState: Sendable {
    public var currentTime: Double
    public var lastPlayDate: Date?
    public var isFinished: Bool
    public var didNotFinish: Bool
    public var note: String?
    public var seriesName: String?
    public var seriesOrder: Double?
    public var speed: Double
    public var details: String

    public init(
      currentTime: Double,
      lastPlayDate: Date?,
      isFinished: Bool,
      didNotFinish: Bool,
      note: String?,
      seriesName: String?,
      seriesOrder: Double?,
      speed: Double,
      details: String
    ) {
      self.currentTime = currentTime
      self.lastPlayDate = lastPlayDate
      self.isFinished = isFinished
      self.didNotFinish = didNotFinish
      self.note = note
      self.seriesName = seriesName
      self.seriesOrder = seriesOrder
      self.speed = speed
      self.details = details
    }
  }

  /// The speed picker's bounds — a hand-edited or corrupt backup could carry
  /// anything
  private static let speedRange: ClosedRange<Float> = 0.5...4.0

  /// The managed item a backup record names — uuid first (survives renames),
  /// relativePath second (survives re-import on a fresh install)
  private func restoredItem(uuid: String, relativePath: String) -> LibraryItem? {
    let context = dataManager.getContext()
    let fetchRequest: NSFetchRequest<LibraryItem> = LibraryItem.fetchRequest()
    fetchRequest.predicate = NSPredicate(
      format: "%K == %@ OR %K == %@",
      #keyPath(LibraryItem.uuid), uuid,
      #keyPath(LibraryItem.relativePath), relativePath
    )
    fetchRequest.fetchLimit = 2
    guard let matches = try? context.fetch(fetchRequest) else { return nil }
    return matches.first(where: { $0.uuid == uuid }) ?? matches.first
  }

  /// Applies one backup record's fields to the item it resolves to — one
  /// fetch instead of the per-field calls' several, no saves, no events.
  /// - Returns: whether the record matched an item
  @discardableResult
  public func applyRestoredState(
    uuid: String,
    relativePath: String,
    state: RestoredItemState
  ) -> Bool {
    guard let item = restoredItem(uuid: uuid, relativePath: relativePath) else { return false }

    /// Clamps a hand-edited or corrupt backup to what the UI could produce
    item.speed = min(max(Float(state.speed), Self.speedRange.lowerBound), Self.speedRange.upperBound)
    /// Same fan-out `updateBookSpeed` does — a book's speed writes its
    /// parent folder's too
    item.folder?.speed = item.speed

    /// Progress only moves forward, capped inside the item's own duration
    let clampedTime = min(max(state.currentTime, 0), item.duration)
    if clampedTime > item.currentTime {
      item.currentTime = clampedTime
      item.lastPlayDate = state.lastPlayDate ?? Date()
      let progress = round(item.currentTime / item.duration * 100)
      item.percentCompleted = progress.isFinite ? progress : 0
      /// `recursiveFolderLastPlayedDateUpdate`'s walk, minus its per-folder
      /// event and save
      var parent = item.folder
      while let folder = parent {
        folder.lastPlayDate = item.lastPlayDate
        parent = folder.folder
      }
    }

    /// Same order the restore had: finished (which clears the flag), then DNF
    if state.isFinished {
      item.isFinished = true
      item.didNotFinish = false
    }
    if state.didNotFinish {
      item.didNotFinish = true
    }

    if let note = state.note?.trimmingCharacters(in: .whitespacesAndNewlines),
      !note.isEmpty {
      item.note = note
    }

    if let series = state.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !series.isEmpty {
      item.seriesName = series
      item.seriesOrder = state.seriesOrder.map { NSNumber(value: $0) }
    }

    /// A blank local detail takes the backup's — a real one wins
    if item.details?.isEmpty != false, !state.details.isEmpty {
      item.details = state.details
    }

    return true
  }

  /// One restored bookmark's merge: `createBookmark`'s floor + dedupe — an
  /// existing mark only takes the note — minus its save and UI event.
  /// - Returns: whether a new bookmark was inserted
  @discardableResult
  public func applyRestoredBookmark(
    at time: Double,
    type: BookmarkType,
    note: String?,
    uuid: String,
    relativePath: String
  ) -> Bool {
    guard
      let item = restoredItem(uuid: uuid, relativePath: relativePath),
      let itemPath = item.relativePath
    else { return false }

    let context = dataManager.getContext()
    let floored = floor(time)

    let fetchRequest: NSFetchRequest<Bookmark> = Bookmark.fetchRequest()
    fetchRequest.predicate = NSPredicate(
      format: "%K == %@ && type == %d && time == %f",
      #keyPath(Bookmark.item.relativePath),
      itemPath,
      type.rawValue,
      floored
    )
    fetchRequest.fetchLimit = 1
    if let existing = try? context.fetch(fetchRequest).first {
      if let note, existing.note != note {
        existing.note = note
      }
      return false
    }

    let bookmark = Bookmark(with: floored, type: type, context: context)
    bookmark.note = note
    item.addToBookmarks(bookmark)
    return true
  }

  /// One restored collection: merges into the shelf carrying the backup's
  /// uuid, else a same-titled one (case-insensitive, the restore's own merge
  /// rule), else creates — then attaches the member paths that still
  /// resolve. No per-call save.
  /// - Returns: the shelf written, nil for a blank title
  @discardableResult
  public func applyRestoredCollection(
    uuid: String,
    title: String,
    memberPaths: [String]
  ) -> SimpleCollection? {
    let context = dataManager.getContext()
    let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return nil }

    let collection: ItemCollection
    if let existing = collectionReference(for: uuid, context: context)
      ?? collectionReference(titled: cleaned, context: context) {
      collection = existing
      if collection.title != cleaned {
        collection.title = cleaned
      }
    } else {
      collection = ItemCollection.create(in: context)
      collection.uuid = uuid
      collection.title = cleaned
    }

    for path in memberPaths {
      guard let item = getItem(with: path, context: context) else { continue }
      collection.addToItems(item)
    }

    return SimpleCollection(from: collection)
  }

  /// A collection by title, case-insensitively — the restore merges into a
  /// same-named shelf instead of scattering membership over a duplicate
  private func collectionReference(titled title: String, context: NSManagedObjectContext) -> ItemCollection? {
    let fetch = ItemCollection.fetchRequest()
    fetch.predicate = NSPredicate(format: "%K ==[c] %@", #keyPath(ItemCollection.title), title)
    fetch.fetchLimit = 1
    return try? context.fetch(fetch).first
  }

  /// The one save that closes a restore batch — the per-record writes above
  /// saved nothing
  public func saveRestoreBatch() {
    dataManager.saveContext()
  }
}
