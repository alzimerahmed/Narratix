//
//  PlaybackHistoryService.swift
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
import UIKit

/// Records a timeline of listening sessions — "where was I" for every play.
/// Each play→pause (or play→stop/switch/end) cycle becomes one `PlaybackSession`
/// row holding the position to restore.
///
/// The service is notification-driven (`.bookPlayed`, `.bookPaused`, `.bookEnd`,
/// `.bookPlaying`, app backgrounding) rather than hooked into `PlayerManager`,
/// keeping the player file untouched. It follows the CoreServices two-step
/// pattern: `init()` for a no-op placeholder, `setup(dataManager:)` for the
/// real one.
///
/// State lives on the main actor: the playback notifications it consumes are
/// all posted there.
@MainActor
final class PlaybackHistoryService {
  private var dataManager: DataManager?
  private var disposeBag = Set<AnyCancellable>()

  /// Fires after every session write so an open history view can refresh
  /// (a session ends and mid-play refreshes while the list is on screen)
  let updates = PassthroughSubject<Void, Never>()

  /// Session in flight: the item that started it and when. The `PlayableItem`
  /// reference stays live through pauses and item swaps — its `currentTime` is
  /// the position worth persisting.
  private var activeItem: PlayableItem?
  private var sessionStartedAt: Date?
  /// The persisted row for the active session (created on the first save so a
  /// mid-play force-quit still leaves a restorable position)
  private var sessionObjectID: NSManagedObjectID?
  private var lastPersistedAt: Date?

  /// How often an active session's position is persisted mid-play
  private static let persistInterval: TimeInterval = 15
  /// Sessions shorter than this are noise (a mistap on play) and dropped
  private static let minimumSessionDuration: TimeInterval = 2
  /// Most recent sessions kept per item — bounds storage
  private static let sessionsPerItem = 30

  /// `nonisolated` so the type stays usable as an `@Entry` default value —
  /// the placeholder does no actor-bound work; `setup` is the real start
  nonisolated init() {}

  func setup(dataManager: DataManager) {
    self.dataManager = dataManager
  }

