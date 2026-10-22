//
//  LibraryService+Collections.swift
//  BookPlayerKit
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import CoreData
import Foundation

/// Collections + series metadata (Phase 3c — Library Organization).
///
/// Collections are user-made shelves: cross-cutting groups where an item can
/// belong to many collections (unlike `Folder`, which is a single-parent
/// tree). Series name + book number live on `LibraryItem` and power the
/// series/author browse surfaces.
///
/// Everything in this file is LOCAL-ONLY: no method emits through
/// `metadataPassthroughPublisher`, so no sync task can ever carry these fields
/// — `updateNote` takes the same posture. `SyncService.scheduleMetadataUpdate`
/// additionally strips the keys defensively.
extension LibraryService {
  // MARK: - Collections

  /// Every collection, title-sorted. The table stays small, so ordering happens
  /// in memory with `localizedStandardCompare` rather than in the fetch.
  public func fetchCollections() -> [SimpleCollection] {
    let context = dataManager.getContext()
    let fetch = ItemCollection.fetchRequest()

    return ((try? context.fetch(fetch)) ?? [])
      .map { SimpleCollection(from: $0) }
      .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }

  /// The collections the item at `relativePath` currently belongs to
  public func fetchCollections(containing relativePath: String) -> [SimpleCollection] {
    let context = dataManager.getContext()
    let fetch = ItemCollection.fetchRequest()
    /// Literal key: `#keyPath` can't traverse the to-many `items` (NSSet)
    fetch.predicate = NSPredicate(format: "ANY %K == %@", "items.relativePath", relativePath)

    return ((try? context.fetch(fetch)) ?? [])
      .map { SimpleCollection(from: $0) }
      .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }

  /// The subset of `relativePaths` already in the collection — the picker marks
  /// a row checked only when the whole selection is inside
  public func collectionMembership(uuid: String, of relativePaths: [String]) -> Set<String> {
    guard let collection = collectionReference(for: uuid) else { return [] }
    let memberPaths = Set(collection.itemsArray.compactMap(\.relativePath))
    return memberPaths.intersection(relativePaths)
  }

  /// Creates a collection. Returns nil on an empty/whitespace title — no
  /// name-uniqueness check: `uuid` is the identity, same-named shelves are legal.
  @discardableResult
  public func createCollection(title: String) -> SimpleCollection? {
    let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return nil }

    let context = dataManager.getContext()
    let collection = ItemCollection.create(in: context)
    collection.uuid = UUID().uuidString
    collection.title = cleaned
    dataManager.saveContext()

