//
//  QueueCounts.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import Combine
import Foundation

/// Pending-task count per queue key, published by the engine that owns every lane.
/// A drained lane is simply absent from the snapshot; `count(in:)` reads it as zero.
public struct QueueCounts: Equatable {
  /// Every queued task per lane, parked ones included
  public let byQueueKey: [String: Int]
  /// Parked tasks per lane (a subset of `byQueueKey`)
  public let pausedByQueueKey: [String: Int]
  /// Lanes that can't make progress until a parked task is resumed: a lane-level pause
  /// at their head, or an account-level pause holding every server lane
  public let blockedQueueKeys: Set<String>
  /// Lanes the user held from Queued Tasks: no task is parked, but the lane's worker
  /// retires instead of popping. Folded in by `SyncQueueService.observeQueueCounts` so a
  /// held lane reads idle to anything waiting on it
  public let userPausedQueueKeys: Set<String>

  public init(
    byQueueKey: [String: Int] = [:],
    pausedByQueueKey: [String: Int] = [:],
    blockedQueueKeys: Set<String> = [],
    userPausedQueueKeys: Set<String> = []
  ) {
    self.byQueueKey = byQueueKey
    self.pausedByQueueKey = pausedByQueueKey
    self.blockedQueueKeys = blockedQueueKeys
    self.userPausedQueueKeys = userPausedQueueKeys
  }

  /// Every queued task across all lanes
  public var total: Int { byQueueKey.values.reduce(0, +) }

  /// Every parked task across all lanes
  public var totalPaused: Int { pausedByQueueKey.values.reduce(0, +) }

  public func count(in queueKey: String) -> Int { byQueueKey[queueKey] ?? 0 }

  public func pausedCount(in queueKey: String) -> Int { pausedByQueueKey[queueKey] ?? 0 }

  public func isBlocked(_ queueKey: String) -> Bool { blockedQueueKeys.contains(queueKey) }

  /// The user held this lane in Queued Tasks — a hold, not a fault (`isBlocked` stays
  /// for lanes waiting on a parked task)
  public func isUserPaused(_ queueKey: String) -> Bool { userPausedQueueKeys.contains(queueKey) }

  /// Nothing in the lane can run: it's empty, holds only parked tasks, is blocked, or
  /// the user held it
  public func isIdle(_ queueKey: String) -> Bool {
    isBlocked(queueKey)
      || isUserPaused(queueKey)
      || count(in: queueKey) == pausedCount(in: queueKey)
  }
}

extension Publisher where Output == QueueCounts, Failure == Never {
  /// `true` whenever the given lane has nothing left it can run (`isIdle`): a parked task
  /// never finishes on its own, so waiting on it would only hold the window open.
  /// Background refresh waits on the `sync` lane through this, so the policy reads the
  /// same at the call site and in tests.
  public func laneDrained(_ queueKey: String) -> AnyPublisher<Bool, Never> {
    map { $0.isIdle(queueKey) }.eraseToAnyPublisher()
  }
}