  /// Starts the notification subscriptions. Called once at CoreServices setup —
  /// subscriptions live in `disposeBag` for the service's lifetime.
  func observePlayback() {
    NotificationCenter.default.publisher(for: .bookPlayed)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] notification in
        guard let item = notification.userInfo?["book"] as? PlayableItem else { return }
        self?.handleBookPlayed(item)
      }
      .store(in: &disposeBag)

    NotificationCenter.default.publisher(for: .bookPaused)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.endSession()
      }
      .store(in: &disposeBag)

    /// The ended book's session — `.bookEnd` can post after the next item was
    /// already loaded, so it closes with the TRACKED item's position, never
    /// the new one
    NotificationCenter.default.publisher(for: .bookEnd)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.endSession()
      }
      .store(in: &disposeBag)

    /// Fires every second while an item is loaded; throttled inside to refresh
    /// the row's position so a kill or crash leaves a recent restore point
    NotificationCenter.default.publisher(for: .bookPlaying)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.persistSessionPosition(throttled: true)
      }
      .store(in: &disposeBag)

    NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        /// Playback may continue in the background; keep the session alive but
        /// capture the position now so a kill loses little
        self?.persistSessionPosition(throttled: false)
      }
      .store(in: &disposeBag)
  }

  // MARK: - Session lifecycle

  private func handleBookPlayed(_ item: PlayableItem) {
    /// A new item starting closes whatever was playing before (a load swap
    /// doesn't post `.bookPaused`)
    if activeItem != nil {
      endSession()
    }

    activeItem = item
    sessionStartedAt = Date()
    sessionObjectID = nil
    lastPersistedAt = nil
  }

  /// Closes the active session: persists position + duration on its row,
  /// dropping rows too short to mean anything
  private func endSession() {
    guard let item = activeItem, let startedAt = sessionStartedAt else { return }

    let duration = Date().timeIntervalSince(startedAt)
    let position = item.currentTime
    let objectID = sessionObjectID

    activeItem = nil
    sessionStartedAt = nil
    sessionObjectID = nil
    lastPersistedAt = nil

    guard duration >= Self.minimumSessionDuration else {
      if let objectID {
        deleteRows(matching: [objectID])
      }
      return
    }

    upsertSession(
      objectID: objectID,
      itemRelativePath: item.relativePath,
      startedAt: startedAt,
      position: position,
      duration: duration
    )
    pruneSessions(for: item.relativePath)
    updates.send()
  }

  /// Refreshes the active session's row so it reflects the latest position
  private func persistSessionPosition(throttled: Bool) {
    guard
      let item = activeItem,
      let startedAt = sessionStartedAt
    else { return }

    if throttled,
       let lastPersistedAt,
       Date().timeIntervalSince(lastPersistedAt) < Self.persistInterval {
      return
    }

    let now = Date()
    upsertSession(
      objectID: sessionObjectID,
      itemRelativePath: item.relativePath,
      startedAt: startedAt,
      position: item.currentTime,
      duration: now.timeIntervalSince(startedAt)
    )
    lastPersistedAt = now
  }

  // MARK: - Reads (snapshots for UI)

  /// Most recent sessions first. The `limit` bounds the timeline the history
  /// view pages through.
  func fetchSessions(limit: Int? = 100) -> [SimplePlaybackSession] {
    guard let dataManager else { return [] }
    let context = dataManager.getContext()

    return context.performAndWait {
      let fetch = PlaybackSession.fetchRequest()
      fetch.sortDescriptors = [NSSortDescriptor(key: #keyPath(PlaybackSession.date), ascending: false)]
      fetch.relationshipKeyPathsForPrefetching = ["item"]
      if let limit {
        fetch.fetchLimit = limit
      }
      return (try? context.fetch(fetch))?
        .compactMap { SimplePlaybackSession(from: $0) } ?? []
    }
  }

  /// Sessions for one item, most recent first
  func fetchSessions(for relativePath: String, limit: Int? = nil) -> [SimplePlaybackSession] {
    guard let dataManager else { return [] }
    let context = dataManager.getContext()

    return context.performAndWait {
      let fetch = PlaybackSession.fetchRequest()
      fetch.predicate = NSPredicate(format: "item.relativePath == %@", relativePath)
      fetch.sortDescriptors = [NSSortDescriptor(key: #keyPath(PlaybackSession.date), ascending: false)]
      fetch.relationshipKeyPathsForPrefetching = ["item"]
      if let limit {
        fetch.fetchLimit = limit
      }
      return (try? context.fetch(fetch))?
        .compactMap { SimplePlaybackSession(from: $0) } ?? []
    }
  }

  func deleteSession(id: String) {
    guard
      let dataManager,
      let uri = URL(string: id),
      let objectID = dataManager.getContext().persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri)
    else { return }
    deleteRows(matching: [objectID])
  }

  func clear() {
    guard let dataManager else { return }
    let context = dataManager.getContext()

    context.performAndWait {
      let fetch = PlaybackSession.fetchRequest()
      (try? context.fetch(fetch))?.forEach { context.delete($0) }
    }
    dataManager.saveContext()
    updates.send()
  }

  // MARK: - Internals

  /// Creates or updates the session row. `date` stays the session START so the
  /// timeline order is stable while the position moves forward.
  private func upsertSession(
    objectID: NSManagedObjectID?,
    itemRelativePath: String,
    startedAt: Date,
    position: Double,
    duration: Double
  ) {
    guard let dataManager else { return }
    let context = dataManager.getContext()

    context.performAndWait {
      guard let item = libraryItem(for: itemRelativePath, context: context) else { return }

      let session: PlaybackSession
      if let objectID,
         let existing = try? context.existingObject(with: objectID) as? PlaybackSession {
        session = existing
      } else {
        session = PlaybackSession.create(in: context)
        session.date = startedAt
        session.item = item
        /// A fresh objectID is temporary until save; pinning it here keeps the
        /// in-memory handle valid across updates instead of duplicating rows
        try? context.obtainPermanentIDs(for: [session])
        sessionObjectID = session.objectID
      }

      session.position = position
      session.duration = duration
    }
    dataManager.saveContext()
    /// The throttled tick shouldn't churn subscribers — only session ENDS and
    /// deletes matter to a list (row contents barely move mid-session)
  }

  /// Keeps the most recent `sessionsPerItem` rows per item
  private func pruneSessions(for relativePath: String) {
    guard let dataManager else { return }
    let context = dataManager.getContext()

    context.performAndWait {
      let fetch = PlaybackSession.fetchRequest()
      fetch.predicate = NSPredicate(format: "item.relativePath == %@", relativePath)
      fetch.sortDescriptors = [NSSortDescriptor(key: #keyPath(PlaybackSession.date), ascending: false)]
      guard let sessions = try? context.fetch(fetch), sessions.count > Self.sessionsPerItem else { return }
      sessions.dropFirst(Self.sessionsPerItem).forEach { context.delete($0) }
    }
    dataManager.saveContext()
  }

  private func deleteRows(matching objectIDs: [NSManagedObjectID]) {
    guard let dataManager else { return }
    let context = dataManager.getContext()

    context.performAndWait {
      for objectID in objectIDs {
        if let session = try? context.existingObject(with: objectID) {
          context.delete(session)
        }
      }
    }
    dataManager.saveContext()
    updates.send()
  }

  /// `BookPlayerKit.` qualification is load-bearing: the SDK's
  /// `DeveloperToolsSupport.LibraryItem` makes the bare name ambiguous
  private func libraryItem(for relativePath: String, context: NSManagedObjectContext) -> BookPlayerKit.LibraryItem? {
    let fetch = BookPlayerKit.LibraryItem.fetchRequest()
    /// Literal key: `#keyPath` rejects the module-qualified type
    fetch.predicate = NSPredicate(format: "%K == %@", "relativePath", relativePath)
    fetch.fetchLimit = 1
    return try? context.fetch(fetch).first
  }
}
