//
//  SimplePlaybackSession.swift
//  BookPlayerKit
//
//  Created by Gianni Carlo on 12/5/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import Foundation

/// Snapshot of one continuous listening session: when it started, where in the
/// book it ended (the position a "jump back" restores), and how long it ran.
/// Value type — the managed `PlaybackSession` never leaves its context.
public struct SimplePlaybackSession: Identifiable, Hashable {
  /// Stable identity for list rows and deletions — the managed object's URI,
  /// so a row can find its record again without holding a managed object
  public let id: String
  /// When the session started
  public let date: Date
  /// Book-time position where the session was last persisted (its restore point)
  public let position: Double
  /// Seconds the session ran between its start and its last update
  public let duration: Double
  /// Path of the item played — the identity `loadPlayer` resolves on restore
  public let itemRelativePath: String
  /// Item title captured at fetch time (the row's label; the item may since be gone)
  public let itemTitle: String

  public init(
    id: String,
    date: Date,
    position: Double,
    duration: Double,
    itemRelativePath: String,
    itemTitle: String
  ) {
    self.id = id
    self.date = date
    self.position = position
    self.duration = duration
    self.itemRelativePath = itemRelativePath
    self.itemTitle = itemTitle
  }
}

extension SimplePlaybackSession {
  public init?(from session: PlaybackSession) {
    guard
      let item = session.item,
      let relativePath = item.relativePath,
      let title = item.title
    else { return nil }

    self.init(
      id: session.objectID.uriRepresentation().absoluteString,
      date: session.date,
      position: session.position,
      duration: session.duration,
      itemRelativePath: relativePath,
      itemTitle: title
    )
  }
}
