//
//  ListeningState.swift
//  BookPlayerKit
//
//  Created by Gianni Carlo on 12/5/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import Foundation

/// An item's effective listening state, derived from its stored flags and
/// progress. `didNotFinish` wins over `isFinished` (a user can mark a finished
/// book DNF, though marking finished clears the flag), so the states stay
/// mutually exclusive without a stored enum to keep in sync.
public enum ListeningState: CaseIterable, Hashable {
  /// Never played — no progress and no user-marked state
  case notStarted
  /// Some progress recorded, neither finished nor abandoned
  case inProgress
  /// `isFinished` — the upstream binary state, unchanged
  case finished
  /// `didNotFinish` — user marked the item abandoned
  case didNotFinish
}

extension ListeningState {
  public init(
    didNotFinish: Bool,
    isFinished: Bool,
    currentTime: Double,
    percentCompleted: Double
  ) {
    if didNotFinish {
      self = .didNotFinish
    } else if isFinished {
      self = .finished
    } else if currentTime > 0 || percentCompleted > 0 {
      self = .inProgress
    } else {
      self = .notStarted
    }
  }
}

extension SimpleLibraryItem {
  public var listeningState: ListeningState {
    ListeningState(
      didNotFinish: didNotFinish,
      isFinished: isFinished,
      currentTime: currentTime,
      percentCompleted: percentCompleted
    )
  }
}
