//
//  ListeningQueueService.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/5/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import Combine
import CoreData
import Foundation

/// The user-managed listening queue ("Up Next"): ordered and deduplicated,
/// persisted in Core Data so it survives restarts and disappears together with
/// its items (cascade). Distinct from folder auto-play chaining — the queue is
/// explicit ordering the player consults first when advancing.
///
/// Entry points follow the CoreServices two-step pattern: `init()` for a safe
/// placeholder (every method no-ops until `setup`), `setup(dataManager:)` for
/// the real one. All work runs on the view context, wrapped in `performAndWait`
/// so callers can be on any queue.
final class ListeningQueueService {
  private var dataManager: DataManager?

  /// Fires after every mutation so queue views can refresh
  let updates = PassthroughSubject<Void, Never>()

  init() {}

  func setup(dataManager: DataManager) {
    self.dataManager = dataManager
  }

  /// Ordered snapshots of the queued items. Stale entries (their item was
  /// deleted through another path) are pruned on the way out.
  func fetchQueue() -> [SimpleLibraryItem] {
    guard let dataManager else { return [] }
    let context = dataManager.getContext()

    var stale = [ListeningQueueItem]()
    let items: [SimpleLibraryItem] = context.performAndWait {
      let entries = fetchEntries(context: context)
      var items = [SimpleLibraryItem]()
      for entry in entries {
        if let item = entry.item {
          items.append(SimpleLibraryItem(from: item))
        } else {
          stale.append(entry)
        }
      }
      return items
    }

    if !stale.isEmpty {
      delete(stale, context: context, dataManager: dataManager)
    }

    return items
  }

  func isQueued(relativePath: String) -> Bool {
    guard let dataManager else { return false }
    let context = dataManager.getContext()
    return context.performAndWait {
      entry(for: relativePath, context: context) != nil
    }
  }

  /// One fetch answering "which of these are queued" — the options menu's
  /// all-queued check used to fetch once per selected item
  func queuedPaths(_ relativePaths: [String]) -> Set<String> {
    guard let dataManager, !relativePaths.isEmpty else { return [] }
    let context = dataManager.getContext()
    return context.performAndWait {
      let fetch = ListeningQueueItem.fetchRequest()
      fetch.predicate = NSPredicate(format: "item.relativePath IN %@", relativePaths)
      fetch.relationshipKeyPathsForPrefetching = ["item"]
      let entries = (try? context.fetch(fetch)) ?? []
      return Set(entries.compactMap { $0.item?.relativePath })
    }
  }

  /// Appends the item at the queue's tail; keeps position when already queued
  func enqueue(_ relativePath: String) {
    insert(relativePath, atHead: false)
  }

  /// Inserts the item at the queue's head ("Play Next"); an already-queued
  /// item moves to the head instead of staying put
  func enqueueNext(_ relativePath: String) {
    insert(relativePath, atHead: true)
  }

  func remove(_ relativePath: String) {
    guard let dataManager else { return }
    let context = dataManager.getContext()

    context.performAndWait {
      if let entry = entry(for: relativePath, context: context) {
        context.delete(entry)
        renumber(context: context)
      }
    }
    dataManager.saveContext()
    updates.send()
  }

  func removeAll(_ relativePaths: [String]) {
    guard let dataManager else { return }
    let context = dataManager.getContext()

    context.performAndWait {
      for relativePath in relativePaths {
        if let entry = entry(for: relativePath, context: context) {
          context.delete(entry)
        }
      }
      renumber(context: context)
    }
    dataManager.saveContext()
    updates.send()
  }

  /// Reorders the queue, matching `List.onMove`'s offsets contract
  func move(fromOffsets source: IndexSet, toOffset destination: Int) {
    guard let dataManager else { return }
    let context = dataManager.getContext()

    context.performAndWait {
      var entries = fetchEntries(context: context)
      entries.move(fromOffsets: source, toOffset: destination)
      for (index, entry) in entries.enumerated() {
        entry.order = Int16(index)
      }
    }
    dataManager.saveContext()
    updates.send()
  }

  /// Consumes and returns the queue's head — the player's "next queued item".
  /// Entries that no longer resolve are dropped and the walk continues, so a
  /// broken row can never stall the queue.
  func dequeueNext() -> SimpleLibraryItem? {
    guard let dataManager else { return nil }
    let context = dataManager.getContext()

    var result: SimpleLibraryItem?
    var dropped = false
    context.performAndWait {
      let entries = fetchEntries(context: context)
      for entry in entries {
        if let item = entry.item {
          result = SimpleLibraryItem(from: item)
          context.delete(entry)
          dropped = true
          break
        } else {
          context.delete(entry)
          dropped = true
        }
      }
      if dropped {
        renumber(context: context)
      }
    }
    if dropped {
      dataManager.saveContext()
      updates.send()
    }
    return result
  }

  func clear() {
    guard let dataManager else { return }
    let context = dataManager.getContext()

    context.performAndWait {
      fetchEntries(context: context).forEach { context.delete($0) }
    }
    dataManager.saveContext()
    updates.send()
  }

  func count() -> Int {
    guard let dataManager else { return 0 }
    let context = dataManager.getContext()
    let fetch = ListeningQueueItem.fetchRequest()
    return (try? context.count(for: fetch)) ?? 0
  }

  // MARK: - Internals

  private func insert(_ relativePath: String, atHead: Bool) {
    guard let dataManager else { return }
    let context = dataManager.getContext()

    context.performAndWait {
      if let existing = entry(for: relativePath, context: context) {
        /// Already queued: a head insert still moves it to the front, a tail
        /// enqueue keeps its position
        if atHead {
          existing.order = -1
          renumber(context: context)
        }
        return
      }
      guard let item = context.libraryItem(for: relativePath) else { return }

      let entry = ListeningQueueItem.create(in: context)
      /// A head insert lands first once `renumber` normalizes to 0…n-1
      entry.order = atHead ? -1 : Int16(fetchEntries(context: context).count)
      entry.item = item
      renumber(context: context)
    }
    dataManager.saveContext()
    updates.send()
  }

  private func fetchEntries(context: NSManagedObjectContext) -> [ListeningQueueItem] {
    let fetch = ListeningQueueItem.fetchRequest()
    fetch.sortDescriptors = [NSSortDescriptor(key: #keyPath(ListeningQueueItem.order), ascending: true)]
    fetch.relationshipKeyPathsForPrefetching = ["item"]
    return (try? context.fetch(fetch)) ?? []
  }

  private func entry(for relativePath: String, context: NSManagedObjectContext) -> ListeningQueueItem? {
    let fetch = ListeningQueueItem.fetchRequest()
    fetch.predicate = NSPredicate(format: "item.relativePath == %@", relativePath)
    fetch.fetchLimit = 1
    return try? context.fetch(fetch).first
  }

  /// Contiguous 0…n-1 in the stored order — the only invariants a move or an
  /// insert has to keep
  private func renumber(context: NSManagedObjectContext) {
    for (index, entry) in fetchEntries(context: context).enumerated() {
      entry.order = Int16(index)
    }
  }

  private func delete(_ entries: [ListeningQueueItem], context: NSManagedObjectContext, dataManager: DataManager) {
    context.performAndWait {
      entries.forEach { context.delete($0) }
      renumber(context: context)
    }
    dataManager.saveContext()
    updates.send()
  }
}