    return SimpleCollection(from: collection)
  }

  public func renameCollection(uuid: String, title: String) {
    let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty,
      let collection = collectionReference(for: uuid)
    else { return }

    collection.title = cleaned
    dataManager.saveContext()
  }

  /// Deletes the collection only — members survive (Nullify on both sides of
  /// the relationship) and stay in their folders.
  public func deleteCollection(uuid: String) {
    let context = dataManager.getContext()
    guard let collection = collectionReference(for: uuid, context: context) else { return }

    context.delete(collection)
    dataManager.saveContext()
  }

  /// Members of a collection, title-sorted
  public func fetchCollectionItems(uuid: String) -> [SimpleLibraryItem] {
    guard let collection = collectionReference(for: uuid) else { return [] }

    return collection.itemsArray
      .map { SimpleLibraryItem(from: $0) }
      .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }

  /// Adds the items at `relativePaths`. Already-member items are a no-op (the
  /// relationship is a set); unknown paths are skipped.
  public func addToCollection(uuid: String, items relativePaths: [String]) {
    let context = dataManager.getContext()
    guard let collection = collectionReference(for: uuid, context: context) else { return }

    for path in relativePaths {
      guard let item = getItem(with: path, context: context) else { continue }
      collection.addToItems(item)
    }
    dataManager.saveContext()
  }

  public func removeFromCollection(uuid: String, items relativePaths: [String]) {
    let context = dataManager.getContext()
    guard let collection = collectionReference(for: uuid, context: context) else { return }

    for path in relativePaths {
      guard let item = getItem(with: path, context: context) else { continue }
      collection.removeFromItems(item)
    }
    dataManager.saveContext()
  }

  private func collectionReference(for uuid: String, context: NSManagedObjectContext? = nil) -> ItemCollection? {
    let context = context ?? dataManager.getContext()
    let fetch = ItemCollection.fetchRequest()
    fetch.predicate = NSPredicate(format: "%K == %@", #keyPath(ItemCollection.uuid), uuid)
    fetch.fetchLimit = 1
    return try? context.fetch(fetch).first
  }

  // MARK: - Series metadata

  /// Writes the item's series name + book number (nil name clears both — a book
  /// number without a series is meaningless). Local-only, so like `updateNote`
  /// this emits NO metadata-passthrough event: the server never learns it.
  public func updateSeriesInfo(name: String?, order: Double?, at relativePath: String) {
    guard let item = self.getItem(with: relativePath) else { return }

    let cleaned = name?.trimmingCharacters(in: .whitespacesAndNewlines)
    item.seriesName = (cleaned?.isEmpty == false) ? cleaned : nil
    item.seriesOrder = item.seriesName == nil ? nil : order.map { NSNumber(value: $0) }

    self.dataManager.saveContext()
  }

  /// Every item carrying series metadata, grouped by series name. Groups are
  /// sorted by name; contents by book number (unordered last) then title.
  public func fetchSeriesGroups() -> [SimpleItemGroup] {
    let context = dataManager.getContext()
    let fetchRequest: NSFetchRequest<NSDictionary> = NSFetchRequest<NSDictionary>(entityName: "LibraryItem")
    fetchRequest.propertiesToFetch = SimpleLibraryItem.fetchRequestProperties
    fetchRequest.resultType = .dictionaryResultType
    fetchRequest.predicate = NSPredicate(
      format: "%K != nil AND %K != ''",
      #keyPath(LibraryItem.seriesName),
      #keyPath(LibraryItem.seriesName)
    )

    let results = try? context.fetch(fetchRequest) as? [[String: Any]]
    let items = parseFetchedItems(from: results, context: context) ?? []

    return Dictionary(grouping: items, by: { $0.seriesName ?? "" })
      .map { SimpleItemGroup(name: $0.key, items: sortSeriesItems($0.value)) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  /// Books and volumes grouped by author (`details`) — folders excluded, theirs
  /// is a generated contents summary. Both levels sorted alphabetically.
  public func fetchAuthorGroups() -> [SimpleItemGroup] {
    let context = dataManager.getContext()
    let fetchRequest: NSFetchRequest<NSDictionary> = NSFetchRequest<NSDictionary>(entityName: "LibraryItem")
    fetchRequest.propertiesToFetch = SimpleLibraryItem.fetchRequestProperties
    fetchRequest.resultType = .dictionaryResultType
    fetchRequest.predicate = NSPredicate(
      format: "%K != %d AND %K != nil AND %K != ''",
      #keyPath(LibraryItem.type),
      SimpleItemType.folder.rawValue,
      #keyPath(LibraryItem.details),
      #keyPath(LibraryItem.details)
    )

    let results = try? context.fetch(fetchRequest) as? [[String: Any]]
    let items = parseFetchedItems(from: results, context: context) ?? []

    return Dictionary(grouping: items, by: { $0.details })
      .map { name, items in
        SimpleItemGroup(
          name: name,
          items: items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        )
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  /// The series-detail ordering, in one place: `seriesOrder` ascending with
  /// unordered items last, title as the tiebreak
  func sortSeriesItems(_ items: [SimpleLibraryItem]) -> [SimpleLibraryItem] {
    items.sorted { lhs, rhs in
      switch (lhs.seriesOrder, rhs.seriesOrder) {
      case let (left?, right?):
        return left != right
          ? left < right
          : lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
      case (_?, nil):
        return true
      case (nil, _?):
        return false
      case (nil, nil):
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
      }
    }
  }
}
